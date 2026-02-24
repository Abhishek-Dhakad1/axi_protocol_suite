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

  axi4_lite_if #(.ADDR_WIDTH(ADDR_WIDTH), .DATA_WIDTH(DATA_WIDTH))
    axi_if (.aclk(aclk), .aresetn(aresetn));

  axi4_lite_slave #(.ADDR_WIDTH(ADDR_WIDTH), .DATA_WIDTH(DATA_WIDTH))
    u_dut (.slv(axi_if.slave));

  int total_tests  = 0;
  int passed_tests = 0;
  int failed_tests = 0;

  // ── Init ──
  task automatic init_signals();
    axi_if.awaddr  = '0; axi_if.awprot  = '0; axi_if.awvalid = 0;
    axi_if.wdata   = '0; axi_if.wstrb   = '0; axi_if.wvalid  = 0;
    axi_if.bready  = 0;
    axi_if.araddr  = '0; axi_if.arprot  = '0; axi_if.arvalid = 0;
    axi_if.rready  = 0;
  endtask

  // ── Reset ──
  task automatic apply_reset();
    $display("[%0t] Reset...", $time);
    aresetn = 0; init_signals();
    repeat(5) @(posedge aclk);
    aresetn = 1;
    repeat(2) @(posedge aclk);
    $display("[%0t] Reset done.\n", $time);
  endtask

  // ── AXI Write (AW+W simultaneous) ──
  task automatic axi_write(
    input  logic [ADDR_WIDTH-1:0] addr,
    input  logic [DATA_WIDTH-1:0] data,
    input  logic [STRB_WIDTH-1:0] strb,
    output logic [1:0]            resp
  );
    int cnt;
    logic aw_done, w_done;

    @(posedge aclk); #1;
    axi_if.awaddr = addr; axi_if.awprot = '0; axi_if.awvalid = 1;
    axi_if.wdata  = data; axi_if.wstrb  = strb; axi_if.wvalid = 1;
    axi_if.bready = 1;

    aw_done = 0; w_done = 0; cnt = 0;
    while (cnt < 200) begin
      @(posedge aclk);
      if (!aw_done && axi_if.awvalid && axi_if.awready) begin
        aw_done = 1; #1; axi_if.awvalid = 0;
      end
      if (!w_done && axi_if.wvalid && axi_if.wready) begin
        w_done = 1; #1; axi_if.wvalid = 0;
      end
      if (axi_if.bvalid && axi_if.bready) begin
        resp = axi_if.bresp; #1; axi_if.bready = 0;
        break;
      end
      cnt++;
    end
    if (cnt >= 200) begin
      $display("[%0t] WR TIMEOUT addr=0x%08h", $time, addr);
      resp = 2'b11;
      #1; axi_if.awvalid=0; axi_if.wvalid=0; axi_if.bready=0;
    end else begin
      $display("[%0t] WR addr=0x%08h data=0x%08h strb=%04b resp=%s",
        $time, addr, data, strb, (resp==RESP_OKAY)?"OK":"ERR");
    end
    repeat(2) @(posedge aclk);
  endtask

  // ── AXI Write: AW first ──
  task automatic axi_write_aw_first(
    input  logic [ADDR_WIDTH-1:0] addr,
    input  logic [DATA_WIDTH-1:0] data,
    input  int delay,
    output logic [1:0] resp
  );
    int cnt;
    @(posedge aclk); #1;
    axi_if.awaddr = addr; axi_if.awprot = '0; axi_if.awvalid = 1;
    axi_if.bready = 1;
    cnt = 0;
    while (cnt < 200) begin
      @(posedge aclk);
      if (axi_if.awvalid && axi_if.awready) begin
        #1; axi_if.awvalid = 0; break;
      end
      cnt++;
    end
    repeat(delay) @(posedge aclk);
    #1;
    axi_if.wdata = data; axi_if.wstrb = '1; axi_if.wvalid = 1;
    cnt = 0;
    while (cnt < 200) begin
      @(posedge aclk);
      if (axi_if.wvalid && axi_if.wready) begin
        #1; axi_if.wvalid = 0;
      end
      if (axi_if.bvalid && axi_if.bready) begin
        resp = axi_if.bresp; #1; axi_if.bready = 0; break;
      end
      cnt++;
    end
    $display("[%0t] WR(AW-first) addr=0x%08h resp=%s",
      $time, addr, (resp==RESP_OKAY)?"OK":"ERR");
    repeat(2) @(posedge aclk);
  endtask

  // ── AXI Write: W first ──
  task automatic axi_write_w_first(
    input  logic [ADDR_WIDTH-1:0] addr,
    input  logic [DATA_WIDTH-1:0] data,
    input  int delay,
    output logic [1:0] resp
  );
    int cnt;
    @(posedge aclk); #1;
    axi_if.wdata = data; axi_if.wstrb = '1; axi_if.wvalid = 1;
    axi_if.bready = 1;
    cnt = 0;
    while (cnt < 200) begin
      @(posedge aclk);
      if (axi_if.wvalid && axi_if.wready) begin
        #1; axi_if.wvalid = 0; break;
      end
      cnt++;
    end
    repeat(delay) @(posedge aclk);
    #1;
    axi_if.awaddr = addr; axi_if.awprot = '0; axi_if.awvalid = 1;
    cnt = 0;
    while (cnt < 200) begin
      @(posedge aclk);
      if (axi_if.awvalid && axi_if.awready) begin
        #1; axi_if.awvalid = 0;
      end
      if (axi_if.bvalid && axi_if.bready) begin
        resp = axi_if.bresp; #1; axi_if.bready = 0; break;
      end
      cnt++;
    end
    $display("[%0t] WR(W-first) addr=0x%08h resp=%s",
      $time, addr, (resp==RESP_OKAY)?"OK":"ERR");
    repeat(2) @(posedge aclk);
  endtask

  // ── AXI Read ──
  task automatic axi_read(
    input  logic [ADDR_WIDTH-1:0] addr,
    output logic [DATA_WIDTH-1:0] data,
    output logic [1:0] resp
  );
    int cnt;
    logic ar_done;
    @(posedge aclk); #1;
    axi_if.araddr = addr; axi_if.arprot = '0; axi_if.arvalid = 1;
    axi_if.rready = 1;
    ar_done = 0; cnt = 0;
    while (cnt < 200) begin
      @(posedge aclk);
      if (!ar_done && axi_if.arvalid && axi_if.arready) begin
        ar_done = 1; #1; axi_if.arvalid = 0;
      end
      if (axi_if.rvalid && axi_if.rready) begin
        data = axi_if.rdata; resp = axi_if.rresp;
        #1; axi_if.rready = 0; break;
      end
      cnt++;
    end
    if (cnt >= 200) begin
      $display("[%0t] RD TIMEOUT addr=0x%08h", $time, addr);
      data = 32'hDEADDEAD; resp = 2'b11;
      #1; axi_if.arvalid=0; axi_if.rready=0;
    end else begin
      $display("[%0t] RD addr=0x%08h data=0x%08h resp=%s",
        $time, addr, data, (resp==RESP_OKAY)?"OK":"ERR");
    end
    @(posedge aclk);
  endtask

  // ── Check helpers ──
  task automatic read_check(
    input logic [ADDR_WIDTH-1:0] addr,
    input logic [DATA_WIDTH-1:0] expected,
    input string name
  );
    logic [DATA_WIDTH-1:0] d; logic [1:0] r;
    axi_read(addr, d, r);
    total_tests++;
    if (d === expected && r === RESP_OKAY) begin
      passed_tests++;
      $display("[%0t] PASS %s exp=0x%08h got=0x%08h", $time, name, expected, d);
    end else begin
      failed_tests++;
      $display("[%0t] FAIL %s exp=0x%08h got=0x%08h r=%02b", $time, name, expected, d, r);
    end
  endtask

  task automatic check_resp(input logic [1:0] got, exp; input string name);
    total_tests++;
    if (got === exp) begin passed_tests++; $display("[%0t] PASS %s", $time, name); end
    else begin failed_tests++; $display("[%0t] FAIL %s exp=%02b got=%02b", $time, name, exp, got); end
  endtask

  // ── Main ──
  logic [DATA_WIDTH-1:0] rd_data;
  logic [1:0] wr_resp, rd_resp;

  initial begin
    $dumpfile("axi4_lite_slave.vcd");
    $dumpvars(0, tb_axi4_lite_slave);

    $display("\n==== AXI4-Lite Slave TB - Abhishek Dhakad ====\n");
    apply_reset();

    // T1: VERSION after reset
    $display("-- T1: VERSION --");
    read_check(REG_VERSION_OFFSET, IP_VERSION, "VERSION");

    // T2: CTRL after reset
    $display("-- T2: CTRL reset --");
    read_check(REG_CTRL_OFFSET, 32'h0, "CTRL_RST");

    // T3: Write/Read CTRL
    $display("-- T3: W/R CTRL --");
    axi_write(REG_CTRL_OFFSET, 32'hCAFEBABE, 4'b1111, wr_resp);
    check_resp(wr_resp, RESP_OKAY, "CTRL_WR");
    read_check(REG_CTRL_OFFSET, 32'hCAFEBABE, "CTRL_RD");

    // T4: Write/Read SCRATCH
    $display("-- T4: W/R SCRATCH --");
    axi_write(REG_SCRATCH_OFFSET, 32'hDEADBEEF, 4'b1111, wr_resp);
    check_resp(wr_resp, RESP_OKAY, "SCRATCH_WR");
    read_check(REG_SCRATCH_OFFSET, 32'hDEADBEEF, "SCRATCH_RD");

    // T5: TX->RX loopback
    $display("-- T5: TX->RX --");
    axi_write(REG_DATA_TX_OFFSET, 32'h12345678, 4'b1111, wr_resp);
    check_resp(wr_resp, RESP_OKAY, "TX_WR");
    read_check(REG_DATA_TX_OFFSET, 32'h12345678, "TX_RD");
    repeat(3) @(posedge aclk);
    read_check(REG_DATA_RX_OFFSET, 32'h12345678, "RX_LB");

    // T6: Write to RO VERSION
    $display("-- T6: WR to VERSION(RO) --");
    axi_write(REG_VERSION_OFFSET, 32'hFFFFFFFF, 4'b1111, wr_resp);
    check_resp(wr_resp, RESP_OKAY, "VER_WR");
    read_check(REG_VERSION_OFFSET, IP_VERSION, "VER_RO");

    // T7: WSTRB byte0
    $display("-- T7: WSTRB byte0 --");
    axi_write(REG_SCRATCH_OFFSET, 32'hAABBCCDD, 4'b1111, wr_resp);
    read_check(REG_SCRATCH_OFFSET, 32'hAABBCCDD, "SCR_FULL");
    axi_write(REG_SCRATCH_OFFSET, 32'h11111111, 4'b0001, wr_resp);
    read_check(REG_SCRATCH_OFFSET, 32'hAABBCC11, "SCR_B0");

    // T8: WSTRB upper
    $display("-- T8: WSTRB upper --");
    axi_write(REG_SCRATCH_OFFSET, 32'hFF00FF00, 4'b1100, wr_resp);
    read_check(REG_SCRATCH_OFFSET, 32'hFF00CC11, "SCR_UP");

    // T9: OOR write
    $display("-- T9: OOR write --");
    axi_write(32'h100, 32'hBAADF00D, 4'b1111, wr_resp);
    check_resp(wr_resp, RESP_SLVERR, "OOR_WR");

    // T10: OOR read
    $display("-- T10: OOR read --");
    axi_read(32'h100, rd_data, rd_resp);
    total_tests++;
    if (rd_resp === RESP_SLVERR) begin
      passed_tests++; $display("[%0t] PASS OOR_RD", $time);
    end else begin
      failed_tests++; $display("[%0t] FAIL OOR_RD exp=SLVERR got=%02b", $time, rd_resp);
    end

    // T11: AW before W
    $display("-- T11: AW first --");
    axi_write_aw_first(REG_SCRATCH_OFFSET, 32'hAAAA1111, 2, wr_resp);
    check_resp(wr_resp, RESP_OKAY, "AWF_WR");
    read_check(REG_SCRATCH_OFFSET, 32'hAAAA1111, "AWF_RD");

    // T12: W before AW
    $display("-- T12: W first --");
    axi_write_w_first(REG_SCRATCH_OFFSET, 32'hBBBB2222, 3, wr_resp);
    check_resp(wr_resp, RESP_OKAY, "WF_WR");
    read_check(REG_SCRATCH_OFFSET, 32'hBBBB2222, "WF_RD");

    // T13: B2B writes
    $display("-- T13: B2B writes --");
    axi_write(REG_SCRATCH_OFFSET, 32'h1, 4'b1111, wr_resp);
    axi_write(REG_SCRATCH_OFFSET, 32'h2, 4'b1111, wr_resp);
    axi_write(REG_SCRATCH_OFFSET, 32'h3, 4'b1111, wr_resp);
    axi_write(REG_SCRATCH_OFFSET, 32'h4, 4'b1111, wr_resp);
    read_check(REG_SCRATCH_OFFSET, 32'h4, "B2B_FINAL");

    // T14: B2B reads
    $display("-- T14: B2B reads --");
    axi_write(REG_CTRL_OFFSET, 32'hFFFF0000, 4'b1111, wr_resp);
    read_check(REG_CTRL_OFFSET, 32'hFFFF0000, "B2B_R1");
    read_check(REG_CTRL_OFFSET, 32'hFFFF0000, "B2B_R2");
    read_check(REG_CTRL_OFFSET, 32'hFFFF0000, "B2B_R3");

    // T15: Write all, read all
    $display("-- T15: All regs --");
    axi_write(REG_CTRL_OFFSET,    32'h11111111, 4'b1111, wr_resp);
    axi_write(REG_DATA_TX_OFFSET, 32'h22222222, 4'b1111, wr_resp);
    axi_write(REG_IRQ_EN_OFFSET,  32'h33333333, 4'b1111, wr_resp);
    axi_write(REG_SCRATCH_OFFSET, 32'h44444444, 4'b1111, wr_resp);
    read_check(REG_CTRL_OFFSET,    32'h11111111, "ALL_CTRL");
    read_check(REG_DATA_TX_OFFSET, 32'h22222222, "ALL_TX");
    repeat(3) @(posedge aclk);
    read_check(REG_DATA_RX_OFFSET, 32'h22222222, "ALL_RX");
    read_check(REG_IRQ_EN_OFFSET,  32'h33333333, "ALL_IRQ");
    read_check(REG_SCRATCH_OFFSET, 32'h44444444, "ALL_SCR");
    read_check(REG_VERSION_OFFSET, IP_VERSION,    "ALL_VER");

    // Summary
    repeat(5) @(posedge aclk);
    $display("\n==== SUMMARY ====");
    $display("Total: %0d  Pass: %0d  Fail: %0d", total_tests, passed_tests, failed_tests);
    if (failed_tests == 0) $display(">>> ALL TESTS PASSED <<<");
    else                   $display(">>> SOME FAILED <<<");
    $display("=================\n");
    $finish;
  end

  // Timeout
  initial begin #2_000_000; $display("TIMEOUT"); $finish; end

endmodule : tb_axi4_lite_slave
