///////////////////////////////////////////////////////////////////////////////
//
// File:        rtl/axi4_lite/axi4_lite_slave.sv
// Author:      Abhishek Dhakad
// Date:        2025
// Description: AXI4-Lite Slave Module
//
//              Features:
//              ✓ 8 memory-mapped registers (CTRL, STATUS, DATA_TX, etc.)
//              ✓ Full AXI4-Lite handshake protocol
//              ✓ Write FSM handles AW/W in any order
//              ✓ Write Strobe (WSTRB) byte-level writes
//              ✓ Read-only registers (writes ignored)
//              ✓ Write-1-to-Clear register (IRQ_STAT)
//              ✓ Address range checking with SLVERR response
//              ✓ Fully synchronous, synthesizable design
//
// Architecture:
//              ┌─────────────────────────────────────────┐
//              │           AXI4-LITE SLAVE                │
//              │                                         │
//              │  ┌──────────┐    ┌──────────────────┐  │
//              │  │ Write    │    │ Register File     │  │
//              │  │ FSM      │───>│ reg[0]: CTRL      │  │
//  AW ────────>│  │          │    │ reg[1]: STATUS    │  │
//  W  ────────>│  │ AW+W     │    │ reg[2]: DATA_TX   │  │
//  B  <────────│  │ latch    │    │ reg[3]: DATA_RX   │  │
//              │  └──────────┘    │ reg[4]: IRQ_EN    │  │
//              │                  │ reg[5]: IRQ_STAT  │  │
//              │  ┌──────────┐    │ reg[6]: SCRATCH   │  │
//  AR ────────>│  │ Read     │    │ reg[7]: VERSION   │  │
//  R  <────────│  │ FSM      │───>│                   │  │
//              │  └──────────┘    └──────────────────┘  │
//              └─────────────────────────────────────────┘
//
///////////////////////////////////////////////////////////////////////////////

module axi4_lite_slave
  import axi_pkg::*;            // Import our package (response codes, etc.)
#(
  parameter int ADDR_WIDTH = 32,  // Address bus width
  parameter int DATA_WIDTH = 32   // Data bus width
)(
  // Port: AXI4-Lite slave interface
  // Using SystemVerilog interface with slave modport
  axi4_lite_if.slave  slv
);

  // ═══════════════════════════════════════════════════════════
  // LOCAL PARAMETERS (calculated from input parameters)
  // ═══════════════════════════════════════════════════════════

  // How many byte strobe bits we need
  // DATA_WIDTH=32 → 4 bytes → STRB_WIDTH=4
  localparam int STRB_WIDTH = DATA_WIDTH / 8;

  // Address bits used for register selection
  // For 32-bit data: each register is 4 bytes
  // Bits [1:0] = byte offset within word (we ignore these)
  // Bits [4:2] = register index (3 bits for 8 registers)
  localparam int ADDR_LSB = $clog2(DATA_WIDTH / 8);  // = 2 for 32-bit
  localparam int ADDR_MSB = ADDR_LSB + $clog2(NUM_REGS) - 1; // = 4

  // Maximum valid address (addresses >= this are out of range)
  localparam int ADDR_MAX = NUM_REGS * (DATA_WIDTH / 8);  // = 32 = 0x20

  // ═══════════════════════════════════════════════════════════
  // REGISTER FILE
  // 8 registers, each DATA_WIDTH bits wide
  // ═══════════════════════════════════════════════════════════
  logic [DATA_WIDTH-1:0] registers [NUM_REGS];

  // ═══════════════════════════════════════════════════════════
  // WRITE FSM
  //
  // Kyun FSM chahiye:
  // AW channel (address) aur W channel (data) INDEPENDENT hain.
  // Dono kisi bhi order mein aa sakte hain:
  //   - AW pehle, W baad mein
  //   - W pehle, AW baad mein
  //   - AW aur W saath mein (same clock cycle)
  //
  // Isliye FSM track karta hai ki kya mila hai aur kya pending hai.
  // ═══════════════════════════════════════════════════════════

  // FSM States
  typedef enum logic [1:0] {
    S_WR_IDLE    = 2'b00,  // Waiting - kuch nahi aaya abhi
    S_WR_GOT_AW  = 2'b01,  // Address mila, data ka wait hai
    S_WR_GOT_W   = 2'b10,  // Data mila, address ka wait hai
    S_WR_RESP    = 2'b11   // Dono mile, response bhej rahe hain
  } wr_state_e;

  wr_state_e wr_state_q, wr_state_d;  // _q = current (flop), _d = next (comb)

  // Latches: Jab AW ya W pehle aaye, uski value store karte hain
  logic [ADDR_WIDTH-1:0] aw_addr_q;    // Latched write address
  logic [DATA_WIDTH-1:0] w_data_q;     // Latched write data
  logic [STRB_WIDTH-1:0] w_strb_q;     // Latched write strobes

  // ═══════════════════════════════════════════════════════════
  // READ FSM (simpler than write - only 2 states)
  // ═══════════════════════════════════════════════════════════
  typedef enum logic {
    S_RD_IDLE = 1'b0,   // Waiting for read address
    S_RD_RESP = 1'b1    // Sending read data back
  } rd_state_e;

  rd_state_e rd_state_q, rd_state_d;

  logic [ADDR_WIDTH-1:0] ar_addr_q;   // Latched read address

  // ═══════════════════════════════════════════════════════════
  // HANDSHAKE DETECTION
  // Handshake = VALID && READY on same clock edge
  // Yeh signals simplify karte hain baaki logic ko
  // ═══════════════════════════════════════════════════════════
  logic aw_fire;  // AW channel handshake happened
  logic w_fire;   // W channel handshake happened
  logic b_fire;   // B channel handshake happened
  logic ar_fire;  // AR channel handshake happened
  logic r_fire;   // R channel handshake happened

  assign aw_fire = slv.awvalid & slv.awready;
  assign w_fire  = slv.wvalid  & slv.wready;
  assign b_fire  = slv.bvalid  & slv.bready;
  assign ar_fire = slv.arvalid & slv.arready;
  assign r_fire  = slv.rvalid  & slv.rready;

  // ═══════════════════════════════════════════════════════════
  // WRITE FSM: State Register (Sequential Block)
  //
  // Yeh block sirf state update karta hai har clock edge par.
  // Reset mein IDLE state par jaata hai.
  // ═══════════════════════════════════════════════════════════
  always_ff @(posedge slv.aclk or negedge slv.aresetn) begin
    if (!slv.aresetn) begin
      wr_state_q <= S_WR_IDLE;
    end else begin
      wr_state_q <= wr_state_d;
    end
  end

  // ═══════════════════════════════════════════════════════════
  // WRITE FSM: Next State Logic (Combinational Block)
  //
  // Current state + inputs → Next state decide karta hai
  // ═══════════════════════════════════════════════════════════
  always_comb begin
    // Default: stay in current state
    wr_state_d = wr_state_q;

    case (wr_state_q)
      // ─────────────────────────────────────────
      // IDLE: Waiting for AW and/or W
      // ─────────────────────────────────────────
      S_WR_IDLE: begin
        if (aw_fire && w_fire) begin
          // CASE 1: Dono saath aaye → seedha response
          wr_state_d = S_WR_RESP;
        end else if (aw_fire) begin
          // CASE 2: Sirf address aaya → data ka wait
          wr_state_d = S_WR_GOT_AW;
        end else if (w_fire) begin
          // CASE 3: Sirf data aaya → address ka wait
          wr_state_d = S_WR_GOT_W;
        end
      end

      // ─────────────────────────────────────────
      // GOT_AW: Address mil chuka, data ka wait
      // ─────────────────────────────────────────
      S_WR_GOT_AW: begin
        if (w_fire) begin
          // Data aa gaya → ab response de sakte hain
          wr_state_d = S_WR_RESP;
        end
      end

      // ─────────────────────────────────────────
      // GOT_W: Data mil chuka, address ka wait
      // ─────────────────────────────────────────
      S_WR_GOT_W: begin
        if (aw_fire) begin
          // Address aa gaya → ab response de sakte hain
          wr_state_d = S_WR_RESP;
        end
      end

      // ─────────────────────────────────────────
      // RESP: Response bhej rahe hain, master ke accept ka wait
      // ─────────────────────────────────────────
      S_WR_RESP: begin
        if (b_fire) begin
          // Master ne response accept kar liya → wapas IDLE
          wr_state_d = S_WR_IDLE;
        end
      end

      default: wr_state_d = S_WR_IDLE;
    endcase
  end

  // ═══════════════════════════════════════════════════════════
  // WRITE: AW and W Latching
  //
  // Jab AW ya W handshake hota hai, value store karte hain.
  // Kyunki dono alag time par aa sakte hain, pehle waale ko
  // yaad rakhna padta hai jab tak doosra na aaye.
  // ═══════════════════════════════════════════════════════════
  always_ff @(posedge slv.aclk or negedge slv.aresetn) begin
    if (!slv.aresetn) begin
      aw_addr_q <= '0;
      w_data_q  <= '0;
      w_strb_q  <= '0;
    end else begin
      // Latch address when AW handshake fires
      if (aw_fire) begin
        aw_addr_q <= slv.awaddr;
      end
      // Latch data when W handshake fires
      if (w_fire) begin
        w_data_q <= slv.wdata;
        w_strb_q <= slv.wstrb;
      end
    end
  end

  // ═══════════════════════════════════════════════════════════
  // WRITE: AWREADY and WREADY Generation
  //
  // AWREADY: Slave tab ready hai address lene ke liye jab:
  //   - IDLE state mein hai (fresh transaction)
  //   - GOT_W state mein hai (data mil chuka, address chahiye)
  //
  // WREADY: Slave tab ready hai data lene ke liye jab:
  //   - IDLE state mein hai (fresh transaction)
  //   - GOT_AW state mein hai (address mil chuka, data chahiye)
  // ═══════════════════════════════════════════════════════════
  assign slv.awready = (wr_state_q == S_WR_IDLE) || (wr_state_q == S_WR_GOT_W);
  assign slv.wready  = (wr_state_q == S_WR_IDLE) || (wr_state_q == S_WR_GOT_AW);

  // ═══════════════════════════════════════════════════════════
  // WRITE: Final Address, Data, Strobe Selection
  //
  // Problem: When both AW+W arrive same cycle, we use direct
  //          signals. When they arrive separately, we use
  //          latched values. This mux selects correctly.
  // ═══════════════════════════════════════════════════════════
  logic [ADDR_WIDTH-1:0] wr_addr;   // Final address for write
  logic [DATA_WIDTH-1:0] wr_data;   // Final data for write
  logic [STRB_WIDTH-1:0] wr_strb;   // Final strobes for write
  logic                  wr_en;     // Write enable (1 clock pulse)

  always_comb begin
    // Defaults
    wr_addr = aw_addr_q;   // Use latched by default
    wr_data = w_data_q;
    wr_strb = w_strb_q;
    wr_en   = 1'b0;

    case (wr_state_q)
      S_WR_IDLE: begin
        if (aw_fire && w_fire) begin
          // Both arriving NOW → use direct bus signals
          wr_addr = slv.awaddr;
          wr_data = slv.wdata;
          wr_strb = slv.wstrb;
          wr_en   = 1'b1;
        end
      end

      S_WR_GOT_AW: begin
        if (w_fire) begin
          // Address was latched before, data arriving NOW
          wr_addr = aw_addr_q;      // Use LATCHED address
          wr_data = slv.wdata;      // Use CURRENT data
          wr_strb = slv.wstrb;      // Use CURRENT strobes
          wr_en   = 1'b1;
        end
      end

      S_WR_GOT_W: begin
        if (aw_fire) begin
          // Data was latched before, address arriving NOW
          wr_addr = slv.awaddr;     // Use CURRENT address
          wr_data = w_data_q;       // Use LATCHED data
          wr_strb = w_strb_q;       // Use LATCHED strobes
          wr_en   = 1'b1;
        end
      end

      default: wr_en = 1'b0;
    endcase
  end

  // Register index from address
  logic [$clog2(NUM_REGS)-1:0] wr_idx;
  assign wr_idx = wr_addr[ADDR_MSB:ADDR_LSB];

  // Is the write address in valid range?
  logic wr_addr_ok;
  assign wr_addr_ok = (wr_addr[ADDR_WIDTH-1:0] < ADDR_MAX[ADDR_WIDTH-1:0]);

  // ═══════════════════════════════════════════════════════════
  // REGISTER FILE: Write Logic
  //
  // Yeh main block hai jahan actual register values update hoti hain.
  // Har register ka apna behavior hai:
  //   R/W:  Normal read/write
  //   R/O:  Software write IGNORED (hardware controls value)
  //   W1C:  Writing '1' to a bit CLEARS that bit to '0'
  // ═══════════════════════════════════════════════════════════
  always_ff @(posedge slv.aclk or negedge slv.aresetn) begin
    if (!slv.aresetn) begin
      // ──────────────────────────────────
      // RESET: All registers to default values
      // ──────────────────────────────────
      registers[REG_CTRL]     <= '0;
      registers[REG_STATUS]   <= '0;
      registers[REG_DATA_TX]  <= '0;
      registers[REG_DATA_RX]  <= '0;
      registers[REG_IRQ_EN]   <= '0;
      registers[REG_IRQ_STAT] <= '0;
      registers[REG_SCRATCH]  <= '0;
      registers[REG_VERSION]  <= IP_VERSION;  // Hardcoded value

    end else begin

      // ──────────────────────────────────
      // HARDWARE-DRIVEN UPDATES
      // (These happen every cycle, independent of AXI writes)
      // In a real SoC, these would come from actual hardware signals
      // ──────────────────────────────────

      // VERSION is constant - always overwrite to prevent corruption
      registers[REG_VERSION] <= IP_VERSION;

      // STATUS register: mirrors some control bits
      // Bit[0] = enabled (mirrors CTRL[0])
      // In real design: busy flag, FIFO full/empty, etc.
      registers[REG_STATUS][0]    <= registers[REG_CTRL][0];
      registers[REG_STATUS][31:1] <= '0;

      // DATA_RX: In real design, comes from peripheral (SPI/I2C/UART RX)
      // For testing, we loopback DATA_TX → DATA_RX
      registers[REG_DATA_RX] <= registers[REG_DATA_TX];

      // ──────────────────────────────────
      // AXI WRITE OPERATION
      // Only happens when wr_en is high AND address is valid
      // ──────────────────────────────────
      if (wr_en && wr_addr_ok) begin
        case (wr_idx)

          // ── CTRL Register (R/W) ──
          // Normal read/write with byte strobes
          REG_CTRL: begin
            for (int b = 0; b < STRB_WIDTH; b++) begin
              if (wr_strb[b]) begin
                // +: is "indexed part select"
                // b=0: registers[0][0+:8] = registers[0][7:0]
                // b=1: registers[0][8+:8] = registers[0][15:8]
                // b=2: registers[0][16+:8] = registers[0][23:16]
                // b=3: registers[0][24+:8] = registers[0][31:24]
                registers[REG_CTRL][b*8 +: 8] <= wr_data[b*8 +: 8];
              end
            end
          end

          // ── STATUS Register (READ-ONLY) ──
          // Write attempts are SILENTLY IGNORED
          // We don't generate an error - this is standard practice
          REG_STATUS: begin
            // Do nothing - hardware controls this register
          end

          // ── DATA_TX Register (R/W) ──
          REG_DATA_TX: begin
            for (int b = 0; b < STRB_WIDTH; b++) begin
              if (wr_strb[b]) begin
                registers[REG_DATA_TX][b*8 +: 8] <= wr_data[b*8 +: 8];
              end
            end
          end

          // ── DATA_RX Register (READ-ONLY) ──
          REG_DATA_RX: begin
            // Do nothing - hardware/loopback controls this
          end

          // ── IRQ_EN Register (R/W) ──
          REG_IRQ_EN: begin
            for (int b = 0; b < STRB_WIDTH; b++) begin
              if (wr_strb[b]) begin
                registers[REG_IRQ_EN][b*8 +: 8] <= wr_data[b*8 +: 8];
              end
            end
          end

          // ── IRQ_STAT Register (WRITE-1-TO-CLEAR) ──
          // This is special! Writing a '1' bit CLEARS that bit.
          // Writing a '0' bit leaves it unchanged.
          //
          // Real use case:
          //   - Hardware SETS bits when interrupt occurs
          //   - Software CLEARS bits by writing '1' to acknowledge
          //
          // Example:
          //   IRQ_STAT = 0x05 (bits 0 and 2 are set)
          //   Software writes 0x01 (clear bit 0 only)
          //   IRQ_STAT becomes 0x04 (only bit 2 remains)
          REG_IRQ_STAT: begin
            for (int b = 0; b < STRB_WIDTH; b++) begin
              if (wr_strb[b]) begin
                for (int bit_idx = 0; bit_idx < 8; bit_idx++) begin
                  if (wr_data[b*8 + bit_idx]) begin
                    // Data bit is '1' → CLEAR the register bit
                    registers[REG_IRQ_STAT][b*8 + bit_idx] <= 1'b0;
                  end
                  // Data bit is '0' → leave register bit unchanged
                end
              end
            end
          end

          // ── SCRATCH Register (R/W) ──
          // General purpose - useful for testing
          REG_SCRATCH: begin
            for (int b = 0; b < STRB_WIDTH; b++) begin
              if (wr_strb[b]) begin
                registers[REG_SCRATCH][b*8 +: 8] <= wr_data[b*8 +: 8];
              end
            end
          end

          // ── VERSION Register (READ-ONLY) ──
          REG_VERSION: begin
            // Do nothing - always stays IP_VERSION
          end

          default: begin
            // Unknown register index - should not happen for valid addr
          end
        endcase
      end // if (wr_en && wr_addr_ok)
    end // else (not reset)
  end

  // ═══════════════════════════════════════════════════════════
  // WRITE RESPONSE (B Channel)
  //
  // After write is done, slave sends BRESP to master:
  //   RESP_OKAY  if address was in valid range
  //   RESP_SLVERR if address was out of range
  //
  // BVALID goes high when response is ready.
  // BVALID stays high until master asserts BREADY (handshake).
  // ═══════════════════════════════════════════════════════════
  always_ff @(posedge slv.aclk or negedge slv.aresetn) begin
    if (!slv.aresetn) begin
      slv.bvalid <= 1'b0;
      slv.bresp  <= 2'b00;
    end else begin
      case (wr_state_q)
        // In IDLE: if both AW+W fire together, assert response next cycle
        S_WR_IDLE: begin
          if (aw_fire && w_fire) begin
            slv.bvalid <= 1'b1;
            slv.bresp  <= (slv.awaddr < ADDR_MAX) ?
                          RESP_OKAY : RESP_SLVERR;
          end
        end

        // In GOT_AW: W just arrived, now we can respond
        S_WR_GOT_AW: begin
          if (w_fire) begin
            slv.bvalid <= 1'b1;
            slv.bresp  <= (aw_addr_q < ADDR_MAX) ?
                          RESP_OKAY : RESP_SLVERR;
          end
        end

        // In GOT_W: AW just arrived, now we can respond
        S_WR_GOT_W: begin
          if (aw_fire) begin
            slv.bvalid <= 1'b1;
            slv.bresp  <= (slv.awaddr < ADDR_MAX) ?
                          RESP_OKAY : RESP_SLVERR;
          end
        end

        // In RESP: Waiting for master to accept (BREADY)
        S_WR_RESP: begin
          if (b_fire) begin
            // Master accepted → deassert BVALID
            slv.bvalid <= 1'b0;
            slv.bresp  <= 2'b00;
          end
          // If BREADY not asserted yet, keep BVALID high
          // (AXI rule: VALID must not deassert until handshake)
        end

        default: begin
          slv.bvalid <= 1'b0;
          slv.bresp  <= 2'b00;
        end
      endcase
    end
  end

  // ═══════════════════════════════════════════════════════════
  // READ FSM: State Register
  // ═══════════════════════════════════════════════════════════
  always_ff @(posedge slv.aclk or negedge slv.aresetn) begin
    if (!slv.aresetn) begin
      rd_state_q <= S_RD_IDLE;
    end else begin
      rd_state_q <= rd_state_d;
    end
  end

  // ═══════════════════════════════════════════════════════════
  // READ FSM: Next State Logic
  // (Simple - only 2 states)
  // ═══════════════════════════════════════════════════════════
  always_comb begin
    rd_state_d = rd_state_q;

    case (rd_state_q)
      S_RD_IDLE: begin
        if (ar_fire) begin
          // Got read address → prepare data response
          rd_state_d = S_RD_RESP;
        end
      end

      S_RD_RESP: begin
        if (r_fire) begin
          // Master accepted data → back to idle
          rd_state_d = S_RD_IDLE;
        end
      end

      default: rd_state_d = S_RD_IDLE;
    endcase
  end

  // ═══════════════════════════════════════════════════════════
  // READ: ARREADY Generation
  //
  // Accept new read address only when IDLE
  // (no pipelining - one read at a time)
  // ═══════════════════════════════════════════════════════════
  assign slv.arready = (rd_state_q == S_RD_IDLE);

  // ═══════════════════════════════════════════════════════════
  // READ: Latch Read Address
  // ═══════════════════════════════════════════════════════════
  always_ff @(posedge slv.aclk or negedge slv.aresetn) begin
    if (!slv.aresetn) begin
      ar_addr_q <= '0;
    end else if (ar_fire) begin
      ar_addr_q <= slv.araddr;
    end
  end

  // ═══════════════════════════════════════════════════════════
  // READ: Data and Response Output (R Channel)
  //
  // When AR handshake happens:
  //   - Read the register at the given address
  //   - Put data on RDATA
  //   - Assert RVALID
  //   - Set RRESP (OKAY or SLVERR)
  //
  // Keep RVALID high until R handshake (RVALID && RREADY)
  // ═══════════════════════════════════════════════════════════
  always_ff @(posedge slv.aclk or negedge slv.aresetn) begin
    if (!slv.aresetn) begin
      slv.rdata  <= '0;
      slv.rresp  <= 2'b00;
      slv.rvalid <= 1'b0;
    end else begin
      case (rd_state_q)
        S_RD_IDLE: begin
          if (ar_fire) begin
            // Read address received → prepare response
            slv.rvalid <= 1'b1;

            if (slv.araddr < ADDR_MAX) begin
              // Valid address → return register data
              slv.rdata <= registers[slv.araddr[ADDR_MSB:ADDR_LSB]];
              slv.rresp <= RESP_OKAY;
            end else begin
              // Invalid address → return error with poison data
              slv.rdata <= 32'hDEAD_BEEF;  // Easily visible in debug
              slv.rresp <= RESP_SLVERR;
            end
          end
        end

        S_RD_RESP: begin
          if (r_fire) begin
            // Master accepted the data → clear outputs
            slv.rvalid <= 1'b0;
            slv.rdata  <= '0;
            slv.rresp  <= 2'b00;
          end
          // Else: keep RVALID high (AXI rule!)
        end

        default: begin
          slv.rvalid <= 1'b0;
        end
      endcase
    end
  end

endmodule : axi4_lite_slave
