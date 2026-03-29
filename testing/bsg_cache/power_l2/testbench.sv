/**
 *  testbench.sv - L2 Cache Power Evaluation
 *
 *  L2: 512KB, 8-way, 64B cacheline, 1024 sets
 *
 *  Phases:
 *    0. TAGST       - invalidate all tag entries
 *    1. WARMUP      - sequential stores to fill portion of cache (compulsory misses)
 *    2. EVICT       - conflict stores to set 0, forcing evictions through dma_data_o
 *    3. RE_WARMUP   - re-store evicted lines to restore cache for measurement
 *    4. WRITE       - stores to same addresses (all hits)
 *    5. READ        - loads from same addresses (all hits)
 *    6. IDLE        - no operations, clock free-running
 *
 *  Fully synchronous stimulus (state machine) to avoid Verilog race conditions.
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
  localparam block_size_in_words_p   = 8;
  localparam sets_p                  = 1024;
  localparam ways_p                  = 8;
  localparam word_tracking_p         = 0;

  localparam num_lines_lp            = sets_p * ways_p;
  localparam num_warmup_lines_lp     = 2048;
  localparam cacheline_bytes_lp      = block_size_in_words_p * (data_width_p / 8);

  // Eviction parameters
  localparam warmup_ways_per_set_lp  = num_warmup_lines_lp / sets_p;
  localparam num_evict_ops_lp        = ways_p - warmup_ways_per_set_lp + 1;
  localparam evict_stride_lp         = sets_p * cacheline_bytes_lp;

  // DMA backing memory: cover warmup range + eviction addresses
  localparam dma_els_lp              = (num_lines_lp + 1) * block_size_in_words_p;

  localparam num_write_ops_lp        = 20480;
  localparam num_read_ops_lp         = 20480;
  localparam num_idle_cycles_lp      = 1000;
  localparam phase_gap_cycles_lp     = 100;

  // Address field widths for TAGST addressing
  localparam lg_data_mask_width_lp   = `BSG_SAFE_CLOG2(data_width_p>>3);
  localparam lg_block_size_lp        = `BSG_SAFE_CLOG2(block_size_in_words_p);
  localparam block_offset_width_lp   = lg_data_mask_width_lp + lg_block_size_lp;
  localparam lg_sets_lp              = `BSG_SAFE_CLOG2(sets_p);
  localparam way_offset_width_lp     = block_offset_width_lp + lg_sets_lp;
  localparam lg_ways_lp              = `BSG_SAFE_CLOG2(ways_p);

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

  assign yumi_li = v_lo;

  // -------------------------------------------------------
  // DMA model
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
  // Synchronous stimulus state machine
  // -------------------------------------------------------
  typedef enum logic [3:0] {
    RESET_WAIT,
    TAGST_INIT,
    TAGST_DRAIN,
    WARMUP,
    WARMUP_GAP,
    EVICT,
    EVICT_GAP,
    RE_WARMUP,
    RE_WARMUP_GAP,
    WRITE,
    WRITE_GAP,
    READ,
    READ_GAP,
    IDLE,
    DONE
  } phase_e;

  phase_e phase_r, phase_n;
  integer op_cnt_r, op_cnt_n;
  integer gap_cnt_r, gap_cnt_n;
  integer send_cnt_r, send_cnt_n;
  integer recv_cnt_r, recv_cnt_n;
  integer reset_wait_r, reset_wait_n;
  logic finish_r;

  // 64-bit LFSR for random write data (maximal-length, taps at 64,63,61,60)
  logic [63:0] lfsr_r;
  wire lfsr_feedback = lfsr_r[63] ^ lfsr_r[62] ^ lfsr_r[60] ^ lfsr_r[59];
  always_ff @(posedge clk) begin
    if (reset)
      lfsr_r <= 64'hA5A5_DEAD_BEEF_CAFE;
    else if (yumi_lo)
      lfsr_r <= {lfsr_r[62:0], lfsr_feedback};
  end

  wire [lg_ways_lp-1:0] tagst_way = op_cnt_r[lg_sets_lp+:lg_ways_lp];
  wire [lg_sets_lp-1:0]  tagst_set = op_cnt_r[0+:lg_sets_lp];
  wire [addr_width_p-1:0] tagst_addr = (addr_width_p'(tagst_way) << way_offset_width_lp)
                                      | (addr_width_p'(tagst_set) << block_offset_width_lp);

  always_comb begin
    phase_n = phase_r; op_cnt_n = op_cnt_r; gap_cnt_n = gap_cnt_r;
    send_cnt_n = send_cnt_r; recv_cnt_n = recv_cnt_r; reset_wait_n = reset_wait_r;
    v_li = 1'b0; cache_pkt = '0;

    case (phase_r)
      RESET_WAIT: begin
        if (reset_wait_r >= 10) begin phase_n = TAGST_INIT; op_cnt_n = 0; end
        else reset_wait_n = reset_wait_r + 1;
      end

      TAGST_INIT: begin
        cache_pkt.opcode = TAGST; cache_pkt.addr = tagst_addr;
        cache_pkt.data = '0; cache_pkt.mask = '0; v_li = 1'b1;
        if (yumi_lo) begin
          if (op_cnt_r == num_lines_lp - 1) begin phase_n = TAGST_DRAIN; gap_cnt_n = 0; end
          else op_cnt_n = op_cnt_r + 1;
        end
      end

      TAGST_DRAIN: begin
        if (gap_cnt_r >= 20) begin phase_n = WARMUP; op_cnt_n = 0; end
        else gap_cnt_n = gap_cnt_r + 1;
      end

      WARMUP: begin
        cache_pkt.opcode = SD;
        cache_pkt.addr = addr_width_p'(op_cnt_r * cacheline_bytes_lp);
        cache_pkt.data = lfsr_r; cache_pkt.mask = '1; v_li = 1'b1;
        if (yumi_lo) begin
          send_cnt_n = send_cnt_r + 1;
          if (op_cnt_r == num_warmup_lines_lp - 1) begin phase_n = WARMUP_GAP; gap_cnt_n = 0; end
          else op_cnt_n = op_cnt_r + 1;
        end
      end

      WARMUP_GAP: begin
        if (gap_cnt_r >= phase_gap_cycles_lp - 1) begin phase_n = EVICT; op_cnt_n = 0; end
        else gap_cnt_n = gap_cnt_r + 1;
      end

      EVICT: begin
        cache_pkt.opcode = SD;
        cache_pkt.addr = addr_width_p'((warmup_ways_per_set_lp + op_cnt_r) * evict_stride_lp);
        cache_pkt.data = lfsr_r; cache_pkt.mask = '1; v_li = 1'b1;
        if (yumi_lo) begin
          if (op_cnt_r == num_evict_ops_lp - 1) begin phase_n = EVICT_GAP; gap_cnt_n = 0; end
          else op_cnt_n = op_cnt_r + 1;
        end
      end

      EVICT_GAP: begin
        if (gap_cnt_r >= phase_gap_cycles_lp - 1) begin phase_n = RE_WARMUP; op_cnt_n = 0; end
        else gap_cnt_n = gap_cnt_r + 1;
      end

      RE_WARMUP: begin
        cache_pkt.opcode = SD;
        cache_pkt.addr = addr_width_p'(op_cnt_r * evict_stride_lp);
        cache_pkt.data = lfsr_r * sets_p; cache_pkt.mask = '1; v_li = 1'b1;
        if (yumi_lo) begin
          if (op_cnt_r == num_evict_ops_lp - 1) begin phase_n = RE_WARMUP_GAP; gap_cnt_n = 0; end
          else op_cnt_n = op_cnt_r + 1;
        end
      end

      RE_WARMUP_GAP: begin
        if (gap_cnt_r >= phase_gap_cycles_lp - 1) begin phase_n = WRITE; op_cnt_n = 0; end
        else gap_cnt_n = gap_cnt_r + 1;
      end

      WRITE: begin
        cache_pkt.opcode = SD;
        cache_pkt.addr = addr_width_p'((op_cnt_r % num_warmup_lines_lp) * cacheline_bytes_lp);
        cache_pkt.data = lfsr_r; cache_pkt.mask = '1; v_li = 1'b1;
        if (yumi_lo) begin
          send_cnt_n = send_cnt_r + 1;
          if (op_cnt_r == num_write_ops_lp - 1) begin phase_n = WRITE_GAP; gap_cnt_n = 0; end
          else op_cnt_n = op_cnt_r + 1;
        end
      end

      WRITE_GAP: begin
        if (gap_cnt_r >= phase_gap_cycles_lp - 1) begin phase_n = READ; op_cnt_n = 0; end
        else gap_cnt_n = gap_cnt_r + 1;
      end

      READ: begin
        cache_pkt.opcode = LD;
        cache_pkt.addr = addr_width_p'((op_cnt_r % num_warmup_lines_lp) * cacheline_bytes_lp);
        cache_pkt.data = '0; cache_pkt.mask = '0; v_li = 1'b1;
        if (yumi_lo) begin
          send_cnt_n = send_cnt_r + 1;
          if (op_cnt_r == num_read_ops_lp - 1) begin phase_n = READ_GAP; gap_cnt_n = 0; end
          else op_cnt_n = op_cnt_r + 1;
        end
      end

      READ_GAP: begin
        if (gap_cnt_r >= phase_gap_cycles_lp - 1) begin phase_n = IDLE; gap_cnt_n = 0; end
        else gap_cnt_n = gap_cnt_r + 1;
      end

      IDLE: begin
        if (gap_cnt_r >= num_idle_cycles_lp - 1) phase_n = DONE;
        else gap_cnt_n = gap_cnt_r + 1;
      end

      DONE: ;
      default: phase_n = RESET_WAIT;
    endcase

    if (v_lo & yumi_li) recv_cnt_n = recv_cnt_r + 1;
  end

  // -------------------------------------------------------
  // High-level operation type (for power annotation)
  // -------------------------------------------------------
  typedef enum logic [2:0] {
    OP_INIT,
    OP_WARMUP,
    OP_WRITE,
    OP_READ,
    OP_IDLE
  } op_type_e;

  op_type_e op_type;

  always_comb begin
    case (phase_r)
      RESET_WAIT, TAGST_INIT, TAGST_DRAIN,
      EVICT, EVICT_GAP, RE_WARMUP, RE_WARMUP_GAP: op_type = OP_INIT;
      WARMUP, WARMUP_GAP:                          op_type = OP_WARMUP;
      WRITE, WRITE_GAP:                            op_type = OP_WRITE;
      READ, READ_GAP:                              op_type = OP_READ;
      IDLE, DONE:                                  op_type = OP_IDLE;
      default:                                     op_type = OP_INIT;
    endcase
  end

  always_ff @(posedge clk) begin
    if (reset) begin
      phase_r <= RESET_WAIT; op_cnt_r <= 0; gap_cnt_r <= 0;
      send_cnt_r <= 0; recv_cnt_r <= 0; reset_wait_r <= 0; finish_r <= 1'b0;
    end else begin
      phase_r <= phase_n; op_cnt_r <= op_cnt_n; gap_cnt_r <= gap_cnt_n;
      send_cnt_r <= send_cnt_n; recv_cnt_r <= recv_cnt_n; reset_wait_r <= reset_wait_n;
      if (phase_n == DONE && phase_r != DONE) finish_r <= 1'b1;
    end
  end

  // -------------------------------------------------------
  // Phase transition display
  // -------------------------------------------------------
  always_ff @(posedge clk) begin
    if (!reset) begin
      if (phase_r == TAGST_DRAIN && phase_n == WARMUP)
        $display("[PHASE_WARMUP_START] cycle=%0d  lines=%0d", cycle_cnt, num_warmup_lines_lp);
      if (phase_r == WARMUP && phase_n == WARMUP_GAP)
        $display("[PHASE_WARMUP_END]   cycle=%0d  sent=%0d recv=%0d", cycle_cnt, send_cnt_n, recv_cnt_n);
      if (phase_r == WARMUP_GAP && phase_n == EVICT)
        $display("[PHASE_EVICT_START]  cycle=%0d  ops=%0d", cycle_cnt, num_evict_ops_lp);
      if (phase_r == EVICT && phase_n == EVICT_GAP)
        $display("[PHASE_EVICT_END]    cycle=%0d", cycle_cnt);
      if (phase_r == RE_WARMUP_GAP && phase_n == WRITE)
        $display("[PHASE_WRITE_START]  cycle=%0d  ops=%0d", cycle_cnt, num_write_ops_lp);
      if (phase_r == WRITE && phase_n == WRITE_GAP)
        $display("[PHASE_WRITE_END]    cycle=%0d  sent=%0d recv=%0d", cycle_cnt, send_cnt_n, recv_cnt_n);
      if (phase_r == WRITE_GAP && phase_n == READ)
        $display("[PHASE_READ_START]   cycle=%0d  ops=%0d", cycle_cnt, num_read_ops_lp);
      if (phase_r == READ && phase_n == READ_GAP)
        $display("[PHASE_READ_END]     cycle=%0d  sent=%0d recv=%0d", cycle_cnt, send_cnt_n, recv_cnt_n);
      if (phase_r == READ_GAP && phase_n == IDLE)
        $display("[PHASE_IDLE_START]   cycle=%0d  cycles=%0d", cycle_cnt, num_idle_cycles_lp);
      if (phase_r == IDLE && phase_n == DONE)
        $display("[PHASE_IDLE_END]     cycle=%0d", cycle_cnt);
    end
  end

  always_ff @(posedge clk) begin
    if (finish_r) begin
      $display("[BSG_FINISH] L2 power testbench complete. sent=%0d recv=%0d", send_cnt_r, recv_cnt_r);
      $finish;
    end
  end

  // -------------------------------------------------------
  // Read data monitor
  // -------------------------------------------------------
  integer phase_resp_cnt_r;
  always_ff @(posedge clk) begin
    if (reset) phase_resp_cnt_r <= 0;
    else if (phase_r != phase_n) phase_resp_cnt_r <= 0;
    else if (v_lo && yumi_li) phase_resp_cnt_r <= phase_resp_cnt_r + 1;
  end

  always_ff @(posedge clk) begin
    if (!reset && v_lo && yumi_li) begin
      if (phase_resp_cnt_r < 3 && (phase_r == WARMUP || phase_r == WRITE || phase_r == READ || phase_r == EVICT))
        $display("  [RESP] #%0d data=0x%016h cycle=%0d phase=%s", phase_resp_cnt_r, data_lo, cycle_cnt, phase_r.name());
    end
  end

  // -------------------------------------------------------
  // Data correctness check (shadow memory)
  // -------------------------------------------------------
  logic [data_width_p-1:0] shadow_mem [num_warmup_lines_lp-1:0];
  integer error_cnt;

  // WRITE phase: record LFSR value written to each address
  always_ff @(posedge clk) begin
    if (phase_r == WRITE && yumi_lo)
      shadow_mem[op_cnt_r % num_warmup_lines_lp] <= lfsr_r;
  end

  // READ phase: compare read data against shadow memory
  integer rd_check_idx_r;
  always_ff @(posedge clk) begin
    if (reset)
      rd_check_idx_r <= 0;
    else if (phase_r == WRITE_GAP && phase_n == READ)
      rd_check_idx_r <= 0;
    else if (phase_r == READ && v_lo && yumi_li)
      rd_check_idx_r <= rd_check_idx_r + 1;
  end

  always_ff @(posedge clk) begin
    if (reset) error_cnt <= 0;
    else if (phase_r == READ && v_lo && yumi_li) begin
      if (data_lo !== shadow_mem[rd_check_idx_r % num_warmup_lines_lp]) begin
        $error("[CHECK FAIL] READ #%0d: got=0x%016h exp=0x%016h cycle=%0d",
          rd_check_idx_r, data_lo, shadow_mem[rd_check_idx_r % num_warmup_lines_lp], cycle_cnt);
        error_cnt <= error_cnt + 1;
      end
    end
  end

  always_ff @(posedge clk) begin
    if (phase_r == READ && phase_n == READ_GAP)
      $display("[CHECK] READ phase done: %0d errors out of %0d reads", error_cnt, num_read_ops_lp);
  end

`ifdef FSDB
  initial begin
    $fsdbDumpfile("bsg_cache_l2_pwr.fsdb");
    $fsdbDumpvars("+all");
  end
`endif

endmodule
