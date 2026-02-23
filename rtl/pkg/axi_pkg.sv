///////////////////////////////////////////////////////////////////////////////
//
// File:        rtl/pkg/axi_pkg.sv
// Author:      Abhishek Dhakad
// Date:        2025
// Description: AXI Protocol Package
//              Contains common definitions used across all AXI modules:
//              - Response code types
//              - Register map offsets and indices
//              - IP version constant
//
// Usage:       import axi_pkg::*;  (at top of any module that needs these)
//
///////////////////////////////////////////////////////////////////////////////

package axi_pkg;

  // ═══════════════════════════════════════════════════════════
  // AXI RESPONSE CODES
  // (From AXI spec section A3.4.4)
  // Used in BRESP (write response) and RRESP (read response)
  // ═══════════════════════════════════════════════════════════
  typedef enum logic [1:0] {
    RESP_OKAY   = 2'b00,  // Normal success - sab theek hai
    RESP_EXOKAY = 2'b01,  // Exclusive OK (AXI4-Lite mein use nahi)
    RESP_SLVERR = 2'b10,  // Slave Error - slave ne address accept kiya
                          //               but process nahi kar saka
    RESP_DECERR = 2'b11   // Decode Error - koi slave hi nahi hai us
                          //               address par (interconnect sends)
  } axi_resp_t;

  // ═══════════════════════════════════════════════════════════
  // REGISTER MAP DEFINITIONS
  // Our slave has 8 registers, each 4 bytes (32-bit) wide
  // Total address space: 8 × 4 = 32 bytes (0x00 to 0x1F)
  // ═══════════════════════════════════════════════════════════

  // Number of registers in our slave
  localparam int NUM_REGS = 8;

  // Register BYTE OFFSETS (these are the addresses CPU will use)
  // Har register 4 bytes apart hai (32-bit aligned)
  localparam logic [7:0] REG_CTRL_OFFSET     = 8'h00;  // Control
  localparam logic [7:0] REG_STATUS_OFFSET   = 8'h04;  // Status (read-only)
  localparam logic [7:0] REG_DATA_TX_OFFSET  = 8'h08;  // TX Data
  localparam logic [7:0] REG_DATA_RX_OFFSET  = 8'h0C;  // RX Data (read-only)
  localparam logic [7:0] REG_IRQ_EN_OFFSET   = 8'h10;  // IRQ Enable
  localparam logic [7:0] REG_IRQ_STAT_OFFSET = 8'h14;  // IRQ Status (W1C)
  localparam logic [7:0] REG_SCRATCH_OFFSET  = 8'h18;  // Scratch Pad
  localparam logic [7:0] REG_VERSION_OFFSET  = 8'h1C;  // Version (read-only)

  // Register INDICES (internal use - derived from addr[4:2])
  // Yeh numbers register array ke index hain
  localparam int REG_CTRL     = 0;
  localparam int REG_STATUS   = 1;
  localparam int REG_DATA_TX  = 2;
  localparam int REG_DATA_RX  = 3;
  localparam int REG_IRQ_EN   = 4;
  localparam int REG_IRQ_STAT = 5;
  localparam int REG_SCRATCH  = 6;
  localparam int REG_VERSION  = 7;

  // IP Version: 1.0.0 → 0x00010000
  // Format: [31:16] = Major, [15:8] = Minor, [7:0] = Patch
  localparam logic [31:0] IP_VERSION = 32'h0001_0000;

endpackage : axi_pkg
