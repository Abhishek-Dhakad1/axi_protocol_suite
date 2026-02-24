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
  axi4_lite_if.slave slv
);

  localparam int STRB_WIDTH = DATA_WIDTH / 8;

  // Individual registers (NOT an array)
  logic [31:0] reg_ctrl;
  logic [31:0] reg_status;
  logic [31:0] reg_data_tx;
  logic [31:0] reg_data_rx;
  logic [31:0] reg_irq_en;
  logic [31:0] reg_irq_stat;
  logic [31:0] reg_scratch;
  logic [31:0] reg_version;

  // Write FSM
  typedef enum logic [2:0] {
    S_WR_IDLE    = 3'd0,
    S_WR_GOT_AW = 3'd1,
    S_WR_GOT_W  = 3'd2,
    S_WR_WRITE  = 3'd3,
    S_WR_RESP   = 3'd4
  } wr_state_e;
  wr_state_e wr_state_q;

  logic [ADDR_WIDTH-1:0] aw_addr_q;
  logic [DATA_WIDTH-1:0] w_data_q;
  logic [STRB_WIDTH-1:0] w_strb_q;

  // Read FSM
  typedef enum logic {
    S_RD_IDLE = 1'b0,
    S_RD_RESP = 1'b1
  } rd_state_e;
  rd_state_e rd_state_q;

  // Handshake
  wire aw_fire = slv.awvalid & slv.awready;
  wire w_fire  = slv.wvalid  & slv.wready;
  wire b_fire  = slv.bvalid  & slv.bready;
  wire ar_fire = slv.arvalid & slv.arready;
  wire r_fire  = slv.rvalid  & slv.rready;

  // Ready
  assign slv.awready = (wr_state_q == S_WR_IDLE) || (wr_state_q == S_WR_GOT_W);
  assign slv.wready  = (wr_state_q == S_WR_IDLE) || (wr_state_q == S_WR_GOT_AW);
  assign slv.arready = (rd_state_q == S_RD_IDLE);

  // Write index from latched address
  wire [2:0] wr_idx = aw_addr_q[4:2];
  wire wr_ok = (aw_addr_q[31:5] == 27'd0);

  // Read helper
  wire [2:0] rd_idx = slv.araddr[4:2];
  wire rd_ok = (slv.araddr[31:5] == 27'd0);

  // Read data mux (combinational)
  logic [31:0] rd_mux;
  always_comb begin
    case (rd_idx)
      3'd0: rd_mux = reg_ctrl;
      3'd1: rd_mux = reg_status;
      3'd2: rd_mux = reg_data_tx;
      3'd3: rd_mux = reg_data_rx;
      3'd4: rd_mux = reg_irq_en;
      3'd5: rd_mux = reg_irq_stat;
      3'd6: rd_mux = reg_scratch;
      3'd7: rd_mux = reg_version;
      default: rd_mux = 32'hDEAD_BEEF;
    endcase
  end

  // SINGLE always_ff
  always_ff @(posedge slv.aclk or negedge slv.aresetn) begin
    if (!slv.aresetn) begin
      wr_state_q <= S_WR_IDLE;
      rd_state_q <= S_RD_IDLE;
      aw_addr_q  <= '0;
      w_data_q   <= '0;
      w_strb_q   <= '0;
      slv.bvalid <= 1'b0;
      slv.bresp  <= 2'b00;
      slv.rvalid <= 1'b0;
      slv.rdata  <= '0;
      slv.rresp  <= 2'b00;
      reg_ctrl     <= 32'd0;
      reg_status   <= 32'd0;
      reg_data_tx  <= 32'd0;
      reg_data_rx  <= 32'd0;
      reg_irq_en   <= 32'd0;
      reg_irq_stat <= 32'd0;
      reg_scratch  <= 32'd0;
      reg_version  <= IP_VERSION;
    end else begin

      // Hardware-driven
      reg_version  <= IP_VERSION;
      reg_status   <= {31'd0, reg_ctrl[0]};
      reg_data_rx  <= reg_data_tx;

      // WRITE FSM
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

        S_WR_WRITE: begin
          // Values are STABLE here (latched on previous cycle)
          if (wr_ok) begin
            case (wr_idx)
              3'd0: begin // CTRL
                for (int b = 0; b < STRB_WIDTH; b++)
                  if (w_strb_q[b]) reg_ctrl[b*8 +: 8] <= w_data_q[b*8 +: 8];
              end
              3'd1: begin end // STATUS - RO
              3'd2: begin // DATA_TX
                for (int b = 0; b < STRB_WIDTH; b++)
                  if (w_strb_q[b]) reg_data_tx[b*8 +: 8] <= w_data_q[b*8 +: 8];
              end
              3'd3: begin end // DATA_RX - RO
              3'd4: begin // IRQ_EN
                for (int b = 0; b < STRB_WIDTH; b++)
                  if (w_strb_q[b]) reg_irq_en[b*8 +: 8] <= w_data_q[b*8 +: 8];
              end
              3'd5: begin // IRQ_STAT W1C
                for (int b = 0; b < STRB_WIDTH; b++)
                  if (w_strb_q[b])
                    for (int i = 0; i < 8; i++)
                      if (w_data_q[b*8 + i]) reg_irq_stat[b*8 + i] <= 1'b0;
              end
              3'd6: begin // SCRATCH
                for (int b = 0; b < STRB_WIDTH; b++)
                  if (w_strb_q[b]) reg_scratch[b*8 +: 8] <= w_data_q[b*8 +: 8];
              end
              3'd7: begin end // VERSION - RO
              default: begin end
            endcase
          end
          slv.bvalid <= 1'b1;
          slv.bresp  <= wr_ok ? RESP_OKAY : RESP_SLVERR;
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

      // READ FSM
      case (rd_state_q)
        S_RD_IDLE: begin
          if (ar_fire) begin
            rd_state_q <= S_RD_RESP;
            slv.rvalid <= 1'b1;
            if (rd_ok) begin
              slv.rdata <= rd_mux;
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
