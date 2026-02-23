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

  import axi_pkg::*;

  localparam int ADDR_WIDTH = 32;
  localparam int DATA_WIDTH = 32;
  localparam int STRB_WIDTH = DATA_WIDTH / 8;
  localparam int CLK_PERIOD = 10;

  logic aclk;
  logic aresetn;

  initial begin
    aclk = 1'b0;
    forever #(CLK_PERIOD / 2) aclk = ~aclk;
  end

  axi4_lite_if #(
    .ADDR_WIDTH(ADDR_WIDTH),
    .DATA_WIDTH(DATA_WIDTH)
  ) axi_if (
    .aclk    (aclk),
    .aresetn (aresetn)
  );

  axi4_lite_slave #(
    .ADDR_WIDTH(ADDR_WIDTH),
    .DATA_WIDTH(DATA_WIDTH)
  ) u_dut (
    .slv(axi_if.slave)
  );

  int total_tests  = 0;
  int passed_tests = 0;
  int failed_tests = 0;

  // ══════════════════════════════════════════
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

  // ══════════════════════════════════════════
  task automatic apply_reset();
    $display("[%0t] Applying Reset...", $time);
    aresetn = 1'b0;
    init_signals();
    repeat (5) @(posedge aclk);
    aresetn = 1'b1;
    repeat (2) @(posedge aclk);
    $display("[%0t] Reset Released.\n", $time);
  endtask

  // ══════════════════════════════════════════
  // AXI Write: Single loop checks AW, W, B
  // ══════════════════════════════════════════
  task automatic axi_write(
    input  logic [ADDR_WIDTH-1:0] addr,
    input  logic [DATA_WIDTH-1:0] data,
    input  logic [STRB_WIDTH-1:0] strb,
    output logic [1:0]            resp
  );
    int cnt;
    logic aw_done, w_done;

    @(posedge aclk);
    #1;
    axi_if.awaddr  = addr;
    axi_if.awprot  = 3'b000;
    axi_if.awvalid = 1'b1;
    axi_if.wdata   = data;
    axi_if.wstrb   = strb;
    axi_if.wvalid  = 1'b1;
    axi_if.bready  = 1'b1;

    aw_done = 0;
    w_done  = 0;
    cnt     = 0;

    while (cnt < 100) begin
      @(posedge aclk);
      if (!aw_done && axi_if.awvalid && axi_if.awready) begin
        aw_done = 1;
        #1; axi_if.awvalid = 1'b0;
      end
      if (!w_done && axi_if.wvalid && axi_if.wready) begin
        w_done = 1;
        #1; axi_if.wvalid = 1'b0;
      end
      if (axi_if.bvalid && axi_if.bready) begin
        resp = axi_if.bresp;
        #1; axi_if.bready = 1'b0;
        break;
      end
      cnt++;
    end

    if (cnt >= 100) begin
      $display("[%0t] ERROR: Write timeout! addr=0x%08h", $time, addr);
      resp = 2'b11;
      #1;
      axi_if.awvalid = 1'b0;
      axi_if.wvalid  = 1'b0;
      axi_if.bready  = 1'b0;
    end else begin
      $display("[%0t] WRITE: addr=0x%08h data=0x%08h strb=4'b%04b resp=%s",
               $time, addr, data, strb,
               (resp == RESP_OKAY) ? "OKAY" : "SLVERR");
    end
    // Wait 2 cycles for register write to settle
    repeat(2) @(posedge aclk);
  endtask

  // ══════════════════════════════════════════
  // AXI Write: AW first, then W
  // ══════════════════════════════════════════
  task automatic axi_write_aw_first(
    input  logic [ADDR_WIDTH-1:0] addr,
    input  logic [DATA_WIDTH-1:0] data,
    input  int                    delay,
    output logic [1:0]            resp
  );
    int cnt;

    $display("[%0t] WRITE(AW-first, %0d delay): addr=0x%08h", $time, delay, addr);

    @(posedge aclk);
    #1;
    axi_if.awaddr  = addr;
    axi_if.awprot  = 3'b000;
    axi_if.awvalid = 1'b1;
    axi_if.bready  = 1'b1;

    cnt = 0;
    while (cnt < 100) begin
      @(posedge aclk);
      if (axi_if.awvalid && axi_if.awready) begin
        #1; axi_if.awvalid = 1'b0;
        break;
      end
      cnt++;
    end

    repeat (delay) @(posedge aclk);

    #1;
    axi_if.wdata  = data;
    axi_if.wstrb  = '1;
    axi_if.wvalid = 1'b1;

    cnt = 0;
    while (cnt < 100) begin
      @(posedge aclk);
      if (axi_if.wvalid && axi_if.wready) begin
        #1; axi_if.wvalid = 1'b0;
      end
      if (axi_if.bvalid && axi_if.bready) begin
        resp = axi_if.bresp;
        #1; axi_if.bready = 1'b0;
        break;
      end
      cnt++;
    end

    $display("[%0t]   -> resp=%s", $time,
             (resp == RESP_OKAY) ? "OKAY" : "SLVERR");
    repeat(2) @(posedge aclk);
  endtask

  // ══════════════════════════════════════════
  // AXI Write: W first, then AW
  // ══════════════════════════════════════════
  task automatic axi_write_w_first(
    input  logic [ADDR_WIDTH-1:0] addr,
    input  logic [DATA_WIDTH-1:0] data,
    input  int                    delay,
    output logic [1:0]            resp
  );
    int cnt;

    $display("[%0t] WRITE(W-first, %0d delay): addr=0x%08h", $time, delay, addr);

    @(posedge aclk);
    #1;
    axi_if.wdata  = data;
    axi_if.wstrb  = '1;
    axi_if.wvalid = 1'b1;
    axi_if.bready = 1'b1;

    cnt = 0;
    while (cnt < 100) begin
      @(posedge aclk);
      if (axi_if.wvalid && axi_if.wready) begin
        #1; axi_if.wvalid = 1'b0;
        break;
      end
      cnt++;
    end

    repeat (delay) @(posedge aclk);

    #1;
    axi_if.awaddr  = addr;
    axi_if.awprot  = 3'b000;
    axi_if.awvalid = 1'b1;

    cnt = 0;
    while (cnt < 100) begin
      @(posedge aclk);
      if (axi_if.awvalid && axi_if.awready) begin
        #1; axi_if.awvalid = 1'b0;
      end
      if (axi_if.bvalid && axi_if.bready) begin
        resp = axi_if.bresp;
        #1; axi_if.bready = 1'b0;
        break;
      end
      cnt++;
    end

    $display("[%0t]   -> resp=%s", $time,
             (resp == RESP_OKAY) ? "OKAY" : "SLVERR");
    repeat(2) @(posedge aclk);
  endtask

  // ══════════════════════════════════════════
  // AXI Read
  // ══════════════════════════════════════════
  task automatic axi_read(
    input  logic [ADDR_WIDTH-1:0] addr,
    output logic [DATA_WIDTH-1:0] data,
    output logic [1:0]            resp
  );
    int cnt;
    logic ar_done;

    @(posedge aclk);
    #1;
    axi_if.araddr  = addr;
    axi_if.arprot  = 3'b000;
    axi_if.arvalid = 1'b1;
    axi_if.rready  = 1'b1;

    ar_done = 0;
    cnt = 0;

    while (cnt < 100) begin
      @(posedge aclk);
      if (!ar_done && axi_if.arvalid && axi_if.arready) begin
        ar_done = 1;
        #1; axi_if.arvalid = 1'b0;
      end
      if (axi_if.rvalid && axi_if.rready) begin
        data = axi_if.rdata;
        resp = axi_if.rresp;
        #1; axi_if.rready = 1'b0;
        break;
      end
      cnt++;
    end

    if (cnt >= 100) begin
      $display("[%0t] ERROR: Read timeout! addr=0x%08h", $time, addr);
      data = 32'hDEADDEAD;
      resp = 2'b11;
      #1;
      axi_if.arvalid = 1'b0;
      axi_if.rready  = 1'b0;
    end else begin
      $display("[%0t] READ:  addr=0x%08h data=0x%08h resp=%s",
               $time, addr, data,
               (resp == RESP_OKAY) ? "OKAY" : "SLVERR");
    end
    @(posedge aclk);
  endtask

  // ══════════════════════════════════════════
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
      $display("[%0t] PASS: %s | Exp=0x%08h Got=0x%08h",
               $time, test_name, expected, got_data);
    end else begin
      failed_tests++;
      $display("[%0t] FAIL: %s | Exp=0x%08h Got=0x%08h Resp=%02b",
               $time, test_name, expected, got_data, got_resp);
    end
  endtask

  // ══════════════════════════════════════════
  task automatic check_resp(
    input logic [1:0] got,
    input logic [1:0] expected,
    input string      test_name
  );
    total_tests++;
    if (got === expected) begin
      passed_tests++;
      $display("[%0t] PASS: %s", $time, test_name);
    end else begin
      failed_tests++;
      $display("[%0t] FAIL: %s | Exp=%02b Got=%02b",
               $time, test_name, expected, got);
    end
  endtask

  // ══════════════════════════════════════════
  // MAIN TEST
  // ══════════════════════════════════════════
  logic [DATA_WIDTH-1:0] rd_data;
  logic [1:0] wr_resp, rd_resp;

  initial begin
    $dumpfile("axi4_lite_slave.vcd");
    $dumpvars(0, tb_axi4_lite_slave);

    $display("\n");
    $display("==================================================");
    $display("  AXI4-Lite Slave Testbench");
    $display("  Author: Abhishek Dhakad");
    $display("==================================================");

    apply_reset();

    // TEST 1
    $display("\n-- TEST 1: VERSION register after reset --");
    read_and_check(REG_VERSION_OFFSET, IP_VERSION, "VERSION after reset");

    // TEST 2
    $display("\n-- TEST 2: CTRL register after reset --");
    read_and_check(REG_CTRL_OFFSET, 32'h0, "CTRL after reset");

    // TEST 3
    $display("\n-- TEST 3: Write/Read CTRL --");
    axi_write(REG_CTRL_OFFSET, 32'hCAFEBABE, 4'b1111, wr_resp);
    check_resp(wr_resp, RESP_OKAY, "CTRL write resp");
    read_and_check(REG_CTRL_OFFSET, 32'hCAFEBABE, "CTRL readback");

    // TEST 4
    $display("\n-- TEST 4: Write/Read SCRATCH --");
    axi_write(REG_SCRATCH_OFFSET, 32'hDEADBEEF, 4'b1111, wr_resp);
    check_resp(wr_resp, RESP_OKAY, "SCRATCH write resp");
    read_and_check(REG_SCRATCH_OFFSET, 32'hDEADBEEF, "SCRATCH readback");

    // TEST 5
    $display("\n-- TEST 5: DATA_TX -> DATA_RX loopback --");
    axi_write(REG_DATA_TX_OFFSET, 32'h12345678, 4'b1111, wr_resp);
    check_resp(wr_resp, RESP_OKAY, "DATA_TX write resp");
    read_and_check(REG_DATA_TX_OFFSET, 32'h12345678, "DATA_TX readback");
    repeat (3) @(posedge aclk);
    read_and_check(REG_DATA_RX_OFFSET, 32'h12345678, "DATA_RX loopback");

    // TEST 6
    $display("\n-- TEST 6: Write to READ-ONLY VERSION --");
    axi_write(REG_VERSION_OFFSET, 32'hFFFFFFFF, 4'b1111, wr_resp);
    check_resp(wr_resp, RESP_OKAY, "VERSION write resp (ignored)");
    read_and_check(REG_VERSION_OFFSET, IP_VERSION, "VERSION unchanged");

    // TEST 7
    $display("\n-- TEST 7: WSTRB - byte 0 only --");
    axi_write(REG_SCRATCH_OFFSET, 32'hAABBCCDD, 4'b1111, wr_resp);
    read_and_check(REG_SCRATCH_OFFSET, 32'hAABBCCDD, "SCRATCH = 0xAABBCCDD");
    axi_write(REG_SCRATCH_OFFSET, 32'h11111111, 4'b0001, wr_resp);
    read_and_check(REG_SCRATCH_OFFSET, 32'hAABBCC11, "SCRATCH byte0 only");

    // TEST 8
    $display("\n-- TEST 8: WSTRB - upper 2 bytes --");
    axi_write(REG_SCRATCH_OFFSET, 32'hFF00FF00, 4'b1100, wr_resp);
    read_and_check(REG_SCRATCH_OFFSET, 32'hFF00CC11, "SCRATCH upper bytes");

    // TEST 9
    $display("\n-- TEST 9: Out-of-range write -> SLVERR --");
    axi_write(32'h00000100, 32'hBAADF00D, 4'b1111, wr_resp);
    check_resp(wr_resp, RESP_SLVERR, "Out-of-range write SLVERR");

    // TEST 10
    $display("\n-- TEST 10: Out-of-range read -> SLVERR --");
    axi_read(32'h00000100, rd_data, rd_resp);
    total_tests++;
    if (rd_resp === RESP_SLVERR) begin
      passed_tests++;
      $display("[%0t] PASS: Out-of-range read SLVERR", $time);
    end else begin
      failed_tests++;
      $display("[%0t] FAIL: Expected SLVERR got %02b", $time, rd_resp);
    end

    // TEST 11
    $display("\n-- TEST 11: AW before W (2 cycle gap) --");
    axi_write_aw_first(REG_SCRATCH_OFFSET, 32'hAAAA1111, 2, wr_resp);
    check_resp(wr_resp, RESP_OKAY, "AW-first write resp");
    read_and_check(REG_SCRATCH_OFFSET, 32'hAAAA1111, "AW-first readback");

    // TEST 12
    $display("\n-- TEST 12: W before AW (3 cycle gap) --");
    axi_write_w_first(REG_SCRATCH_OFFSET, 32'hBBBB2222, 3, wr_resp);
    check_resp(wr_resp, RESP_OKAY, "W-first write resp");
    read_and_check(REG_SCRATCH_OFFSET, 32'hBBBB2222, "W-first readback");

    // TEST 13
    $display("\n-- TEST 13: Back-to-back writes --");
    axi_write(REG_SCRATCH_OFFSET, 32'h00000001, 4'b1111, wr_resp);
    axi_write(REG_SCRATCH_OFFSET, 32'h00000002, 4'b1111, wr_resp);
    axi_write(REG_SCRATCH_OFFSET, 32'h00000003, 4'b1111, wr_resp);
    axi_write(REG_SCRATCH_OFFSET, 32'h00000004, 4'b1111, wr_resp);
    read_and_check(REG_SCRATCH_OFFSET, 32'h00000004, "B2B final value");

    // TEST 14
    $display("\n-- TEST 14: Back-to-back reads --");
    axi_write(REG_CTRL_OFFSET, 32'hFFFF0000, 4'b1111, wr_resp);
    read_and_check(REG_CTRL_OFFSET, 32'hFFFF0000, "B2B read 1");
    read_and_check(REG_CTRL_OFFSET, 32'hFFFF0000, "B2B read 2");
    read_and_check(REG_CTRL_OFFSET, 32'hFFFF0000, "B2B read 3");

    // TEST 15
    $display("\n-- TEST 15: Write all, Read all --");
    axi_write(REG_CTRL_OFFSET,    32'h11111111, 4'b1111, wr_resp);
    axi_write(REG_DATA_TX_OFFSET, 32'h22222222, 4'b1111, wr_resp);
    axi_write(REG_IRQ_EN_OFFSET,  32'h33333333, 4'b1111, wr_resp);
    axi_write(REG_SCRATCH_OFFSET, 32'h44444444, 4'b1111, wr_resp);
    read_and_check(REG_CTRL_OFFSET,    32'h11111111, "Final CTRL");
    read_and_check(REG_DATA_TX_OFFSET, 32'h22222222, "Final DATA_TX");
    repeat (3) @(posedge aclk);
    read_and_check(REG_DATA_RX_OFFSET, 32'h22222222, "Final DATA_RX");
    read_and_check(REG_IRQ_EN_OFFSET,  32'h33333333, "Final IRQ_EN");
    read_and_check(REG_SCRATCH_OFFSET, 32'h44444444, "Final SCRATCH");
    read_and_check(REG_VERSION_OFFSET, IP_VERSION,    "Final VERSION");

    // SUMMARY
    repeat (10) @(posedge aclk);
    $display("\n==================================================");
    $display("  TEST SUMMARY");
    $display("==================================================");
    $display("  Total:  %0d", total_tests);
    $display("  Passed: %0d", passed_tests);
    $display("  Failed: %0d", failed_tests);
    $display("==================================================");
    if (failed_tests == 0)
      $display("  >>> ALL TESTS PASSED! <<<");
    else
      $display("  >>> SOME TESTS FAILED! <<<");
    $display("==================================================\n");
    $finish;
  end

  initial begin
    #1_000_000;
    $display("\n[%0t] TIMEOUT!", $time);
    $finish;
  end

endmodule : tb_axi4_lite_slave
