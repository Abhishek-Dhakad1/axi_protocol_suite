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

  localparam int AW = 32;
  localparam int DW = 32;
  localparam int SW = DW / 8;
  localparam int CLK_PERIOD = 10;

  logic aclk, aresetn;
  initial begin aclk = 0; forever #(CLK_PERIOD/2) aclk = ~aclk; end

  axi4_lite_if #(.ADDR_WIDTH(AW), .DATA_WIDTH(DW))
    axi_if (.aclk(aclk), .aresetn(aresetn));

  axi4_lite_slave #(.ADDR_WIDTH(AW), .DATA_WIDTH(DW))
    u_dut (.slv(axi_if.slave));

  int total_tests = 0, passed_tests = 0, failed_tests = 0;

  task automatic init_signals();
    axi_if.awaddr = 0; axi_if.awprot = 0; axi_if.awvalid = 0;
    axi_if.wdata  = 0; axi_if.wstrb  = 0; axi_if.wvalid  = 0;
    axi_if.bready = 0;
    axi_if.araddr = 0; axi_if.arprot = 0; axi_if.arvalid = 0;
    axi_if.rready = 0;
  endtask

  task automatic apply_reset();
    $display("[%0t] Reset...", $time);
    aresetn = 0; init_signals();
    repeat(5) @(posedge aclk);
    aresetn = 1;
    repeat(2) @(posedge aclk);
    $display("[%0t] Reset done.\n", $time);
  endtask

  // ── AXI WRITE ──
  // KEY FIX: Check ALL handshakes at posedge, THEN do ONE #1 for updates
  task automatic axi_write(
    input  logic [AW-1:0] addr,
    input  logic [DW-1:0] data,
    input  logic [SW-1:0] strb,
    output logic [1:0]    resp
  );
    logic aw_done, w_done, b_done;
    logic aw_hs, w_hs, b_hs;
    int cnt;

    // Drive signals
    @(posedge aclk); #1;
    axi_if.awaddr = addr; axi_if.awprot = 0; axi_if.awvalid = 1;
    axi_if.wdata  = data; axi_if.wstrb  = strb; axi_if.wvalid = 1;
    axi_if.bready = 1;

    aw_done = 0; w_done = 0; b_done = 0; cnt = 0;
    while (cnt < 200) begin
      @(posedge aclk);
      // Sample ALL handshakes at this posedge (no #1 between them!)
      aw_hs = axi_if.awvalid && axi_if.awready;
      w_hs  = axi_if.wvalid  && axi_if.wready;
      b_hs  = axi_if.bvalid  && axi_if.bready;

      if (!aw_done && aw_hs) aw_done = 1;
      if (!w_done && w_hs)   w_done  = 1;
      if (b_hs) begin resp = axi_if.bresp; b_done = 1; end

      // NOW update signals after all checks
      #1;
      if (aw_done) axi_if.awvalid = 0;
      if (w_done)  axi_if.wvalid  = 0;
      if (b_done)  break;
      cnt++;
    end

    // Give slave one cycle to process b_fire
    @(posedge aclk); #1;
    axi_if.bready = 0;
    @(posedge aclk);

    if (!b_done) begin
      $display("[%0t] WR TIMEOUT addr=0x%08h", $time, addr);
      resp = 2'b11;
      axi_if.awvalid = 0; axi_if.wvalid = 0; axi_if.bready = 0;
    end else begin
      $display("[%0t] WR addr=0x%08h data=0x%08h strb=%04b resp=%s",
        $time, addr, data, strb, (resp==RESP_OKAY)?"OK":"ERR");
    end
  endtask

  // ── AXI WRITE: AW first ──
  task automatic axi_write_aw_first(
    input  logic [AW-1:0] addr,
    input  logic [DW-1:0] data,
    input  int delay,
    output logic [1:0] resp
  );
    logic w_done, b_done, w_hs, b_hs;
    int cnt;

    // Phase 1: AW only
    @(posedge aclk); #1;
    axi_if.awaddr = addr; axi_if.awprot = 0; axi_if.awvalid = 1;
    axi_if.bready = 1;

    // Wait for AW handshake
    forever begin
      @(posedge aclk);
      if (axi_if.awvalid && axi_if.awready) break;
    end
    #1; axi_if.awvalid = 0;

    // Phase 2: Delay
    repeat(delay) @(posedge aclk);

    // Phase 3: W
    #1;
    axi_if.wdata = data; axi_if.wstrb = '1; axi_if.wvalid = 1;

    w_done = 0; b_done = 0; cnt = 0;
    while (cnt < 200) begin
      @(posedge aclk);
      w_hs = axi_if.wvalid && axi_if.wready;
      b_hs = axi_if.bvalid && axi_if.bready;
      if (!w_done && w_hs) w_done = 1;
      if (b_hs) begin resp = axi_if.bresp; b_done = 1; end
      #1;
      if (w_done) axi_if.wvalid = 0;
      if (b_done) break;
      cnt++;
    end

    @(posedge aclk); #1;
    axi_if.bready = 0;
    @(posedge aclk);

    $display("[%0t] WR(AW-first) addr=0x%08h resp=%s",
      $time, addr, (resp==RESP_OKAY)?"OK":"ERR");
  endtask

  // ── AXI WRITE: W first ──
  task automatic axi_write_w_first(
    input  logic [AW-1:0] addr,
    input  logic [DW-1:0] data,
    input  int delay,
    output logic [1:0] resp
  );
    logic aw_done, b_done, aw_hs, b_hs;
    int cnt;

    // Phase 1: W only
    @(posedge aclk); #1;
    axi_if.wdata = data; axi_if.wstrb = '1; axi_if.wvalid = 1;
    axi_if.bready = 1;

    // Wait for W handshake
    forever begin
      @(posedge aclk);
      if (axi_if.wvalid && axi_if.wready) break;
    end
    #1; axi_if.wvalid = 0;

    // Phase 2: Delay
    repeat(delay) @(posedge aclk);

    // Phase 3: AW
    #1;
    axi_if.awaddr = addr; axi_if.awprot = 0; axi_if.awvalid = 1;

    aw_done = 0; b_done = 0; cnt = 0;
    while (cnt < 200) begin
      @(posedge aclk);
      aw_hs = axi_if.awvalid && axi_if.awready;
      b_hs  = axi_if.bvalid  && axi_if.bready;
      if (!aw_done && aw_hs) aw_done = 1;
      if (b_hs) begin resp = axi_if.bresp; b_done = 1; end
      #1;
      if (aw_done) axi_if.awvalid = 0;
      if (b_done) break;
      cnt++;
    end

    @(posedge aclk); #1;
    axi_if.bready = 0;
    @(posedge aclk);

    $display("[%0t] WR(W-first) addr=0x%08h resp=%s",
      $time, addr, (resp==RESP_OKAY)?"OK":"ERR");
  endtask

  // ── AXI READ ──
  // KEY FIX: After capturing data, wait one cycle for slave to process r_fire
  task automatic axi_read(
    input  logic [AW-1:0] addr,
    output logic [DW-1:0] data,
    output logic [1:0]    resp
  );
    logic ar_done, r_done, ar_hs, r_hs;
    int cnt;

    @(posedge aclk); #1;
    axi_if.araddr = addr; axi_if.arprot = 0; axi_if.arvalid = 1;
    axi_if.rready = 1;

    ar_done = 0; r_done = 0; cnt = 0;
    while (cnt < 200) begin
      @(posedge aclk);
      // Sample at posedge
      ar_hs = axi_if.arvalid && axi_if.arready;
      r_hs  = axi_if.rvalid  && axi_if.rready;

      if (!ar_done && ar_hs) ar_done = 1;
      if (r_hs) begin data = axi_if.rdata; resp = axi_if.rresp; r_done = 1; end

      #1;
      if (ar_done) axi_if.arvalid = 0;
      if (r_done) break;
      cnt++;
    end

    // Give slave one cycle to process r_fire
    @(posedge aclk); #1;
    axi_if.rready = 0;
    @(posedge aclk);

    if (!r_done) begin
      $display("[%0t] RD TIMEOUT addr=0x%08h", $time, addr);
      data = 32'hDEADDEAD; resp = 2'b11;
      axi_if.arvalid = 0; axi_if.rready = 0;
    end else begin
      $display("[%0t] RD addr=0x%08h data=0x%08h resp=%s",
        $time, addr, data, (resp==RESP_OKAY)?"OK":"ERR");
    end
  endtask

  // ── Check helpers ──
  task automatic read_check(input logic [AW-1:0] a; input logic [DW-1:0] e; input string n);
    logic [DW-1:0] d; logic [1:0] r;
    axi_read(a, d, r);
    total_tests++;
    if (d === e && r === RESP_OKAY) begin
      passed_tests++; $display("[%0t] PASS %s exp=0x%08h got=0x%08h", $time, n, e, d);
    end else begin
      failed_tests++; $display("[%0t] FAIL %s exp=0x%08h got=0x%08h r=%02b", $time, n, e, d, r);
    end
  endtask

  task automatic check_resp(input logic [1:0] got, exp; input string n);
    total_tests++;
    if (got === exp) begin passed_tests++; $display("[%0t] PASS %s", $time, n); end
    else begin failed_tests++; $display("[%0t] FAIL %s exp=%02b got=%02b", $time, n, exp, got); end
  endtask

  // ── Main Test ──
  logic [DW-1:0] rd_data;
  logic [1:0] wr_resp, rd_resp;

  initial begin
    $dumpfile("axi4_lite_slave.vcd");
    $dumpvars(0, tb_axi4_lite_slave);
    $display("\n==== AXI4-Lite Slave TB ====\n");
    apply_reset();

    $display("-- T1: VERSION --");
    read_check(REG_VERSION_OFFSET, IP_VERSION, "VERSION");

    $display("-- T2: CTRL reset --");
    read_check(REG_CTRL_OFFSET, 32'h0, "CTRL_RST");

    $display("-- T3: W/R CTRL --");
    axi_write(REG_CTRL_OFFSET, 32'hCAFEBABE, 4'b1111, wr_resp);
    check_resp(wr_resp, RESP_OKAY, "CTRL_WR");
    read_check(REG_CTRL_OFFSET, 32'hCAFEBABE, "CTRL_RD");

    $display("-- T4: W/R SCRATCH --");
    axi_write(REG_SCRATCH_OFFSET, 32'hDEADBEEF, 4'b1111, wr_resp);
    check_resp(wr_resp, RESP_OKAY, "SCR_WR");
    read_check(REG_SCRATCH_OFFSET, 32'hDEADBEEF, "SCR_RD");

    $display("-- T5: TX->RX --");
    axi_write(REG_DATA_TX_OFFSET, 32'h12345678, 4'b1111, wr_resp);
    check_resp(wr_resp, RESP_OKAY, "TX_WR");
    read_check(REG_DATA_TX_OFFSET, 32'h12345678, "TX_RD");
    repeat(3) @(posedge aclk);
    read_check(REG_DATA_RX_OFFSET, 32'h12345678, "RX_LB");

    $display("-- T6: WR VERSION(RO) --");
    axi_write(REG_VERSION_OFFSET, 32'hFFFFFFFF, 4'b1111, wr_resp);
    check_resp(wr_resp, RESP_OKAY, "VER_WR");
    read_check(REG_VERSION_OFFSET, IP_VERSION, "VER_RO");

    $display("-- T7: WSTRB byte0 --");
    axi_write(REG_SCRATCH_OFFSET, 32'hAABBCCDD, 4'b1111, wr_resp);
    read_check(REG_SCRATCH_OFFSET, 32'hAABBCCDD, "SCR_FULL");
    axi_write(REG_SCRATCH_OFFSET, 32'h11111111, 4'b0001, wr_resp);
    read_check(REG_SCRATCH_OFFSET, 32'hAABBCC11, "SCR_B0");

    $display("-- T8: WSTRB upper --");
    axi_write(REG_SCRATCH_OFFSET, 32'hFF00FF00, 4'b1100, wr_resp);
    read_check(REG_SCRATCH_OFFSET, 32'hFF00CC11, "SCR_UP");

    $display("-- T9: OOR write --");
    axi_write(32'h100, 32'hBAADF00D, 4'b1111, wr_resp);
    check_resp(wr_resp, RESP_SLVERR, "OOR_WR");

    $display("-- T10: OOR read --");
    axi_read(32'h100, rd_data, rd_resp);
    total_tests++;
    if (rd_resp === RESP_SLVERR) begin
      passed_tests++; $display("[%0t] PASS OOR_RD", $time);
    end else begin
      failed_tests++; $display("[%0t] FAIL OOR_RD got=%02b", $time, rd_resp);
    end

    $display("-- T11: AW first --");
    axi_write_aw_first(REG_SCRATCH_OFFSET, 32'hAAAA1111, 2, wr_resp);
    check_resp(wr_resp, RESP_OKAY, "AWF_WR");
    read_check(REG_SCRATCH_OFFSET, 32'hAAAA1111, "AWF_RD");

    $display("-- T12: W first --");
    axi_write_w_first(REG_SCRATCH_OFFSET, 32'hBBBB2222, 3, wr_resp);
    check_resp(wr_resp, RESP_OKAY, "WF_WR");
    read_check(REG_SCRATCH_OFFSET, 32'hBBBB2222, "WF_RD");

    $display("-- T13: B2B writes --");
    axi_write(REG_SCRATCH_OFFSET, 32'h1, 4'b1111, wr_resp);
    axi_write(REG_SCRATCH_OFFSET, 32'h2, 4'b1111, wr_resp);
    axi_write(REG_SCRATCH_OFFSET, 32'h3, 4'b1111, wr_resp);
    axi_write(REG_SCRATCH_OFFSET, 32'h4, 4'b1111, wr_resp);
    read_check(REG_SCRATCH_OFFSET, 32'h4, "B2B");

    $display("-- T14: B2B reads --");
    axi_write(REG_CTRL_OFFSET, 32'hFFFF0000, 4'b1111, wr_resp);
    read_check(REG_CTRL_OFFSET, 32'hFFFF0000, "B2B_R1");
    read_check(REG_CTRL_OFFSET, 32'hFFFF0000, "B2B_R2");
    read_check(REG_CTRL_OFFSET, 32'hFFFF0000, "B2B_R3");

    $display("-- T15: All regs --");
    axi_write(REG_CTRL_OFFSET,    32'h11111111, 4'b1111, wr_resp);
    axi_write(REG_DATA_TX_OFFSET, 32'h22222222, 4'b1111, wr_resp);
    axi_write(REG_IRQ_EN_OFFSET,  32'h33333333, 4'b1111, wr_resp);
    axi_write(REG_SCRATCH_OFFSET, 32'h44444444, 4'b1111, wr_resp);
    read_check(REG_CTRL_OFFSET,    32'h11111111, "A_CTRL");
    read_check(REG_DATA_TX_OFFSET, 32'h22222222, "A_TX");
    repeat(3) @(posedge aclk);
    read_check(REG_DATA_RX_OFFSET, 32'h22222222, "A_RX");
    read_check(REG_IRQ_EN_OFFSET,  32'h33333333, "A_IRQ");
    read_check(REG_SCRATCH_OFFSET, 32'h44444444, "A_SCR");
    read_check(REG_VERSION_OFFSET, IP_VERSION,    "A_VER");

    repeat(5) @(posedge aclk);
    $display("\n==== SUMMARY ====");
    $display("Total: %0d  Pass: %0d  Fail: %0d", total_tests, passed_tests, failed_tests);
    if (failed_tests == 0) $display(">>> ALL TESTS PASSED <<<");
    else                   $display(">>> SOME FAILED <<<");
    $display("=================\n");
    $finish;
  end

  initial begin #5_000_000; $display("TIMEOUT"); $finish; end
endmodule : tb_axi4_lite_slave
FILEEND

echo "TB written."

# Also inline the read mux in slave for robustness
cat > rtl/axi4_lite/axi4_lite_slave.sv << 'FILEEND'
// File: rtl/axi4_lite/axi4_lite_slave.sv
// Author: Abhishek Dhakad
// AXI4-Lite Slave - individual regs, single always_ff, inline read mux

module axi4_lite_slave
  import axi_pkg::*;
#(
  parameter int ADDR_WIDTH = 32,
  parameter int DATA_WIDTH = 32
)(
  axi4_lite_if.slave slv
);
  localparam int STRB_WIDTH = DATA_WIDTH / 8;

  // Individual registers
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
    S_WR_IDLE=0, S_WR_GOT_AW=1, S_WR_GOT_W=2, S_WR_WRITE=3, S_WR_RESP=4
  } wr_state_e;
  wr_state_e wr_state_q;

  logic [ADDR_WIDTH-1:0] aw_addr_q;
  logic [DATA_WIDTH-1:0] w_data_q;
  logic [STRB_WIDTH-1:0] w_strb_q;

  // Read FSM
  typedef enum logic { S_RD_IDLE=0, S_RD_RESP=1 } rd_state_e;
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

  // Write helpers
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

      // ── Write FSM ──
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
              3'd0: for (int b=0;b<SW;b++) if(w_strb_q[b]) reg_ctrl[b*8+:8]     <= w_data_q[b*8+:8];
              3'd1: ; // STATUS RO
              3'd2: for (int b=0;b<SW;b++) if(w_strb_q[b]) reg_data_tx[b*8+:8]  <= w_data_q[b*8+:8];
              3'd3: ; // DATA_RX RO
              3'd4: for (int b=0;b<SW;b++) if(w_strb_q[b]) reg_irq_en[b*8+:8]   <= w_data_q[b*8+:8];
              3'd5: for (int b=0;b<SW;b++) if(w_strb_q[b])
                      for(int i=0;i<8;i++) if(w_data_q[b*8+i]) reg_irq_stat[b*8+i] <= 1'b0;
              3'd6: for (int b=0;b<SW;b++) if(w_strb_q[b]) reg_scratch[b*8+:8]  <= w_data_q[b*8+:8];
              3'd7: ; // VERSION RO
              default: ;
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

      // ── Read FSM (inline mux, no separate always_comb) ──
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
