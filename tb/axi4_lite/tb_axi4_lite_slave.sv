///////////////////////////////////////////////////////////////////////////////
//
// File:        tb/axi4_lite/tb_axi4_lite_slave.sv
// Author:      Abhishek Dhakad
// Date:        2025
// Description: Complete Directed Testbench for AXI4-Lite Slave
//
//              Test Cases:
//              TEST 1:  Read VERSION after reset (should be IP_VERSION)
//              TEST 2:  Read CTRL after reset (should be 0)
//              TEST 3:  Write + read CTRL register
//              TEST 4:  Write + read SCRATCH register
//              TEST 5:  Write DATA_TX, read DATA_RX (loopback check)
//              TEST 6:  Write to read-only VERSION (should be ignored)
//              TEST 7:  WSTRB partial write (byte 0 only)
//              TEST 8:  WSTRB partial write (upper 2 bytes)
//              TEST 9:  Out-of-range write (expect SLVERR)
//              TEST 10: Out-of-range read (expect SLVERR)
//              TEST 11: AW arrives before W (2 cycle gap)
//              TEST 12: W arrives before AW (3 cycle gap)
//              TEST 13: Back-to-back writes
//              TEST 14: Back-to-back reads
//              TEST 15: Write all, read all (final integrity check)
//
///////////////////////////////////////////////////////////////////////////////

`timescale 1ns / 1ps

module tb_axi4_lite_slave;

  // Import package for constants and types
  import axi_pkg::*;

  // ═══════════════════════════════════════════════════════════
  // PARAMETERS
  // ═══════════════════════════════════════════════════════════
  localparam int ADDR_WIDTH  = 32;
  localparam int DATA_WIDTH  = 32;
  localparam int STRB_WIDTH  = DATA_WIDTH / 8;  // = 4
  localparam int CLK_PERIOD  = 10;               // 10ns = 100MHz

  // ═══════════════════════════════════════════════════════════
  // CLOCK AND RESET
  // ═══════════════════════════════════════════════════════════
  logic aclk;
  logic aresetn;

  // Clock: Toggle every 5ns → 10ns period → 100MHz
  initial begin
    aclk = 1'b0;
    forever #(CLK_PERIOD / 2) aclk = ~aclk;
  end

  // ═══════════════════════════════════════════════════════════
  // INTERFACE INSTANTIATION
  // ═══════════════════════════════════════════════════════════
  axi4_lite_if #(
    .ADDR_WIDTH (ADDR_WIDTH),
    .DATA_WIDTH (DATA_WIDTH)
  ) axi_if (
    .aclk    (aclk),
    .aresetn (aresetn)
  );

  // ═══════════════════════════════════════════════════════════
  // DUT (Device Under Test) INSTANTIATION
  // ═══════════════════════════════════════════════════════════
  axi4_lite_slave #(
    .ADDR_WIDTH (ADDR_WIDTH),
    .DATA_WIDTH (DATA_WIDTH)
  ) u_dut (
    .slv (axi_if.slave)
  );

  // ═══════════════════════════════════════════════════════════
  // TEST COUNTERS
  // ═══════════════════════════════════════════════════════════
  int total_tests  = 0;
  int passed_tests = 0;
  int failed_tests = 0;

  // ═══════════════════════════════════════════════════════════
  // TASK: Initialize all master-driven signals to 0
  // Master drives: AW, W, AR channels + BREADY, RREADY
  // ═══════════════════════════════════════════════════════════
  task automatic init_signals();
    axi_if.awaddr  = '0;
    axi_if.awprot  = 3'b000;
    axi_if.awvalid = 1'b0;

    axi_if.wdata   = '0;
    axi_if.wstrb   = '0;
    axi_if.wvalid  = 1'b0;

    axi_if.bready  = 1'b0;

    axi_if.araddr  = '0;
    axi_if.arprot  = 3'b000;
    axi_if.arvalid = 1'b0;

    axi_if.rready  = 1'b0;
  endtask

  // ═══════════════════════════════════════════════════════════
  // TASK: Apply Reset
  // AXI uses ACTIVE-LOW reset (aresetn)
  // aresetn = 0 → Reset active
  // aresetn = 1 → Normal operation
  // ═══════════════════════════════════════════════════════════
  task automatic apply_reset();
    $display("\n[%0t] ════ Applying Reset ════", $time);
    aresetn = 1'b0;       // Assert reset (active low)
    init_signals();       // All master signals to 0
    repeat (5) @(posedge aclk);  // Hold reset for 5 clock cycles
    aresetn = 1'b1;       // Release reset
    @(posedge aclk);      // Wait one cycle for stability
    $display("[%0t] ════ Reset Released ════\n", $time);
  endtask

  // ═══════════════════════════════════════════════════════════
  // TASK: AXI Write (Simultaneous AW + W)
  //
  // This is the most common write method:
  // 1. Assert AWVALID + WVALID simultaneously
  // 2. Wait for both handshakes
  // 3. Wait for B response
  //
  // Parameters:
  //   addr - Register address to write to
  //   data - Data to write
  //   strb - Byte enables (default '1 = all bytes)
  //   resp - Output: response from slave
  // ═══════════════════════════════════════════════════════════
  task automatic axi_write(
    input  logic [ADDR_WIDTH-1:0] addr,
    input  logic [DATA_WIDTH-1:0] data,
    input  logic [STRB_WIDTH-1:0] strb,
    output logic [1:0]            resp
  );
    // Step 1: Drive AW and W channels
    @(posedge aclk);
    axi_if.awaddr  = addr;
    axi_if.awprot  = 3'b000;
    axi_if.awvalid = 1'b1;

    axi_if.wdata   = data;
    axi_if.wstrb   = strb;
    axi_if.wvalid  = 1'b1;

    axi_if.bready  = 1'b1;  // Ready for response

    // Step 2: Wait for AW and W handshakes (can be different cycles)
    fork
      begin : wait_aw
        // Wait until AW handshake happens
        do @(posedge aclk);
        while (!(axi_if.awvalid && axi_if.awready));
        axi_if.awvalid = 1'b0;  // Deassert after handshake
      end

      begin : wait_w
        // Wait until W handshake happens
        do @(posedge aclk);
        while (!(axi_if.wvalid && axi_if.wready));
        axi_if.wvalid = 1'b0;   // Deassert after handshake
      end
    join  // Wait for BOTH to complete

    // Step 3: Wait for B response
    do @(posedge aclk);
    while (!(axi_if.bvalid && axi_if.bready));
    resp = axi_if.bresp;  // Capture response

    @(posedge aclk);
    axi_if.bready = 1'b0;

    $display("[%0t] WRITE: addr=0x%08h data=0x%08h strb=4'b%04b resp=%s",
             $time, addr, data, strb,
             (resp == RESP_OKAY) ? "OKAY" : "SLVERR");
  endtask

  // ═══════════════════════════════════════════════════════════
  // TASK: AXI Write with AW arriving FIRST, W arriving LATER
  //
  // Tests the case: Master sends address first, data after delay
  // Slave must latch address and wait for data
  // ═══════════════════════════════════════════════════════════
  task automatic axi_write_aw_first(
    input  logic [ADDR_WIDTH-1:0] addr,
    input  logic [DATA_WIDTH-1:0] data,
    input  int                    delay,
    output logic [1:0]            resp
  );
    $display("[%0t] WRITE(AW-first, %0d cycle delay): addr=0x%08h data=0x%08h",
             $time, delay, addr, data);

    // Step 1: Send AW only
    @(posedge aclk);
    axi_if.awaddr  = addr;
    axi_if.awprot  = 3'b000;
    axi_if.awvalid = 1'b1;
    axi_if.bready  = 1'b1;

    // Wait for AW handshake
    do @(posedge aclk);
    while (!(axi_if.awvalid && axi_if.awready));
    axi_if.awvalid = 1'b0;

    // Step 2: Wait some cycles (simulating slow data preparation)
    repeat (delay) @(posedge aclk);

    // Step 3: Now send W
    axi_if.wdata  = data;
    axi_if.wstrb  = '1;
    axi_if.wvalid = 1'b1;

    // Wait for W handshake
    do @(posedge aclk);
    while (!(axi_if.wvalid && axi_if.wready));
    axi_if.wvalid = 1'b0;

    // Step 4: Wait for B response
    do @(posedge aclk);
    while (!(axi_if.bvalid && axi_if.bready));
    resp = axi_if.bresp;

    @(posedge aclk);
    axi_if.bready = 1'b0;

    $display("[%0t]   → resp=%s", $time,
             (resp == RESP_OKAY) ? "OKAY" : "SLVERR");
  endtask

  // ═══════════════════════════════════════════════════════════
  // TASK: AXI Write with W arriving FIRST, AW arriving LATER
  //
  // Tests the case: Data arrives before address
  // This is unusual but MUST be handled per AXI spec
  // ═══════════════════════════════════════════════════════════
  task automatic axi_write_w_first(
    input  logic [ADDR_WIDTH-1:0] addr,
    input  logic [DATA_WIDTH-1:0] data,
    input  int                    delay,
    output logic [1:0]            resp
  );
    $display("[%0t] WRITE(W-first, %0d cycle delay): addr=0x%08h data=0x%08h",
             $time, delay, addr, data);

    // Step 1: Send W first
    @(posedge aclk);
    axi_if.wdata  = data;
    axi_if.wstrb  = '1;
    axi_if.wvalid = 1'b1;
    axi_if.bready = 1'b1;

    // Wait for W handshake
    do @(posedge aclk);
    while (!(axi_if.wvalid && axi_if.wready));
    axi_if.wvalid = 1'b0;

    // Step 2: Delay
    repeat (delay) @(posedge aclk);

    // Step 3: Now send AW
    axi_if.awaddr  = addr;
    axi_if.awprot  = 3'b000;
    axi_if.awvalid = 1'b1;

    // Wait for AW handshake
    do @(posedge aclk);
    while (!(axi_if.awvalid && axi_if.awready));
    axi_if.awvalid = 1'b0;

    // Step 4: Wait for B response
    do @(posedge aclk);
    while (!(axi_if.bvalid && axi_if.bready));
    resp = axi_if.bresp;

    @(posedge aclk);
    axi_if.bready = 1'b0;

    $display("[%0t]   → resp=%s", $time,
             (resp == RESP_OKAY) ? "OKAY" : "SLVERR");
  endtask

  // ═══════════════════════════════════════════════════════════
  // TASK: AXI Read
  //
  // 1. Assert ARVALID with address
  // 2. Wait for AR handshake
  // 3. Wait for R response
  // 4. Capture RDATA and RRESP
  // ═══════════════════════════════════════════════════════════
  task automatic axi_read(
    input  logic [ADDR_WIDTH-1:0] addr,
    output logic [DATA_WIDTH-1:0] data,
    output logic [1:0]            resp
  );
    // Step 1: Send read address
    @(posedge aclk);
    axi_if.araddr  = addr;
    axi_if.arprot  = 3'b000;
    axi_if.arvalid = 1'b1;
    axi_if.rready  = 1'b1;  // Ready to accept data

    // Step 2: Wait for AR handshake
    do @(posedge aclk);
    while (!(axi_if.arvalid && axi_if.arready));
    axi_if.arvalid = 1'b0;

    // Step 3: Wait for R response
    do @(posedge aclk);
    while (!(axi_if.rvalid && axi_if.rready));
    data = axi_if.rdata;
    resp = axi_if.rresp;

    @(posedge aclk);
    axi_if.rready = 1'b0;

    $display("[%0t] READ:  addr=0x%08h data=0x%08h resp=%s",
             $time, addr, data,
             (resp == RESP_OKAY) ? "OKAY" : "SLVERR");
  endtask

  // ═══════════════════════════════════════════════════════════
  // TASK: Read and Check against expected value
  // Combines read + comparison + pass/fail reporting
  // ═══════════════════════════════════════════════════════════
  task automatic read_and_check(
    input logic [ADDR_WIDTH-1:0] addr,
    input logic [DATA_WIDTH-1:0] expected,
    input string                 test_name
  );
    logic [DATA_WIDTH-1:0] got_data;
    logic [1:0]            got_resp;

    axi_read(addr, got_data, got_resp);

    total_tests++;
    if (got_data === expected && got_resp === RESP_OKAY) begin
      passed_tests++;
      $display("[%0t] PASS: %s | Expected=0x%08h Got=0x%08h",
               $time, test_name, expected, got_data);
    end else begin
      failed_tests++;
      $display("[%0t] FAIL: %s | Expected=0x%08h Got=0x%08h Resp=%02b",
               $time, test_name, expected, got_data, got_resp);
    end
  endtask

  // ═══════════════════════════════════════════════════════════
  // TASK: Check write response
  // ═══════════════════════════════════════════════════════════
  task automatic check_resp(
    input logic [1:0] got,
    input logic [1:0] expected,
    input string      test_name
  );
    total_tests++;
    if (got === expected) begin
      passed_tests++;
      $display("[%0t] PASS: %s | Response=%s",
               $time, test_name,
               (got == RESP_OKAY) ? "OKAY" : "SLVERR");
    end else begin
      failed_tests++;
      $display("[%0t] FAIL: %s | Expected resp=%02b Got=%02b",
               $time, test_name, expected, got);
    end
  endtask

  // ═══════════════════════════════════════════════════════════
  // MAIN TEST SEQUENCE
  // ═══════════════════════════════════════════════════════════
  logic [DATA_WIDTH-1:0] rd_data;
  logic [1:0]            wr_resp, rd_resp;

  initial begin
    // ── Waveform Dump ──
    $dumpfile("waves/axi4_lite_slave.vcd");
    $dumpvars(0, tb_axi4_lite_slave);

    $display("\n");
    $display("╔══════════════════════════════════════════════╗");
    $display("║  AXI4-Lite Slave Testbench                   ║");
    $display("║  Author: Abhishek Dhakad                     ║");
    $display("║  Starting Tests...                           ║");
    $display("╚══════════════════════════════════════════════╝");

    // ──────────────────────────────────
    // RESET
    // ──────────────────────────────────
    apply_reset();

    // ══════════════════════════════════
    // TEST 1: Read VERSION after reset
    // Expected: IP_VERSION = 0x00010000
    // ══════════════════════════════════
    $display("\n── TEST 1: VERSION register after reset ──");
    read_and_check(
      REG_VERSION_OFFSET,     // Address: 0x1C
      IP_VERSION,             // Expected: 0x00010000
      "VERSION after reset"
    );

    // ══════════════════════════════════
    // TEST 2: Read CTRL after reset
    // Expected: 0x00000000 (all zeros)
    // ══════════════════════════════════
    $display("\n── TEST 2: CTRL register after reset ──");
    read_and_check(
      REG_CTRL_OFFSET,        // Address: 0x00
      32'h0000_0000,          // Expected: 0
      "CTRL after reset"
    );

    // ══════════════════════════════════
    // TEST 3: Write and Read CTRL register
    // Write 0xCAFEBABE, read it back
    // ══════════════════════════════════
    $display("\n── TEST 3: Write/Read CTRL register ──");
    axi_write(REG_CTRL_OFFSET, 32'hCAFE_BABE, 4'b1111, wr_resp);
    check_resp(wr_resp, RESP_OKAY, "CTRL write resp");
    read_and_check(REG_CTRL_OFFSET, 32'hCAFE_BABE, "CTRL readback");

    // ══════════════════════════════════
    // TEST 4: Write and Read SCRATCH register
    // ══════════════════════════════════
    $display("\n── TEST 4: Write/Read SCRATCH register ──");
    axi_write(REG_SCRATCH_OFFSET, 32'hDEAD_BEEF, 4'b1111, wr_resp);
    check_resp(wr_resp, RESP_OKAY, "SCRATCH write resp");
    read_and_check(REG_SCRATCH_OFFSET, 32'hDEAD_BEEF, "SCRATCH readback");

    // ══════════════════════════════════
    // TEST 5: DATA_TX → DATA_RX loopback
    // Write to TX, read from RX (our design loops back)
    // ══════════════════════════════════
    $display("\n── TEST 5: DATA_TX → DATA_RX loopback ──");
    axi_write(REG_DATA_TX_OFFSET, 32'h1234_5678, 4'b1111, wr_resp);
    check_resp(wr_resp, RESP_OKAY, "DATA_TX write resp");
    read_and_check(REG_DATA_TX_OFFSET, 32'h1234_5678, "DATA_TX readback");
    // Wait 2 cycles for loopback to update
    repeat (2) @(posedge aclk);
    read_and_check(REG_DATA_RX_OFFSET, 32'h1234_5678, "DATA_RX loopback");

    // ══════════════════════════════════
    // TEST 6: Write to READ-ONLY register (VERSION)
    // Write should get OKAY but value should NOT change
    // ══════════════════════════════════
    $display("\n── TEST 6: Write to READ-ONLY VERSION register ──");
    axi_write(REG_VERSION_OFFSET, 32'hFFFF_FFFF, 4'b1111, wr_resp);
    check_resp(wr_resp, RESP_OKAY, "VERSION write resp (accepted but ignored)");
    read_and_check(REG_VERSION_OFFSET, IP_VERSION, "VERSION unchanged");

    // ══════════════════════════════════
    // TEST 7: WSTRB partial write - byte 0 only
    // ══════════════════════════════════
    $display("\n── TEST 7: WSTRB test - write byte 0 only ──");
    // First write known value
    axi_write(REG_SCRATCH_OFFSET, 32'hAABB_CCDD, 4'b1111, wr_resp);
    read_and_check(REG_SCRATCH_OFFSET, 32'hAABB_CCDD, "SCRATCH = 0xAABBCCDD");

    // Now write only byte 0 with WSTRB = 4'b0001
    // WDATA = 0x11111111, but only byte 0 (0x11) should be written
    // Expected result: 0xAABBCC11
    axi_write(REG_SCRATCH_OFFSET, 32'h1111_1111, 4'b0001, wr_resp);
    read_and_check(REG_SCRATCH_OFFSET, 32'hAABB_CC11,
                   "SCRATCH byte0 only (WSTRB=0001)");

    // ══════════════════════════════════
    // TEST 8: WSTRB partial write - upper 2 bytes
    // ══════════════════════════════════
    $display("\n── TEST 8: WSTRB test - write upper 2 bytes ──");
    // Current value: 0xAABBCC11
    // Write 0xFF00FF00 with WSTRB = 4'b1100 (bytes 2 and 3)
    // Expected: byte3=FF, byte2=00, byte1=CC (unchanged), byte0=11 (unchanged)
    // Result: 0xFF00CC11
    axi_write(REG_SCRATCH_OFFSET, 32'hFF00_FF00, 4'b1100, wr_resp);
    read_and_check(REG_SCRATCH_OFFSET, 32'hFF00_CC11,
                   "SCRATCH upper bytes (WSTRB=1100)");

    // ══════════════════════════════════
    // TEST 9: Out-of-range WRITE (expect SLVERR)
    // ══════════════════════════════════
    $display("\n── TEST 9: Out-of-range write → SLVERR ──");
    axi_write(32'h0000_0100, 32'hBAAD_F00D, 4'b1111, wr_resp);
    check_resp(wr_resp, RESP_SLVERR, "Out-of-range write SLVERR");

    // ══════════════════════════════════
    // TEST 10: Out-of-range READ (expect SLVERR)
    // ══════════════════════════════════
    $display("\n── TEST 10: Out-of-range read → SLVERR ──");
    axi_read(32'h0000_0100, rd_data, rd_resp);
    total_tests++;
    if (rd_resp === RESP_SLVERR) begin
      passed_tests++;
      $display("[%0t] PASS: Out-of-range read returns SLVERR", $time);
    end else begin
      failed_tests++;
      $display("[%0t] FAIL: Expected SLVERR, got %02b", $time, rd_resp);
    end

    // ══════════════════════════════════
    // TEST 11: AW before W (2 cycle gap)
    // Tests that slave correctly handles split AW/W
    // ══════════════════════════════════
    $display("\n── TEST 11: AW arrives before W (2 cycle gap) ──");
    axi_write_aw_first(REG_SCRATCH_OFFSET, 32'hAAAA_1111, 2, wr_resp);
    check_resp(wr_resp, RESP_OKAY, "AW-first write resp");
    read_and_check(REG_SCRATCH_OFFSET, 32'hAAAA_1111, "AW-first readback");

    // ══════════════════════════════════
    // TEST 12: W before AW (3 cycle gap)
    // Tests the unusual but valid case
    // ══════════════════════════════════
    $display("\n── TEST 12: W arrives before AW (3 cycle gap) ──");
    axi_write_w_first(REG_SCRATCH_OFFSET, 32'hBBBB_2222, 3, wr_resp);
    check_resp(wr_resp, RESP_OKAY, "W-first write resp");
    read_and_check(REG_SCRATCH_OFFSET, 32'hBBBB_2222, "W-first readback");

    // ══════════════════════════════════
    // TEST 13: Back-to-back writes (4 writes rapidly)
    // Tests that slave handles continuous writes correctly
    // ══════════════════════════════════
    $display("\n── TEST 13: Back-to-back writes ──");
    axi_write(REG_SCRATCH_OFFSET, 32'h0000_0001, 4'b1111, wr_resp);
    axi_write(REG_SCRATCH_OFFSET, 32'h0000_0002, 4'b1111, wr_resp);
    axi_write(REG_SCRATCH_OFFSET, 32'h0000_0003, 4'b1111, wr_resp);
    axi_write(REG_SCRATCH_OFFSET, 32'h0000_0004, 4'b1111, wr_resp);
    // Last write should win
    read_and_check(REG_SCRATCH_OFFSET, 32'h0000_0004,
                   "Back-to-back final value");

    // ══════════════════════════════════
    // TEST 14: Back-to-back reads
    // ══════════════════════════════════
    $display("\n── TEST 14: Back-to-back reads ──");
    axi_write(REG_CTRL_OFFSET, 32'hFFFF_0000, 4'b1111, wr_resp);
    read_and_check(REG_CTRL_OFFSET, 32'hFFFF_0000, "B2B read 1");
    read_and_check(REG_CTRL_OFFSET, 32'hFFFF_0000, "B2B read 2");
    read_and_check(REG_CTRL_OFFSET, 32'hFFFF_0000, "B2B read 3");

    // ══════════════════════════════════
    // TEST 15: Write all writable registers, read all
    // ══════════════════════════════════
    $display("\n── TEST 15: Write all, Read all (integrity check) ──");
    axi_write(REG_CTRL_OFFSET,    32'h1111_1111, 4'b1111, wr_resp);
    axi_write(REG_DATA_TX_OFFSET, 32'h2222_2222, 4'b1111, wr_resp);
    axi_write(REG_IRQ_EN_OFFSET,  32'h3333_3333, 4'b1111, wr_resp);
    axi_write(REG_SCRATCH_OFFSET, 32'h4444_4444, 4'b1111, wr_resp);

    read_and_check(REG_CTRL_OFFSET,    32'h1111_1111, "Final CTRL");
    read_and_check(REG_DATA_TX_OFFSET, 32'h2222_2222, "Final DATA_TX");
    repeat (2) @(posedge aclk);  // Wait for loopback
    read_and_check(REG_DATA_RX_OFFSET, 32'h2222_2222, "Final DATA_RX");
    read_and_check(REG_IRQ_EN_OFFSET,  32'h3333_3333, "Final IRQ_EN");
    read_and_check(REG_SCRATCH_OFFSET, 32'h4444_4444, "Final SCRATCH");
    read_and_check(REG_VERSION_OFFSET, IP_VERSION,     "Final VERSION");

    // ══════════════════════════════════
    // TEST SUMMARY
    // ══════════════════════════════════
    repeat (10) @(posedge aclk);

    $display("\n");
    $display("╔══════════════════════════════════════════════╗");
    $display("║            TEST SUMMARY                      ║");
    $display("╠══════════════════════════════════════════════╣");
    $display("║  Total Tests:  %3d                           ║", total_tests);
    $display("║  Passed:       %3d                           ║", passed_tests);
    $display("║  Failed:       %3d                           ║", failed_tests);
    $display("╠══════════════════════════════════════════════╣");
    if (failed_tests == 0) begin
      $display("║  ALL TESTS PASSED!                          ║");
    end else begin
      $display("║  SOME TESTS FAILED!                         ║");
    end
    $display("╚══════════════════════════════════════════════╝");
    $display("\n");

    $finish;
  end

  // ═══════════════════════════════════════════════════════════
  // TIMEOUT WATCHDOG
  // Agar koi bug ki wajah se simulation hang ho jaaye,
  // yeh 200us baad automatically band kar dega
  // ═══════════════════════════════════════════════════════════
  initial begin
    #200_000;  // 200us max
    $display("\n[%0t] TIMEOUT! Simulation exceeded 200us", $time);
    $display("Check for deadlock: VALID asserted but READY never comes\n");
    $finish;
  end

endmodule : tb_axi4_lite_slave
