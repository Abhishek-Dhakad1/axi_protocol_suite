///////////////////////////////////////////////////////////////////////////////
//
// File:        rtl/axi4_lite/axi4_lite_slave_wrapper.sv
// Author:      Abhishek Dhakad
// Date:        2025
// Description: Synthesis Wrapper for AXI4-Lite Slave
//
//              KYUN CHAHIYE?
//              Vivado synthesis ke liye top-level module mein
//              SystemVerilog interface directly use nahi ho sakta.
//              Vivado ko explicit ports chahiye (logic/wire).
//
//              Yeh wrapper module:
//              1. Top-level par normal ports expose karta hai
//              2. Andar ek interface instance create karta hai
//              3. Ports ko interface se connect karta hai
//              4. Actual slave module instantiate karta hai
//
//              SIMULATION ke liye: Direct interface use karo (testbench)
//              SYNTHESIS ke liye: Yeh wrapper use karo
//
///////////////////////////////////////////////////////////////////////////////

module axi4_lite_slave_wrapper
  import axi_pkg::*;
#(
  parameter int ADDR_WIDTH = 32,
  parameter int DATA_WIDTH = 32
)(
  // ─── Global Signals ───
  input  logic                      aclk,
  input  logic                      aresetn,

  // ─── Write Address Channel (AW) ───
  input  logic [ADDR_WIDTH-1:0]     s_axi_awaddr,
  input  logic [2:0]                s_axi_awprot,
  input  logic                      s_axi_awvalid,
  output logic                      s_axi_awready,

  // ─── Write Data Channel (W) ───
  input  logic [DATA_WIDTH-1:0]     s_axi_wdata,
  input  logic [DATA_WIDTH/8-1:0]   s_axi_wstrb,
  input  logic                      s_axi_wvalid,
  output logic                      s_axi_wready,

  // ─── Write Response Channel (B) ───
  output logic [1:0]                s_axi_bresp,
  output logic                      s_axi_bvalid,
  input  logic                      s_axi_bready,

  // ─── Read Address Channel (AR) ───
  input  logic [ADDR_WIDTH-1:0]     s_axi_araddr,
  input  logic [2:0]                s_axi_arprot,
  input  logic                      s_axi_arvalid,
  output logic                      s_axi_arready,

  // ─── Read Data Channel (R) ───
  output logic [DATA_WIDTH-1:0]     s_axi_rdata,
  output logic [1:0]                s_axi_rresp,
  output logic                      s_axi_rvalid,
  input  logic                      s_axi_rready
);

  // ─── Internal Interface Instance ───
  axi4_lite_if #(
    .ADDR_WIDTH (ADDR_WIDTH),
    .DATA_WIDTH (DATA_WIDTH)
  ) axi_bus (
    .aclk    (aclk),
    .aresetn (aresetn)
  );

  // ─── Connect external ports → interface signals ───
  // Write Address
  assign axi_bus.awaddr  = s_axi_awaddr;
  assign axi_bus.awprot  = s_axi_awprot;
  assign axi_bus.awvalid = s_axi_awvalid;
  assign s_axi_awready   = axi_bus.awready;

  // Write Data
  assign axi_bus.wdata  = s_axi_wdata;
  assign axi_bus.wstrb  = s_axi_wstrb;
  assign axi_bus.wvalid = s_axi_wvalid;
  assign s_axi_wready   = axi_bus.wready;

  // Write Response
  assign s_axi_bresp  = axi_bus.bresp;
  assign s_axi_bvalid = axi_bus.bvalid;
  assign axi_bus.bready = s_axi_bready;

  // Read Address
  assign axi_bus.araddr  = s_axi_araddr;
  assign axi_bus.arprot  = s_axi_arprot;
  assign axi_bus.arvalid = s_axi_arvalid;
  assign s_axi_arready   = axi_bus.arready;

  // Read Data
  assign s_axi_rdata  = axi_bus.rdata;
  assign s_axi_rresp  = axi_bus.rresp;
  assign s_axi_rvalid = axi_bus.rvalid;
  assign axi_bus.rready = s_axi_rready;

  // ─── Instantiate the actual AXI4-Lite Slave ───
  axi4_lite_slave #(
    .ADDR_WIDTH (ADDR_WIDTH),
    .DATA_WIDTH (DATA_WIDTH)
  ) u_slave (
    .slv (axi_bus.slave)
  );

endmodule : axi4_lite_slave_wrapper
