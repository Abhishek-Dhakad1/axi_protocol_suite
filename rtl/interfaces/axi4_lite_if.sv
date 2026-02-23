///////////////////////////////////////////////////////////////////////////////
//
// File:        rtl/interfaces/axi4_lite_if.sv
// Author:      Abhishek Dhakad
// Date:        2025
// Description: AXI4-Lite Interface Definition
//
//              SystemVerilog 'interface' ek bundle hai signals ka.
//              Iske fayde:
//              1. Port connection mein galti nahi hoti (1 connection, not 20+)
//              2. 'modport' se direction enforce hoti hai
//              3. Code clean aur readable hota hai
//
//              Yeh interface 5 AXI4-Lite channels ke saare signals
//              ek jagah define karta hai.
//
// Parameters:
//              ADDR_WIDTH - Address bus width (default 32)
//              DATA_WIDTH - Data bus width (32 or 64, default 32)
//
///////////////////////////////////////////////////////////////////////////////

interface axi4_lite_if #(
  parameter int ADDR_WIDTH = 32,    // Address bus width in bits
  parameter int DATA_WIDTH = 32     // Data bus width (AXI4-Lite: 32 or 64 only)
)(
  input logic aclk,      // AXI Global Clock
  input logic aresetn    // AXI Global Reset (ACTIVE LOW!)
                         // aresetn = 0 → Reset active (everything resets)
                         // aresetn = 1 → Normal operation
);

  // ─────────────────────────────────────────────────────────
  // DERIVED PARAMETER
  // DATA_WIDTH = 32 → 4 bytes → STRB_WIDTH = 4
  // DATA_WIDTH = 64 → 8 bytes → STRB_WIDTH = 8
  // ─────────────────────────────────────────────────────────
  localparam int STRB_WIDTH = DATA_WIDTH / 8;

  // ═════════════════════════════════════════════════════════
  // CHANNEL 1: Write Address (AW)
  // Master → Slave: "Is address par likhna hai"
  // ═════════════════════════════════════════════════════════
  logic [ADDR_WIDTH-1:0]  awaddr;    // Write address
  logic [2:0]             awprot;    // Protection type:
                                     //   [0] 0=Unprivileged, 1=Privileged
                                     //   [1] 0=Secure, 1=Non-secure
                                     //   [2] 0=Data, 1=Instruction
                                     // (Mostly 3'b000 use hota hai)
  logic                   awvalid;   // Master says: "Address ready hai"
  logic                   awready;   // Slave says: "Haan, de do address"

  // ═════════════════════════════════════════════════════════
  // CHANNEL 2: Write Data (W)
  // Master → Slave: "Yeh data likhna hai"
  // ═════════════════════════════════════════════════════════
  logic [DATA_WIDTH-1:0]  wdata;     // Write data
  logic [STRB_WIDTH-1:0]  wstrb;     // Write strobes (byte enables)
                                     // wstrb[i]=1 → byte i write hoga
  logic                   wvalid;    // Master says: "Data ready hai"
  logic                   wready;    // Slave says: "Haan, de do data"

  // ═════════════════════════════════════════════════════════
  // CHANNEL 3: Write Response (B)
  // Slave → Master: "Write ho gaya / error aaya"
  // ═════════════════════════════════════════════════════════
  logic [1:0]             bresp;     // Response: OKAY/SLVERR/DECERR
  logic                   bvalid;    // Slave says: "Response ready hai"
  logic                   bready;    // Master says: "Haan, de do response"

  // ═════════════════════════════════════════════════════════
  // CHANNEL 4: Read Address (AR)
  // Master → Slave: "Is address se padhna hai"
  // ═════════════════════════════════════════════════════════
  logic [ADDR_WIDTH-1:0]  araddr;    // Read address
  logic [2:0]             arprot;    // Protection type
  logic                   arvalid;   // Master says: "Read address ready"
  logic                   arready;   // Slave says: "Haan, de do address"

  // ═════════════════════════════════════════════════════════
  // CHANNEL 5: Read Data (R)
  // Slave → Master: "Yeh raha data / error"
  // ═════════════════════════════════════════════════════════
  logic [DATA_WIDTH-1:0]  rdata;     // Read data
  logic [1:0]             rresp;     // Response: OKAY/SLVERR/DECERR
  logic                   rvalid;    // Slave says: "Data ready hai"
  logic                   rready;    // Master says: "Haan, de do data"

  // ═════════════════════════════════════════════════════════
  // MODPORTS (Direction Rules)
  //
  // Modport batata hai ki kaun sa signal input hai aur kaun
  // sa output hai - ye direction PERSPECTIVE se define hoti hai.
  // ═════════════════════════════════════════════════════════

  // MASTER perspective: drives AW, W, AR channels; receives B, R
  modport master (
    input  aclk, aresetn,
    // AW: Master drives address
    output awaddr, awprot, awvalid,
    input  awready,
    // W: Master drives data
    output wdata, wstrb, wvalid,
    input  wready,
    // B: Master receives response
    input  bresp, bvalid,
    output bready,
    // AR: Master drives read address
    output araddr, arprot, arvalid,
    input  arready,
    // R: Master receives read data
    input  rdata, rresp, rvalid,
    output rready
  );

  // SLAVE perspective: receives AW, W, AR channels; drives B, R
  modport slave (
    input  aclk, aresetn,
    // AW: Slave receives address
    input  awaddr, awprot, awvalid,
    output awready,
    // W: Slave receives data
    input  wdata, wstrb, wvalid,
    output wready,
    // B: Slave drives response
    output bresp, bvalid,
    input  bready,
    // AR: Slave receives read address
    input  araddr, arprot, arvalid,
    output arready,
    // R: Slave drives read data
    output rdata, rresp, rvalid,
    input  rready
  );

  // MONITOR perspective: for verification - sab kuch input hai
  // (monitor sirf observe karta hai, drive nahi karta)
  modport monitor (
    input aclk, aresetn,
    input awaddr, awprot, awvalid, awready,
    input wdata, wstrb, wvalid, wready,
    input bresp, bvalid, bready,
    input araddr, arprot, arvalid, arready,
    input rdata, rresp, rvalid, rready
  );

endinterface : axi4_lite_if
