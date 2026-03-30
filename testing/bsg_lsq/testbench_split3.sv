/**
 *  testbench_split3.sv — bsg_lsq_split3 testbench
 *
 *  Tests:
 *    1. Store (addr+data together) → load forwarding
 *    2. Store addr first, data later → load forwarding
 *    3. Store data first, addr later → load forwarding
 *    4. Two stores same addr, youngest forwarded
 *    5. No forwarding (different addr)
 *    6. Fill and drain both queues
 */

`include "bsg_defines.sv"

module testbench;

  localparam sq_entries_p      = 4;
  localparam lq_entries_p      = 4;
  localparam addr_width_p      = 32;
  localparam data_width_p      = 32;
  localparam sq_id_width_lp    = `BSG_SAFE_CLOG2(sq_entries_p);
  localparam lq_id_width_lp    = `BSG_SAFE_CLOG2(lq_entries_p);
  localparam data_mask_width_lp = data_width_p >> 3;

  logic clk = 0;
  always #5 clk = ~clk;
  logic reset = 1;
  initial begin repeat (5) @(posedge clk); reset = 0; end

  // --- DUT signals ---
  logic sq_dv = 0, sq_dr;
  logic [sq_id_width_lp-1:0] sq_did;
  logic lq_dv = 0, lq_dr;
  logic [lq_id_width_lp-1:0] lq_did;

  logic sq_av = 0; logic [sq_id_width_lp-1:0] sq_aid; logic [addr_width_p-1:0] sq_aa;
  logic sq_dtv = 0; logic [sq_id_width_lp-1:0] sq_dtid; logic [data_width_p-1:0] sq_dd; logic [data_mask_width_lp-1:0] sq_dm;
  logic lq_ev = 0; logic [lq_id_width_lp-1:0] lq_eid; logic [addr_width_p-1:0] lq_ea;

  logic fwd_v; logic [lq_id_width_lp-1:0] fwd_lqid; logic [data_width_p-1:0] fwd_data;
  logic lq_crv; logic [addr_width_p-1:0] lq_cra; logic [lq_id_width_lp-1:0] lq_crid; logic lq_cry = 0;
  logic lq_cpv = 0; logic [lq_id_width_lp-1:0] lq_cpid; logic [data_width_p-1:0] lq_cpd;

  logic sq_cv; logic [sq_id_width_lp-1:0] sq_cid;
  logic [addr_width_p-1:0] sq_ca; logic [data_width_p-1:0] sq_cd; logic [data_mask_width_lp-1:0] sq_cm;
  logic sq_cyumi = 0;
  logic lq_cv; logic [lq_id_width_lp-1:0] lq_cid; logic [data_width_p-1:0] lq_cd; logic lq_cyumi = 0;

  bsg_lsq_split3 #(
    .sq_entries_p(sq_entries_p), .lq_entries_p(lq_entries_p)
   ,.addr_width_p(addr_width_p), .data_width_p(data_width_p)
  ) DUT (
    .clk_i(clk), .reset_i(reset)
   ,.sq_dispatch_v_i(sq_dv), .sq_dispatch_ready_o(sq_dr), .sq_dispatch_id_o(sq_did)
   ,.lq_dispatch_v_i(lq_dv), .lq_dispatch_ready_o(lq_dr), .lq_dispatch_id_o(lq_did)
   ,.sq_addr_v_i(sq_av), .sq_addr_id_i(sq_aid), .sq_addr_i(sq_aa)
   ,.sq_data_v_i(sq_dtv), .sq_data_id_i(sq_dtid), .sq_data_i(sq_dd), .sq_data_byte_mask_i(sq_dm)
   ,.lq_exe_v_i(lq_ev), .lq_exe_id_i(lq_eid), .lq_exe_addr_i(lq_ea)
   ,.fwd_v_o(fwd_v), .fwd_lq_id_o(fwd_lqid), .fwd_data_o(fwd_data)
   ,.lq_cache_req_v_o(lq_crv), .lq_cache_req_addr_o(lq_cra)
   ,.lq_cache_req_id_o(lq_crid), .lq_cache_req_yumi_i(lq_cry)
   ,.lq_cache_resp_v_i(lq_cpv), .lq_cache_resp_id_i(lq_cpid), .lq_cache_resp_data_i(lq_cpd)
   ,.sq_commit_v_o(sq_cv), .sq_commit_id_o(sq_cid), .sq_commit_addr_o(sq_ca)
   ,.sq_commit_data_o(sq_cd), .sq_commit_byte_mask_o(sq_cm), .sq_commit_yumi_i(sq_cyumi)
   ,.lq_commit_v_o(lq_cv), .lq_commit_id_o(lq_cid)
   ,.lq_commit_data_o(lq_cd), .lq_commit_yumi_i(lq_cyumi)
  );

  // --- Helpers ---
  integer error_cnt = 0;

  task automatic sq_dispatch(output logic [sq_id_width_lp-1:0] id);
    while (!sq_dr) @(posedge clk);
    @(negedge clk); sq_dv = 1;
    @(posedge clk); id = sq_did;
    @(negedge clk); sq_dv = 0;
  endtask

  task automatic lq_dispatch(output logic [lq_id_width_lp-1:0] id);
    while (!lq_dr) @(posedge clk);
    @(negedge clk); lq_dv = 1;
    @(posedge clk); id = lq_did;
    @(negedge clk); lq_dv = 0;
  endtask

  // Store addr write (separate from data)
  task automatic sq_write_addr(input [sq_id_width_lp-1:0] id, input [addr_width_p-1:0] addr);
    @(negedge clk); sq_av = 1; sq_aid = id; sq_aa = addr;
    @(posedge clk);
    @(negedge clk); sq_av = 0;
  endtask

  // Store data write (separate from addr)
  task automatic sq_write_data(input [sq_id_width_lp-1:0] id, input [data_width_p-1:0] data);
    @(negedge clk); sq_dtv = 1; sq_dtid = id; sq_dd = data; sq_dm = '1;
    @(posedge clk);
    @(negedge clk); sq_dtv = 0;
  endtask

  // Store addr+data together (convenience)
  task automatic sq_execute(input [sq_id_width_lp-1:0] id, input [addr_width_p-1:0] addr, input [data_width_p-1:0] data);
    @(negedge clk);
    sq_av = 1; sq_aid = id; sq_aa = addr;
    sq_dtv = 1; sq_dtid = id; sq_dd = data; sq_dm = '1;
    @(posedge clk);
    @(negedge clk); sq_av = 0; sq_dtv = 0;
  endtask

  task automatic lq_execute(input [lq_id_width_lp-1:0] id, input [addr_width_p-1:0] addr);
    @(negedge clk); lq_ev = 1; lq_eid = id; lq_ea = addr;
    @(posedge clk);
    @(negedge clk); lq_ev = 0;
  endtask

  task automatic check_fwd(input [lq_id_width_lp-1:0] exp_id, input logic exp_hit,
                           input [data_width_p-1:0] exp_data, input string label);
    #1; // combinational settle after negedge
    if (exp_hit) begin
      if (fwd_v && fwd_lqid == exp_id && fwd_data == exp_data)
        $display("  [PASS] %s: fwd hit lq=%0d data=0x%08h", label, fwd_lqid, fwd_data);
      else begin
        $error("  [FAIL] %s: fwd_v=%0b lq=%0d data=0x%08h, expected hit lq=%0d data=0x%08h",
          label, fwd_v, fwd_lqid, fwd_data, exp_id, exp_data);
        error_cnt++;
      end
    end else begin
      if (!fwd_v)
        $display("  [PASS] %s: no forwarding", label);
      else begin
        $error("  [FAIL] %s: unexpected fwd hit data=0x%08h", label, fwd_data);
        error_cnt++;
      end
    end
  endtask

  task automatic cache_resp(input [lq_id_width_lp-1:0] id, input [data_width_p-1:0] data);
    @(negedge clk); lq_cpv = 1; lq_cpid = id; lq_cpd = data;
    @(posedge clk);
    @(negedge clk); lq_cpv = 0;
  endtask

  task automatic sq_commit();
    while (!sq_cv) @(posedge clk);
    @(negedge clk); sq_cyumi = 1;
    @(posedge clk);
    @(negedge clk); sq_cyumi = 0;
  endtask

  task automatic lq_commit();
    while (!lq_cv) @(posedge clk);
    @(negedge clk); lq_cyumi = 1;
    @(posedge clk);
    @(negedge clk); lq_cyumi = 0;
  endtask

  task automatic wait_cycles(int n);
    repeat (n) @(posedge clk);
  endtask

  // --- Test sequence ---
  logic [sq_id_width_lp-1:0] sid_a, sid_b;
  logic [lq_id_width_lp-1:0] lid_a, lid_b;

  initial begin
    @(negedge reset); wait_cycles(3);

    // ==========================================================
    // TEST 1: Store addr+data together → load forwarding
    // ==========================================================
    $display("\n[TEST 1] Store addr+data together, then load");
    sq_dispatch(sid_a);
    sq_execute(sid_a, 32'h1000, 32'hDEAD_BEEF);
    lq_dispatch(lid_a);
    lq_execute(lid_a, 32'h1000);
    check_fwd(lid_a, 1'b1, 32'hDEAD_BEEF, "T1");
    sq_commit(); lq_commit();
    wait_cycles(2);

    // ==========================================================
    // TEST 2: Store addr first, data later → load sees forwarding
    // ==========================================================
    $display("\n[TEST 2] Store addr first, data arrives later");
    sq_dispatch(sid_a);
    sq_write_addr(sid_a, 32'h2000);
    // data not yet written — forward should miss
    lq_dispatch(lid_a);
    lq_execute(lid_a, 32'h2000);
    check_fwd(lid_a, 1'b0, '0, "T2-before-data");

    // Now write data
    sq_write_data(sid_a, 32'hCAFE_BABE);
    // Re-check forwarding (re-issue load execute to trigger new check)
    lq_execute(lid_a, 32'h2000);
    check_fwd(lid_a, 1'b1, 32'hCAFE_BABE, "T2-after-data");
    sq_commit();
    cache_resp(lid_a, 32'hCAFE_BABE); // provide data so LQ can commit
    lq_commit();
    wait_cycles(2);

    // ==========================================================
    // TEST 3: Store data first, addr later → forward after addr arrives
    // ==========================================================
    $display("\n[TEST 3] Store data first, addr arrives later");
    sq_dispatch(sid_a);
    sq_write_data(sid_a, 32'h1234_5678);
    // addr not yet written — CAM has no entry
    lq_dispatch(lid_a);
    lq_execute(lid_a, 32'h3000);
    check_fwd(lid_a, 1'b0, '0, "T3-before-addr");

    // Now write addr
    sq_write_addr(sid_a, 32'h3000);
    lq_execute(lid_a, 32'h3000);
    check_fwd(lid_a, 1'b1, 32'h1234_5678, "T3-after-addr");
    sq_commit();
    cache_resp(lid_a, 32'h1234_5678);
    lq_commit();
    wait_cycles(2);

    // ==========================================================
    // TEST 4: Two stores same addr, load picks youngest
    // ==========================================================
    $display("\n[TEST 4] Two stores same addr, youngest forwarded");
    sq_dispatch(sid_a);
    sq_dispatch(sid_b);
    sq_execute(sid_a, 32'h4000, 32'hAAAA_AAAA);
    sq_execute(sid_b, 32'h4000, 32'hBBBB_BBBB);
    lq_dispatch(lid_a);
    lq_execute(lid_a, 32'h4000);
    check_fwd(lid_a, 1'b1, 32'hBBBB_BBBB, "T4");
    sq_commit(); sq_commit(); lq_commit();
    wait_cycles(2);

    // ==========================================================
    // TEST 5: No forwarding (different addr)
    // ==========================================================
    $display("\n[TEST 5] Different addresses, no forwarding");
    sq_dispatch(sid_a);
    sq_execute(sid_a, 32'h5000, 32'hFFFF_FFFF);
    lq_dispatch(lid_a);
    lq_execute(lid_a, 32'h6000);
    check_fwd(lid_a, 1'b0, '0, "T5");
    sq_commit();
    cache_resp(lid_a, 32'h0000_0001);
    lq_commit();
    wait_cycles(2);

    // ==========================================================
    // TEST 6: Fill and drain
    // ==========================================================
    $display("\n[TEST 6] Fill SQ(%0d) and LQ(%0d)", sq_entries_p, lq_entries_p);
    begin
      logic [sq_id_width_lp-1:0] sids [sq_entries_p];
      logic [lq_id_width_lp-1:0] lids [lq_entries_p];

      for (int i = 0; i < sq_entries_p; i++) sq_dispatch(sids[i]);
      @(posedge clk);
      if (!sq_dr) $display("  [PASS] SQ full");
      else begin $error("  [FAIL] SQ should be full"); error_cnt++; end

      for (int i = 0; i < lq_entries_p; i++) lq_dispatch(lids[i]);
      @(posedge clk);
      if (!lq_dr) $display("  [PASS] LQ full");
      else begin $error("  [FAIL] LQ should be full"); error_cnt++; end

      // Execute all stores (addr+data)
      for (int i = 0; i < sq_entries_p; i++)
        sq_execute(sids[i], 32'h7000 + i*4, 32'hA000 + i);
      // Execute all loads + cache resp
      for (int i = 0; i < lq_entries_p; i++) begin
        lq_execute(lids[i], 32'h8000 + i*4);
        wait_cycles(1);
        cache_resp(lids[i], 32'hB000 + i);
      end
      // Drain
      for (int i = 0; i < sq_entries_p; i++) sq_commit();
      for (int i = 0; i < lq_entries_p; i++) lq_commit();

      @(posedge clk);
      if (sq_dr && lq_dr) $display("  [PASS] Both queues drained");
      else begin $error("  [FAIL] Queues not drained"); error_cnt++; end
    end

    // ==========================================================
    repeat (3) @(posedge clk);
    $display("\n========================================");
    if (error_cnt == 0)
      $display("[RESULT] ALL TESTS PASSED");
    else
      $display("[RESULT] FAILED: %0d errors", error_cnt);
    $display("========================================\n");
    $finish;
  end

  initial begin #300000; $display("[TIMEOUT]"); $finish; end

endmodule
