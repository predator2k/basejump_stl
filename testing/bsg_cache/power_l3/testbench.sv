/**
 *  testbench.sv - L3 Cache Power Evaluation
 *
 *  L3: 4MB, 16-way, 64B cacheline, 4096 sets
 *
 *  Phases:
 *    1. WARMUP  - sequential stores to fill a portion of cache (compulsory misses)
 *    2. WRITE   - stores to same addresses (all hits)
 *    3. READ    - loads from same addresses (all hits)
 *    4. IDLE    - no operations, clock free-running
 */

`include "bsg_defines.sv"
`include "bsg_cache.svh"

module testbench();
  import bsg_cache_pkg::*;

  // -------------------------------------------------------
  // Parameters
  // -------------------------------------------------------
  localparam addr_width_p            = 40;
  localparam data_width_p            = 64;
  localparam block_size_in_words_p   = 8;    // 64B / 8B
  localparam sets_p                  = 4096;
  localparam ways_p                  = 16;
  localparam word_tracking_p         = 0;

  // Warmup 4096 lines (1 way per set, exercises all index decode paths)
  // Full cache = 65536 lines would be extremely slow
  localparam num_warmup_lines_lp     = 4096;
  localparam cacheline_bytes_lp      = block_size_in_words_p * (data_width_p / 8);  // 64

  // DMA model backing memory
  localparam dma_els_lp              = num_warmup_lines_lp * block_size_in_words_p;  // 32768

  // Phase durations
  localparam num_write_ops_lp        = 4096;
  localparam num_read_ops_lp         = 4096;
  localparam num_idle_cycles_lp      = 500;
  localparam phase_gap_cycles_lp     = 100;

  // -------------------------------------------------------
  // Clock / Reset
  // -------------------------------------------------------
  bit clk;
  bit reset;

  bsg_nonsynth_clock_gen #(
    .cycle_time_p(20)
  ) clk_gen (
    .o(clk)
  );

  bsg_nonsynth_reset_gen #(
    .reset_cycles_lo_p(0)
    ,.reset_cycles_hi_p(10)
  ) reset_gen (
    .clk_i(clk)
    ,.async_reset_o(reset)
  );

  integer cycle_cnt;
  always_ff @(posedge clk) begin
    if (reset)
      cycle_cnt <= 0;
    else
      cycle_cnt <= cycle_cnt + 1;
  end

  // -------------------------------------------------------
  // DUT signals
  // -------------------------------------------------------
  `declare_bsg_cache_pkt_s(addr_width_p, data_width_p);
  bsg_cache_pkt_s cache_pkt;

  logic v_li;
  logic yumi_lo;

  logic [data_width_p-1:0] data_lo;
  logic v_lo;
  logic yumi_li;

  `declare_bsg_cache_dma_pkt_s(addr_width_p, block_size_in_words_p);
  bsg_cache_dma_pkt_s dma_pkt;
  logic dma_pkt_v_lo;
  logic dma_pkt_yumi_li;

  logic [data_width_p-1:0] dma_data_li;
  logic dma_data_v_li;
  logic dma_data_ready_and_lo;

  logic [data_width_p-1:0] dma_data_lo;
  logic dma_data_v_lo;
  logic dma_data_yumi_li;

  // -------------------------------------------------------
  // DUT
  // -------------------------------------------------------
  bsg_cache #(
    .addr_width_p(addr_width_p)
    ,.data_width_p(data_width_p)
    ,.block_size_in_words_p(block_size_in_words_p)
    ,.sets_p(sets_p)
    ,.ways_p(ways_p)
    ,.word_tracking_p(word_tracking_p)
    ,.amo_support_p(amo_support_level_arithmetic_lp)
  ) DUT (
    .clk_i(clk)
    ,.reset_i(reset)

    ,.cache_pkt_i(cache_pkt)
    ,.v_i(v_li)
    ,.yumi_o(yumi_lo)

    ,.data_o(data_lo)
    ,.v_o(v_lo)
    ,.yumi_i(yumi_li)

    ,.dma_pkt_o(dma_pkt)
    ,.dma_pkt_v_o(dma_pkt_v_lo)
    ,.dma_pkt_yumi_i(dma_pkt_yumi_li)

    ,.dma_data_i(dma_data_li)
    ,.dma_data_v_i(dma_data_v_li)
    ,.dma_data_ready_and_o(dma_data_ready_and_lo)

    ,.dma_data_o(dma_data_lo)
    ,.dma_data_v_o(dma_data_v_lo)
    ,.dma_data_yumi_i(dma_data_yumi_li)

    ,.v_we_o()
  );

  // -------------------------------------------------------
  // Always accept output
  // -------------------------------------------------------
  assign yumi_li = v_lo;

  // -------------------------------------------------------
  // DMA model (zero delay for fast warmup)
  // -------------------------------------------------------
  bsg_nonsynth_dma_model #(
    .addr_width_p(addr_width_p)
    ,.data_width_p(data_width_p)
    ,.mask_width_p(block_size_in_words_p)
    ,.block_size_in_words_p(block_size_in_words_p)
    ,.els_p(dma_els_lp)
    ,.read_delay_p(0)
    ,.write_delay_p(0)
    ,.dma_req_delay_p(0)
    ,.dma_data_delay_p(0)
  ) dma (
    .clk_i(clk)
    ,.reset_i(reset)

    ,.dma_pkt_i(dma_pkt)
    ,.dma_pkt_v_i(dma_pkt_v_lo)
    ,.dma_pkt_yumi_o(dma_pkt_yumi_li)

    ,.dma_data_o(dma_data_li)
    ,.dma_data_v_o(dma_data_v_li)
    ,.dma_data_ready_i(dma_data_ready_and_lo)

    ,.dma_data_i(dma_data_lo)
    ,.dma_data_v_i(dma_data_v_lo)
    ,.dma_data_yumi_o(dma_data_yumi_li)
  );

  // -------------------------------------------------------
  // Stimulus
  // -------------------------------------------------------
  task automatic send_store(
    input logic [addr_width_p-1:0] addr,
    input logic [data_width_p-1:0] data
  );
    @(negedge clk);
    cache_pkt.opcode = SD;
    cache_pkt.addr   = addr;
    cache_pkt.data   = data;
    cache_pkt.mask   = '1;
    v_li = 1'b1;
    @(negedge clk);
    while (!yumi_lo) @(negedge clk);
  endtask

  task automatic send_load(
    input logic [addr_width_p-1:0] addr
  );
    @(negedge clk);
    cache_pkt.opcode = LD;
    cache_pkt.addr   = addr;
    cache_pkt.data   = '0;
    cache_pkt.mask   = '0;
    v_li = 1'b1;
    @(negedge clk);
    while (!yumi_lo) @(negedge clk);
  endtask

  initial begin
    v_li = 1'b0;
    cache_pkt = '0;

    @(negedge reset);
    repeat (10) @(posedge clk);

    // =====================================================
    // Phase 1: WARMUP
    // =====================================================
    $display("[PHASE_WARMUP_START] cycle=%0d  lines=%0d", cycle_cnt, num_warmup_lines_lp);
    for (integer i = 0; i < num_warmup_lines_lp; i++) begin
      send_store(i * cacheline_bytes_lp, 64'hDEAD_0000 + i);
    end
    v_li = 1'b0;
    repeat (phase_gap_cycles_lp) @(posedge clk);
    $display("[PHASE_WARMUP_END]   cycle=%0d", cycle_cnt);

    // =====================================================
    // Phase 2: WRITE (all hits)
    // =====================================================
    $display("[PHASE_WRITE_START]  cycle=%0d  ops=%0d", cycle_cnt, num_write_ops_lp);
    for (integer i = 0; i < num_write_ops_lp; i++) begin
      send_store((i % num_warmup_lines_lp) * cacheline_bytes_lp, 64'hBEEF_0000 + i);
    end
    v_li = 1'b0;
    repeat (phase_gap_cycles_lp) @(posedge clk);
    $display("[PHASE_WRITE_END]    cycle=%0d", cycle_cnt);

    // =====================================================
    // Phase 3: READ (all hits)
    // =====================================================
    $display("[PHASE_READ_START]   cycle=%0d  ops=%0d", cycle_cnt, num_read_ops_lp);
    for (integer i = 0; i < num_read_ops_lp; i++) begin
      send_load((i % num_warmup_lines_lp) * cacheline_bytes_lp);
    end
    v_li = 1'b0;
    repeat (phase_gap_cycles_lp) @(posedge clk);
    $display("[PHASE_READ_END]     cycle=%0d", cycle_cnt);

    // =====================================================
    // Phase 4: IDLE
    // =====================================================
    $display("[PHASE_IDLE_START]   cycle=%0d  cycles=%0d", cycle_cnt, num_idle_cycles_lp);
    repeat (num_idle_cycles_lp) @(posedge clk);
    $display("[PHASE_IDLE_END]     cycle=%0d", cycle_cnt);

    $display("[BSG_FINISH] L3 power testbench complete.");
    $finish;
  end

  // -------------------------------------------------------
  // FSDB dump
  // -------------------------------------------------------
`ifdef FSDB
  initial begin
    $fsdbDumpfile("bsg_cache_l3_pwr.fsdb");
    $fsdbDumpvars("+all");
  end
`endif

endmodule
