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

  logic [31:0] reg_ctrl;
  logic [31:0] reg_status;
  logic [31:0] reg_data_tx;
  logic [31:0] reg_data_rx;
  logic [31:0] reg_irq_en;
  logic [31:0] reg_irq_stat;
  logic [31:0] reg_scratch;
  logic [31:0] reg_version;

  typedef enum logic [2:0] {
    S_WR_IDLE=0, S_WR_GOT_AW=1, S_WR_GOT_W=2, S_WR_WRITE=3, S_WR_RESP=4
  } wr_state_e;
  wr_state_e wr_state_q;

  logic [ADDR_WIDTH-1:0] aw_addr_q;
  logic [DATA_WIDTH-1:0] w_data_q;
  logic [STRB_WIDTH-1:0] w_strb_q;

  typedef enum logic { S_RD_IDLE=0, S_RD_RESP=1 } rd_state_e;
  rd_state_e rd_state_q;

  wire aw_fire = slv.awvalid & slv.awready;
  wire w_fire  = slv.wvalid  & slv.wready;
  wire b_fire  = slv.bvalid  & slv.bready;
  wire ar_fire = slv.arvalid & slv.arready;
  wire r_fire  = slv.rvalid  & slv.rready;

  assign slv.awready = (wr_state_q == S_WR_IDLE) || (wr_state_q == S_WR_GOT_W);
  assign slv.wready  = (wr_state_q == S_WR_IDLE) || (wr_state_q == S_WR_GOT_AW);
  assign slv.arready = (rd_state_q == S_RD_IDLE);

  wire [2:0] wr_idx = aw_addr_q[4:2];
  wire wr_ok = (aw_addr_q[31:5] == 27'd0);

  always_ff @(posedge slv.aclk or negedge slv.aresetn) begin
    if (!slv.aresetn) begin
      wr_state_q <= S_WR_IDLE;
      rd_state_q <= S_RD_IDLE;
      aw_addr_q <= '0; w_data_q <= '0; w_strb_q <= '0;
      slv.bvalid <= 0; slv.bresp <= 0;
      slv.rvalid <= 0; slv.rdata <= 0; slv.rresp <= 0;
      reg_ctrl <= 0; reg_status <= 0; reg_data_tx <= 0; reg_data_rx <= 0;
      reg_irq_en <= 0; reg_irq_stat <= 0; reg_scratch <= 0;
      reg_version <= IP_VERSION;
    end else begin

      // Hardware-driven (every cycle)
      reg_version <= IP_VERSION;
      reg_status  <= {31'd0, reg_ctrl[0]};
      reg_data_rx <= reg_data_tx;

      // Write FSM
      case (wr_state_q)
        S_WR_IDLE: begin
          slv.bvalid <= 0;
          if (aw_fire && w_fire) begin
            aw_addr_q <= slv.awaddr; w_data_q <= slv.wdata; w_strb_q <= slv.wstrb;
            wr_state_q <= S_WR_WRITE;
          end else if (aw_fire) begin
            aw_addr_q <= slv.awaddr;
            wr_state_q <= S_WR_GOT_AW;
          end else if (w_fire) begin
            w_data_q <= slv.wdata; w_strb_q <= slv.wstrb;
            wr_state_q <= S_WR_GOT_W;
          end
        end
        S_WR_GOT_AW: begin
          if (w_fire) begin
            w_data_q <= slv.wdata; w_strb_q <= slv.wstrb;
            wr_state_q <= S_WR_WRITE;
          end
        end
        S_WR_GOT_W: begin
          if (aw_fire) begin
            aw_addr_q <= slv.awaddr;
            wr_state_q <= S_WR_WRITE;
          end
        end
        S_WR_WRITE: begin
          if (wr_ok) begin
            case (wr_idx)
              3'd0: begin
                if (w_strb_q[0]) reg_ctrl[ 7: 0] <= w_data_q[ 7: 0];
                if (w_strb_q[1]) reg_ctrl[15: 8] <= w_data_q[15: 8];
                if (w_strb_q[2]) reg_ctrl[23:16] <= w_data_q[23:16];
                if (w_strb_q[3]) reg_ctrl[31:24] <= w_data_q[31:24];
              end
              3'd1: begin end // STATUS RO
              3'd2: begin
                if (w_strb_q[0]) reg_data_tx[ 7: 0] <= w_data_q[ 7: 0];
                if (w_strb_q[1]) reg_data_tx[15: 8] <= w_data_q[15: 8];
                if (w_strb_q[2]) reg_data_tx[23:16] <= w_data_q[23:16];
                if (w_strb_q[3]) reg_data_tx[31:24] <= w_data_q[31:24];
              end
              3'd3: begin end // DATA_RX RO
              3'd4: begin
                if (w_strb_q[0]) reg_irq_en[ 7: 0] <= w_data_q[ 7: 0];
                if (w_strb_q[1]) reg_irq_en[15: 8] <= w_data_q[15: 8];
                if (w_strb_q[2]) reg_irq_en[23:16] <= w_data_q[23:16];
                if (w_strb_q[3]) reg_irq_en[31:24] <= w_data_q[31:24];
              end
              3'd5: begin // IRQ_STAT W1C
                if (w_strb_q[0]) begin
                  if (w_data_q[0]) reg_irq_stat[0] <= 0;
                  if (w_data_q[1]) reg_irq_stat[1] <= 0;
                  if (w_data_q[2]) reg_irq_stat[2] <= 0;
                  if (w_data_q[3]) reg_irq_stat[3] <= 0;
                  if (w_data_q[4]) reg_irq_stat[4] <= 0;
                  if (w_data_q[5]) reg_irq_stat[5] <= 0;
                  if (w_data_q[6]) reg_irq_stat[6] <= 0;
                  if (w_data_q[7]) reg_irq_stat[7] <= 0;
                end
              end
              3'd6: begin
                if (w_strb_q[0]) reg_scratch[ 7: 0] <= w_data_q[ 7: 0];
                if (w_strb_q[1]) reg_scratch[15: 8] <= w_data_q[15: 8];
                if (w_strb_q[2]) reg_scratch[23:16] <= w_data_q[23:16];
                if (w_strb_q[3]) reg_scratch[31:24] <= w_data_q[31:24];
              end
              3'd7: begin end // VERSION RO
              default: begin end
            endcase
          end
          slv.bvalid <= 1;
          slv.bresp  <= wr_ok ? RESP_OKAY : RESP_SLVERR;
          wr_state_q <= S_WR_RESP;
        end
        S_WR_RESP: begin
          if (b_fire) begin slv.bvalid <= 0; slv.bresp <= 0; wr_state_q <= S_WR_IDLE; end
        end
        default: begin wr_state_q <= S_WR_IDLE; slv.bvalid <= 0; end
      endcase

      // Read FSM
      case (rd_state_q)
        S_RD_IDLE: begin
          if (ar_fire) begin
            rd_state_q <= S_RD_RESP;
            slv.rvalid <= 1;
            if (slv.araddr[31:5] == 27'd0) begin
              slv.rresp <= RESP_OKAY;
              case (slv.araddr[4:2])
                3'd0: slv.rdata <= reg_ctrl;
                3'd1: slv.rdata <= reg_status;
                3'd2: slv.rdata <= reg_data_tx;
                3'd3: slv.rdata <= reg_data_rx;
                3'd4: slv.rdata <= reg_irq_en;
                3'd5: slv.rdata <= reg_irq_stat;
                3'd6: slv.rdata <= reg_scratch;
                3'd7: slv.rdata <= reg_version;
                default: slv.rdata <= 32'hDEADBEEF;
              endcase
            end else begin
              slv.rdata <= 32'hDEADBEEF;
              slv.rresp <= RESP_SLVERR;
            end
          end
        end
        S_RD_RESP: begin
          if (r_fire) begin
            rd_state_q <= S_RD_IDLE; slv.rvalid <= 0; slv.rdata <= 0; slv.rresp <= 0;
          end
        end
        default: begin rd_state_q <= S_RD_IDLE; slv.rvalid <= 0; end
      endcase
    end
  end
endmodule : axi4_lite_slave
