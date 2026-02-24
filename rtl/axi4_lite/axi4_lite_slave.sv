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


interface axi4_lite_if #(
  parameter int ADDR_WIDTH = 32,
  parameter int DATA_WIDTH = 32
)(
  input logic aclk,
  input logic aresetn
);
  localparam int STRB_WIDTH = DATA_WIDTH / 8;

  logic [ADDR_WIDTH-1:0] awaddr;
  logic [2:0]            awprot;
  logic                  awvalid;
  logic                  awready;

  logic [DATA_WIDTH-1:0] wdata;
  logic [STRB_WIDTH-1:0] wstrb;
  logic                  wvalid;
  logic                  wready;

  logic [1:0]            bresp;
  logic                  bvalid;
  logic                  bready;

  logic [ADDR_WIDTH-1:0] araddr;
  logic [2:0]            arprot;
  logic                  arvalid;
  logic                  arready;

  logic [DATA_WIDTH-1:0] rdata;
  logic [1:0]            rresp;
  logic                  rvalid;
  logic                  rready;

  modport master (
    input  aclk, aresetn,
    output awaddr, awprot, awvalid, input awready,
    output wdata, wstrb, wvalid, input wready,
    input  bresp, bvalid, output bready,
    output araddr, arprot, arvalid, input arready,
    input  rdata, rresp, rvalid, output rready
  );

  modport slave (
    input  aclk, aresetn,
    input  awaddr, awprot, awvalid, output awready,
    input  wdata, wstrb, wvalid, output wready,
    output bresp, bvalid, input bready,
    input  araddr, arprot, arvalid, output arready,
    output rdata, rresp, rvalid, input rready
  );

  modport monitor (
    input aclk, aresetn,
    input awaddr, awprot, awvalid, awready,
    input wdata, wstrb, wvalid, wready,
    input bresp, bvalid, bready,
    input araddr, arprot, arvalid, arready,
    input rdata, rresp, rvalid, rready
  );
endinterface : axi4_lite_if
