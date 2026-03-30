/**
 *  testbench.sv — bsg_lsq testbench
 *
 *  Tests:
 *    1. Basic store then load (same address) — verify forwarding
 *    2. Multiple stores, load picks youngest older store
 *    3. Load without forwarding (goes to cache, gets response)
 *    4. Full queue back-pressure
 *    5. Interleaved stores and loads with correct age ordering
 */

`include "bsg_defines.sv"

module testbench;

  localparam lsq_entries_p      = 8;
  localparam addr_width_p       = 32;
  localparam data_width_p       = 32;
  localparam entry_id_width_lp  = `BSG_SAFE_CLOG2(lsq_entries_p);
  localparam data_mask_width_lp = data_width_p >> 3;

  // -------------------------------------------------------
  // Clock / Reset
  // -------------------------------------------------------
  logic clk, reset;
  initial clk = 0;
  always #5 clk = ~clk;

  initial begin
    reset = 1;
    repeat (5) @(posedge clk);
    reset = 0;
  end

  // -------------------------------------------------------
  // DUT signals
  // -------------------------------------------------------
  logic                            dispatch_v;
  logic                            dispatch_is_store;
  logic                            dispatch_ready;
  logic [entry_id_width_lp-1:0]    dispatch_id;

  logic                            exe_v;
  logic [entry_id_width_lp-1:0]    exe_id;
  logic [addr_width_p-1:0]         exe_addr;
  logic [data_width_p-1:0]         exe_data;
  logic [data_mask_width_lp-1:0]   exe_byte_mask;

  logic                            cache_req_v;
  logic                            cache_req_is_store;
  logic [addr_width_p-1:0]         cache_req_addr;
  logic [data_width_p-1:0]         cache_req_data;
  logic [data_mask_width_lp-1:0]   cache_req_byte_mask;
  logic [entry_id_width_lp-1:0]    cache_req_id;
  logic                            cache_req_yumi;

  logic                            cache_resp_v;
  logic [entry_id_width_lp-1:0]    cache_resp_id;
  logic [data_width_p-1:0]         cache_resp_data;

  logic                            fwd_check_v;
  logic [entry_id_width_lp-1:0]    fwd_check_id;
  logic [addr_width_p-1:0]         fwd_check_addr;
  logic                            fwd_hit;
  logic [data_width_p-1:0]         fwd_data;

  logic                            commit_v;
  logic [entry_id_width_lp-1:0]    commit_id;
  logic                            commit_is_store;
  logic [data_width_p-1:0]         commit_data;
  logic [addr_width_p-1:0]         commit_addr;
  logic                            commit_yumi;

  // -------------------------------------------------------
  // DUT
  // -------------------------------------------------------
  bsg_lsq #(
    .lsq_entries_p(lsq_entries_p)
   ,.addr_width_p(addr_width_p)
   ,.data_width_p(data_width_p)
  ) DUT (
    .clk_i(clk), .reset_i(reset)
   ,.dispatch_v_i(dispatch_v), .dispatch_is_store_i(dispatch_is_store)
   ,.dispatch_ready_o(dispatch_ready), .dispatch_id_o(dispatch_id)
   ,.exe_v_i(exe_v), .exe_id_i(exe_id), .exe_addr_i(exe_addr)
   ,.exe_data_i(exe_data), .exe_byte_mask_i(exe_byte_mask)
   ,.cache_req_v_o(cache_req_v), .cache_req_is_store_o(cache_req_is_store)
   ,.cache_req_addr_o(cache_req_addr), .cache_req_data_o(cache_req_data)
   ,.cache_req_byte_mask_o(cache_req_byte_mask), .cache_req_id_o(cache_req_id)
   ,.cache_req_yumi_i(cache_req_yumi)
   ,.cache_resp_v_i(cache_resp_v), .cache_resp_id_i(cache_resp_id)
   ,.cache_resp_data_i(cache_resp_data)
   ,.fwd_check_v_i(fwd_check_v), .fwd_check_id_i(fwd_check_id)
   ,.fwd_check_addr_i(fwd_check_addr)
   ,.fwd_hit_o(fwd_hit), .fwd_data_o(fwd_data)
   ,.commit_v_o(commit_v), .commit_id_o(commit_id)
   ,.commit_is_store_o(commit_is_store), .commit_data_o(commit_data)
   ,.commit_addr_o(commit_addr), .commit_yumi_i(commit_yumi)
  );

  // -------------------------------------------------------
  // Helpers — all signals driven at negedge to avoid race
  // -------------------------------------------------------
  integer error_cnt = 0;

  task automatic clear_inputs();
    @(negedge clk);
    dispatch_v     = 0;
    exe_v          = 0;
    cache_resp_v   = 0;
    cache_req_yumi = 0;
    fwd_check_v    = 0;
    commit_yumi    = 0;
  endtask

  // Dispatch: drive at negedge, sample at next posedge
  task automatic do_dispatch(input logic is_store, output logic [entry_id_width_lp-1:0] id);
    // Wait until dispatch_ready
    while (!dispatch_ready) @(posedge clk);
    @(negedge clk);
    dispatch_v = 1;
    dispatch_is_store = is_store;
    @(posedge clk);  // fires here (alloc_yumi)
    id = dispatch_id;
    @(negedge clk);
    dispatch_v = 0;
  endtask

  // Execute: drive at negedge, hold for one cycle
  task automatic do_execute(
    input [entry_id_width_lp-1:0] id,
    input [addr_width_p-1:0] addr,
    input [data_width_p-1:0] data,
    input [data_mask_width_lp-1:0] mask
  );
    @(negedge clk);
    exe_v = 1;
    exe_id = id;
    exe_addr = addr;
    exe_data = data;
    exe_byte_mask = mask;
    @(posedge clk);  // captured
    @(negedge clk);
    exe_v = 0;
  endtask

  // Forwarding check: combinational, check at negedge (stable signals)
  task automatic do_fwd_check(
    input [entry_id_width_lp-1:0] load_id,
    input [addr_width_p-1:0] addr,
    output logic hit,
    output logic [data_width_p-1:0] data
  );
    @(negedge clk);
    fwd_check_v    = 1;
    fwd_check_id   = load_id;
    fwd_check_addr = addr;
    #1;  // let combinational logic settle
    hit  = fwd_hit;
    data = fwd_data;
    @(negedge clk);
    fwd_check_v = 0;
  endtask

  // Cache response: drive at negedge, hold one cycle
  task automatic do_cache_resp(
    input [entry_id_width_lp-1:0] id,
    input [data_width_p-1:0] data
  );
    @(negedge clk);
    cache_resp_v    = 1;
    cache_resp_id   = id;
    cache_resp_data = data;
    @(posedge clk);
    @(negedge clk);
    cache_resp_v = 0;
  endtask

  // Commit: wait for commit_v, then assert yumi for one cycle
  task automatic do_commit();
    // Wait until head is ready to commit
    while (!commit_v) @(posedge clk);
    @(negedge clk);
    commit_yumi = 1;
    @(posedge clk);
    @(negedge clk);
    commit_yumi = 0;
  endtask

  // Wait idle cycles
  task automatic wait_cycles(int n);
    repeat (n) @(posedge clk);
  endtask

  // -------------------------------------------------------
  // Test sequence
  // -------------------------------------------------------
  logic [entry_id_width_lp-1:0] id_a, id_b, id_c, id_d;
  logic fwd_hit_r;
  logic [data_width_p-1:0] fwd_data_r;

  initial begin
    dispatch_v = 0; exe_v = 0; cache_resp_v = 0;
    cache_req_yumi = 0; fwd_check_v = 0; commit_yumi = 0;
    exe_id = 0; exe_addr = 0; exe_data = 0; exe_byte_mask = 0;
    cache_resp_id = 0; cache_resp_data = 0;
    fwd_check_id = 0; fwd_check_addr = 0;

    @(negedge reset);
    wait_cycles(3);

    // ==========================================================
    // TEST 1: Basic store → load forwarding
    // ==========================================================
    $display("\n[TEST 1] Store then load, same address");

    do_dispatch(1'b1, id_a);
    $display("  STORE dispatched id=%0d", id_a);

    do_execute(id_a, 32'h1000, 32'hDEAD_BEEF, 4'hF);
    $display("  STORE executed addr=0x1000 data=0xDEADBEEF");

    do_dispatch(1'b0, id_b);
    $display("  LOAD  dispatched id=%0d", id_b);

    do_execute(id_b, 32'h1000, '0, '0);

    do_fwd_check(id_b, 32'h1000, fwd_hit_r, fwd_data_r);
    if (fwd_hit_r && fwd_data_r == 32'hDEAD_BEEF) begin
      $display("  [PASS] Forwarding hit data=0x%08h", fwd_data_r);
    end else begin
      $error("  [FAIL] hit=%0b data=0x%08h, expected hit=1 data=0xDEADBEEF", fwd_hit_r, fwd_data_r);
      error_cnt++;
    end

    // Commit store first (reorder_buf has store data from exe write)
    do_commit();
    // Provide load data via cache resp so reorder_buf marks it complete
    do_cache_resp(id_b, 32'hDEAD_BEEF);
    do_commit();
    wait_cycles(2);

    // ==========================================================
    // TEST 2: Two stores same addr, load picks youngest older
    // ==========================================================
    $display("\n[TEST 2] Two stores, load picks youngest older");

    do_dispatch(1'b1, id_a);
    do_dispatch(1'b1, id_b);
    do_dispatch(1'b0, id_c);
    $display("  S0=%0d S1=%0d L2=%0d", id_a, id_b, id_c);

    do_execute(id_a, 32'h2000, 32'h1111_1111, 4'hF);
    do_execute(id_b, 32'h2000, 32'h2222_2222, 4'hF);
    do_execute(id_c, 32'h2000, '0, '0);

    do_fwd_check(id_c, 32'h2000, fwd_hit_r, fwd_data_r);
    if (fwd_hit_r && fwd_data_r == 32'h2222_2222) begin
      $display("  [PASS] Load forwards from youngest older store: 0x%08h", fwd_data_r);
    end else begin
      $error("  [FAIL] hit=%0b data=0x%08h, expected 0x22222222", fwd_hit_r, fwd_data_r);
      error_cnt++;
    end

    // Commit all in order: S0, S1, L2
    do_commit();
    do_commit();
    do_cache_resp(id_c, 32'h2222_2222);
    do_commit();
    wait_cycles(2);

    // ==========================================================
    // TEST 3: No forwarding (different address)
    // ==========================================================
    $display("\n[TEST 3] Load with no matching store");

    do_dispatch(1'b1, id_a);
    do_dispatch(1'b0, id_b);

    do_execute(id_a, 32'h3000, 32'hAAAA_AAAA, 4'hF);
    do_execute(id_b, 32'h4000, '0, '0);

    do_fwd_check(id_b, 32'h4000, fwd_hit_r, fwd_data_r);
    if (!fwd_hit_r) begin
      $display("  [PASS] No forwarding hit");
    end else begin
      $error("  [FAIL] Unexpected hit data=0x%08h", fwd_data_r);
      error_cnt++;
    end

    do_commit();
    do_cache_resp(id_b, 32'hBBBB_BBBB);
    do_commit();
    wait_cycles(2);

    // ==========================================================
    // TEST 4: Fill and drain
    // ==========================================================
    $display("\n[TEST 4] Fill %0d entries, test back-pressure", lsq_entries_p);
    begin
      logic [entry_id_width_lp-1:0] ids [lsq_entries_p];

      for (int i = 0; i < lsq_entries_p; i++)
        do_dispatch(1'b1, ids[i]);

      @(posedge clk);
      if (!dispatch_ready) begin
        $display("  [PASS] Queue full, dispatch_ready=0");
      end else begin
        $error("  [FAIL] dispatch_ready should be 0");
        error_cnt++;
      end

      // Execute all (writes data into reorder_buf for stores)
      for (int i = 0; i < lsq_entries_p; i++)
        do_execute(ids[i], 32'h5000 + i*4, 32'hF000_0000 + i, 4'hF);

      // Commit all — each store needs commit_v to be asserted
      for (int i = 0; i < lsq_entries_p; i++)
        do_commit();

      @(posedge clk);
      if (dispatch_ready) begin
        $display("  [PASS] Queue drained");
      end else begin
        $error("  [FAIL] dispatch_ready should be 1 after drain");
        error_cnt++;
      end
    end
    wait_cycles(2);

    // ==========================================================
    // TEST 5: Interleaved S-L-S-L, correct age ordering
    // ==========================================================
    $display("\n[TEST 5] S0-L1-S2-L3 interleaved, age-ordered forwarding");

    do_dispatch(1'b1, id_a);  // S0
    do_dispatch(1'b0, id_b);  // L1
    do_dispatch(1'b1, id_c);  // S2
    do_dispatch(1'b0, id_d);  // L3
    $display("  S0=%0d L1=%0d S2=%0d L3=%0d", id_a, id_b, id_c, id_d);

    do_execute(id_a, 32'hA000, 32'h0000_0100, 4'hF);
    do_execute(id_b, 32'hA000, '0, '0);
    do_execute(id_c, 32'hA000, 32'h0000_0200, 4'hF);
    do_execute(id_d, 32'hA000, '0, '0);

    // L1 should see S0 only (S2 is younger than L1)
    do_fwd_check(id_b, 32'hA000, fwd_hit_r, fwd_data_r);
    if (fwd_hit_r && fwd_data_r == 32'h0000_0100) begin
      $display("  [PASS] L1 forwards from S0: 0x%08h", fwd_data_r);
    end else begin
      $error("  [FAIL] L1: hit=%0b data=0x%08h, expected S0=0x00000100", fwd_hit_r, fwd_data_r);
      error_cnt++;
    end

    // L3 should see S2 (youngest older store)
    do_fwd_check(id_d, 32'hA000, fwd_hit_r, fwd_data_r);
    if (fwd_hit_r && fwd_data_r == 32'h0000_0200) begin
      $display("  [PASS] L3 forwards from S2: 0x%08h", fwd_data_r);
    end else begin
      $error("  [FAIL] L3: hit=%0b data=0x%08h, expected S2=0x00000200", fwd_hit_r, fwd_data_r);
      error_cnt++;
    end

    // Commit in order: S0, L1, S2, L3
    do_commit();  // S0
    do_cache_resp(id_b, 32'h0000_0100);
    do_commit();  // L1
    do_commit();  // S2
    do_cache_resp(id_d, 32'h0000_0200);
    do_commit();  // L3
    wait_cycles(2);

    // ==========================================================
    // Summary
    // ==========================================================
    repeat (5) @(posedge clk);
    $display("\n========================================");
    if (error_cnt == 0)
      $display("[RESULT] ALL TESTS PASSED");
    else
      $display("[RESULT] FAILED: %0d errors", error_cnt);
    $display("========================================\n");
    $finish;
  end

  initial begin
    #200000;
    $display("[TIMEOUT]");
    $finish;
  end

endmodule
