
// File: rtl/pkg/axi_pkg.sv
// Author: Abhishek Dhakad
// AXI Protocol Package

package axi_pkg;

  typedef enum logic [1:0] {
    RESP_OKAY   = 2'b00,
    RESP_EXOKAY = 2'b01,
    RESP_SLVERR = 2'b10,
    RESP_DECERR = 2'b11
  } axi_resp_t;

  localparam int NUM_REGS = 8;

  localparam logic [7:0] REG_CTRL_OFFSET     = 8'h00;
  localparam logic [7:0] REG_STATUS_OFFSET   = 8'h04;
  localparam logic [7:0] REG_DATA_TX_OFFSET  = 8'h08;
  localparam logic [7:0] REG_DATA_RX_OFFSET  = 8'h0C;
  localparam logic [7:0] REG_IRQ_EN_OFFSET   = 8'h10;
  localparam logic [7:0] REG_IRQ_STAT_OFFSET = 8'h14;
  localparam logic [7:0] REG_SCRATCH_OFFSET  = 8'h18;
  localparam logic [7:0] REG_VERSION_OFFSET  = 8'h1C;

  localparam int REG_CTRL     = 0;
  localparam int REG_STATUS   = 1;
  localparam int REG_DATA_TX  = 2;
  localparam int REG_DATA_RX  = 3;
  localparam int REG_IRQ_EN   = 4;
  localparam int REG_IRQ_STAT = 5;
  localparam int REG_SCRATCH  = 6;
  localparam int REG_VERSION  = 7;

  localparam logic [31:0] IP_VERSION = 32'h0001_0000;

endpackage : axi_pkg
