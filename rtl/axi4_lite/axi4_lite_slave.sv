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
  import axi_pkg::*;
#(
  parameter int ADDR_WIDTH = 32,
  parameter int DATA_WIDTH = 32
)(
  axi4_lite_if.slave  slv
);

  localparam int STRB_WIDTH = DATA_WIDTH / 8;
  localparam int ADDR_LSB   = $clog2(DATA_WIDTH / 8);
  localparam int ADDR_MSB   = ADDR_LSB + $clog2(NUM_REGS) - 1;
  localparam int ADDR_MAX   = NUM_REGS * (DATA_WIDTH / 8);

  // Register file
  logic [DATA_WIDTH-1:0] registers [NUM_REGS];

  // Write FSM - now 4 states with explicit WRITE state
  typedef enum logic [2:0] {
    S_WR_IDLE    = 3'b000,
    S_WR_GOT_AW = 3'b001,
    S_WR_GOT_W  = 3'b010,
    S_WR_WRITE  = 3'b011,  // NEW: do actual register write here
    S_WR_RESP   = 3'b100   // send BVALID, wait for BREADY
  } wr_state_e;

  wr_state_e wr_state_q;

  // Latched values (stable one cycle after handshake)
  logic [ADDR_WIDTH-1:0] aw_addr_q;
  logic [DATA_WIDTH-1:0] w_data_q;
  logic [STRB_WIDTH-1:0] w_strb_q;

  // Read FSM
  typedef enum logic {
    S_RD_IDLE = 1'b0,
    S_RD_RESP = 1'b1
  } rd_state_e;

  rd_state_e rd_state_q;

  // Handshake detection
  logic aw_fire, w_fire, b_fire, ar_fire, r_fire;
  assign aw_fire = slv.awvalid & slv.awready;
  assign w_fire  = slv.wvalid  & slv.wready;
  assign b_fire  = slv.bvalid  & slv.bready;
  assign ar_fire = slv.arvalid & slv.arready;
  assign r_fire  = slv.rvalid  & slv.rready;

  // Ready signals
  assign slv.awready = (wr_state_q == S_WR_IDLE) || (wr_state_q == S_WR_GOT_W);
  assign slv.wready  = (wr_state_q == S_WR_IDLE) || (wr_state_q == S_WR_GOT_AW);
  assign slv.arready = (rd_state_q == S_RD_IDLE);

  // ══════════════════════════════════════════
  // WRITE FSM + LATCH
  // ══════════════════════════════════════════
  always_ff @(posedge slv.aclk or negedge slv.aresetn) begin
    if (!slv.aresetn) begin
      wr_state_q <= S_WR_IDLE;
      aw_addr_q  <= '0;
      w_data_q   <= '0;
      w_strb_q   <= '0;
      slv.bvalid <= 1'b0;
      slv.bresp  <= 2'b00;
    end else begin

      case (wr_state_q)

        S_WR_IDLE: begin
          slv.bvalid <= 1'b0;
          if (aw_fire && w_fire) begin
            aw_addr_q  <= slv.awaddr;
            w_data_q   <= slv.wdata;
            w_strb_q   <= slv.wstrb;
            wr_state_q <= S_WR_WRITE;
          end else if (aw_fire) begin
            aw_addr_q  <= slv.awaddr;
            wr_state_q <= S_WR_GOT_AW;
          end else if (w_fire) begin
            w_data_q   <= slv.wdata;
            w_strb_q   <= slv.wstrb;
            wr_state_q <= S_WR_GOT_W;
          end
        end

        S_WR_GOT_AW: begin
          if (w_fire) begin
            w_data_q   <= slv.wdata;
            w_strb_q   <= slv.wstrb;
            wr_state_q <= S_WR_WRITE;
          end
        end

        S_WR_GOT_W: begin
          if (aw_fire) begin
            aw_addr_q  <= slv.awaddr;
            wr_state_q <= S_WR_WRITE;
          end
        end

        // NEW STATE: Values are NOW stable in aw_addr_q, w_data_q, w_strb_q
        // Register write happens in separate always_ff below
        // Assert BVALID here
        S_WR_WRITE: begin
          slv.bvalid <= 1'b1;
          slv.bresp  <= (aw_addr_q < ADDR_MAX) ? RESP_OKAY : RESP_SLVERR;
          wr_state_q <= S_WR_RESP;
        end

        S_WR_RESP: begin
          if (b_fire) begin
            slv.bvalid <= 1'b0;
            slv.bresp  <= 2'b00;
            wr_state_q <= S_WR_IDLE;
          end
        end

        default: begin
          wr_state_q <= S_WR_IDLE;
          slv.bvalid <= 1'b0;
        end
      endcase
    end
  end

  // ══════════════════════════════════════════
  // REGISTER FILE: Write Logic
  //
  // Write happens when FSM is in S_WR_WRITE state.
  // At this point aw_addr_q and w_data_q are GUARANTEED
  // stable (they were latched on the previous cycle).
  // ══════════════════════════════════════════
  logic [$clog2(NUM_REGS)-1:0] wr_idx;
  assign wr_idx = aw_addr_q[ADDR_MSB:ADDR_LSB];

  logic wr_addr_ok;
  assign wr_addr_ok = (aw_addr_q < ADDR_MAX);

  always_ff @(posedge slv.aclk or negedge slv.aresetn) begin
    if (!slv.aresetn) begin
      registers[REG_CTRL]     <= '0;
      registers[REG_STATUS]   <= '0;
      registers[REG_DATA_TX]  <= '0;
      registers[REG_DATA_RX]  <= '0;
      registers[REG_IRQ_EN]   <= '0;
      registers[REG_IRQ_STAT] <= '0;
      registers[REG_SCRATCH]  <= '0;
      registers[REG_VERSION]  <= IP_VERSION;
    end else begin
      // Hardware-driven (every cycle)
      registers[REG_VERSION]      <= IP_VERSION;
      registers[REG_STATUS][0]    <= registers[REG_CTRL][0];
      registers[REG_STATUS][31:1] <= '0;
      registers[REG_DATA_RX]     <= registers[REG_DATA_TX];

      // AXI write: only in S_WR_WRITE state with valid address
      if (wr_state_q == S_WR_WRITE && wr_addr_ok) begin
        case (wr_idx)
          REG_CTRL: begin
            for (int b = 0; b < STRB_WIDTH; b++)
              if (w_strb_q[b])
                registers[REG_CTRL][b*8 +: 8] <= w_data_q[b*8 +: 8];
          end
          REG_STATUS: ; // READ-ONLY
          REG_DATA_TX: begin
            for (int b = 0; b < STRB_WIDTH; b++)
              if (w_strb_q[b])
                registers[REG_DATA_TX][b*8 +: 8] <= w_data_q[b*8 +: 8];
          end
          REG_DATA_RX: ; // READ-ONLY
          REG_IRQ_EN: begin
            for (int b = 0; b < STRB_WIDTH; b++)
              if (w_strb_q[b])
                registers[REG_IRQ_EN][b*8 +: 8] <= w_data_q[b*8 +: 8];
          end
          REG_IRQ_STAT: begin
            for (int b = 0; b < STRB_WIDTH; b++)
              if (w_strb_q[b])
                for (int i = 0; i < 8; i++)
                  if (w_data_q[b*8 + i])
                    registers[REG_IRQ_STAT][b*8 + i] <= 1'b0;
          end
          REG_SCRATCH: begin
            for (int b = 0; b < STRB_WIDTH; b++)
              if (w_strb_q[b])
                registers[REG_SCRATCH][b*8 +: 8] <= w_data_q[b*8 +: 8];
          end
          REG_VERSION: ; // READ-ONLY
          default: ;
        endcase
      end
    end
  end

  // ══════════════════════════════════════════
  // READ FSM + DATA OUTPUT
  // ══════════════════════════════════════════
  always_ff @(posedge slv.aclk or negedge slv.aresetn) begin
    if (!slv.aresetn) begin
      rd_state_q <= S_RD_IDLE;
      slv.rdata  <= '0;
      slv.rresp  <= 2'b00;
      slv.rvalid <= 1'b0;
    end else begin
      case (rd_state_q)
        S_RD_IDLE: begin
          if (ar_fire) begin
            rd_state_q <= S_RD_RESP;
            slv.rvalid <= 1'b1;
            if (slv.araddr < ADDR_MAX) begin
              slv.rdata <= registers[slv.araddr[ADDR_MSB:ADDR_LSB]];
              slv.rresp <= RESP_OKAY;
            end else begin
              slv.rdata <= 32'hDEAD_BEEF;
              slv.rresp <= RESP_SLVERR;
            end
          end
        end
        S_RD_RESP: begin
          if (r_fire) begin
            rd_state_q <= S_RD_IDLE;
            slv.rvalid <= 1'b0;
            slv.rdata  <= '0;
            slv.rresp  <= 2'b00;
          end
        end
        default: begin
          rd_state_q <= S_RD_IDLE;
          slv.rvalid <= 1'b0;
        end
      endcase
    end
  end

endmodule : axi4_lite_slave
