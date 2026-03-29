/**
 *  testbench.sv - L2 Cache+SPM Power Evaluation
 *
 *  Instantiates bsg_cache_l2_spm (L2 top with scratchpad).
 *
 *  Phases:
 *    0. TAGST       - invalidate all tag entries
 *    1. WARMUP      - sequential stores to fill cache (compulsory misses)
 *    2. EVICT       - conflict stores to set 0, forcing evictions through dma_data_o
 *    3. RE_WARMUP   - re-store evicted lines to restore cache
 *    4. WRITE       - stores to cached addresses (all hits)
 *    5. READ        - loads from cached addresses (all hits)
 *    6. SPM_WRITE   - direct SRAM writes to scratchpad bank 0
 *    7. SPM_READ    - direct SRAM reads from scratchpad bank 0
 *    8. IDLE        - no operations, clock free-running
 */

`include "bsg_defines.sv"
`include "bsg_cache.svh"

module testbench();
  import bsg_cache_pkg::*;

  // -------------------------------------------------------
  // Parameters  (must match bsg_cache_l2_spm defaults)
  // -------------------------------------------------------
  localparam addr_width_p            = 40;
  localparam data_width_p            = 64;
  localparam block_size_in_words_p   = 8;
  localparam sets_p                  = 1024;
  localparam ways_p                  = 8;
  localparam word_tracking_p         = 0;

  // SPM configuration: way 0 switches to scratchpad during SPM phases
  localparam sp_way_lp               = 0;

  localparam num_lines_lp            = sets_p * ways_p;
  localparam num_warmup_lines_lp     = sets_p * (ways_p - 1);
  localparam cacheline_bytes_lp      = block_size_in_words_p * (data_width_p / 8);

  localparam warmup_ways_per_set_lp  = num_warmup_lines_lp / sets_p;
  localparam num_evict_ops_lp        = 1;
  localparam evict_stride_lp         = sets_p * cacheline_bytes_lp;

  localparam dma_els_lp              = (num_lines_lp + 1) * block_size_in_words_p;

  localparam num_write_ops_lp        = 2048;
  localparam num_read_ops_lp         = 2048;

  // SPM bank geometry
  localparam sp_bank_els_lp          = sets_p * block_size_in_words_p;
  localparam lg_sp_bank_els_lp       = `BSG_SAFE_CLOG2(sp_bank_els_lp);
  localparam sp_mask_width_lp        = (data_width_p >> 3);
  localparam num_spm_ops_lp          = 4096;

  localparam num_idle_cycles_lp      = 500;
  localparam phase_gap_cycles_lp     = 100;

  // TAGST addressing helpers
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
    if (reset) cycle_cnt <= 0;
    else       cycle_cnt <= cycle_cnt + 1;
  end

  // -------------------------------------------------------
  // DUT signals
  // -------------------------------------------------------
  `declare_bsg_cache_pkt_s(addr_width_p, data_width_p);
  bsg_cache_pkt_s cache_pkt;

  logic v_li, yumi_lo;
  logic [data_width_p-1:0] data_lo;
  logic v_lo, yumi_li;

  `declare_bsg_cache_dma_pkt_s(addr_width_p, block_size_in_words_p);
  bsg_cache_dma_pkt_s dma_pkt;
  logic dma_pkt_v_lo, dma_pkt_yumi_li;

  logic [data_width_p-1:0] dma_data_li;
  logic dma_data_v_li, dma_data_ready_and_lo;

  logic [data_width_p-1:0] dma_data_lo;
  logic dma_data_v_lo, dma_data_yumi_li;

  // Scratchpad signals
  logic [ways_p-1:0]                           sp_en;
  logic [ways_p-1:0]                           sp_v;
  logic [ways_p-1:0]                           sp_w;
  logic [ways_p-1:0][lg_sp_bank_els_lp-1:0]   sp_addr;
  logic [ways_p-1:0][data_width_p-1:0]         sp_wdata;
  logic [ways_p-1:0][sp_mask_width_lp-1:0]     sp_w_mask;
  logic [ways_p-1:0][data_width_p-1:0]         sp_rdata;

  // -------------------------------------------------------
  // DUT: bsg_cache_l2_spm
  // -------------------------------------------------------
  bsg_cache_l2_spm #(
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

    ,.sp_en_i(sp_en)
    ,.sp_v_i(sp_v)
    ,.sp_w_i(sp_w)
    ,.sp_addr_i(sp_addr)
    ,.sp_data_i(sp_wdata)
    ,.sp_w_mask_i(sp_w_mask)
    ,.sp_data_o(sp_rdata)
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
  typedef enum logic [4:0] {
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
    SPM_WRITE,
    SPM_WRITE_GAP,
    SPM_READ,
    SPM_READ_GAP,
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

  // 64-bit LFSR for random data
  logic [63:0] lfsr_r;
  wire lfsr_feedback = lfsr_r[63] ^ lfsr_r[62] ^ lfsr_r[60] ^ lfsr_r[59];
  wire lfsr_advance  = yumi_lo | (phase_r == SPM_WRITE) | (phase_r == SPM_READ);

  always_ff @(posedge clk) begin
    if (reset)            lfsr_r <= 64'hA5A5_DEAD_BEEF_CAFE;
    else if (lfsr_advance) lfsr_r <= {lfsr_r[62:0], lfsr_feedback};
  end

  // TAGST addressing
  wire [lg_ways_lp-1:0]   tagst_way  = op_cnt_r[lg_sets_lp+:lg_ways_lp];
  wire [lg_sets_lp-1:0]   tagst_set  = op_cnt_r[0+:lg_sets_lp];
  wire [addr_width_p-1:0] tagst_addr = (addr_width_p'(tagst_way) << way_offset_width_lp)
                                      | (addr_width_p'(tagst_set) << block_offset_width_lp);

  // Warmup addresses: skip way-0 region, start from way 1
  wire [addr_width_p-1:0] warmup_addr = addr_width_p'((1 * sets_p + op_cnt_r) * cacheline_bytes_lp);

  // SPM read capture (1-cycle SRAM latency)
  logic spm_rd_valid_r;
  always_ff @(posedge clk) begin
    if (reset) spm_rd_valid_r <= 1'b0;
    else       spm_rd_valid_r <= (phase_r == SPM_READ);
  end

  // -------------------------------------------------------
  // Combinational next-state + output
  // -------------------------------------------------------
  always_comb begin
    phase_n = phase_r; op_cnt_n = op_cnt_r; gap_cnt_n = gap_cnt_r;
    send_cnt_n = send_cnt_r; recv_cnt_n = recv_cnt_r; reset_wait_n = reset_wait_r;
    v_li = 1'b0; cache_pkt = '0;
    sp_en = '0; sp_v = '0; sp_w = '0; sp_addr = '0; sp_wdata = '0; sp_w_mask = '0;

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
        cache_pkt.addr = warmup_addr;
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
        cache_pkt.addr = addr_width_p'((warmup_ways_per_set_lp + 1 + op_cnt_r) * evict_stride_lp);
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
        cache_pkt.data = lfsr_r; cache_pkt.mask = '1; v_li = 1'b1;
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
        cache_pkt.addr = addr_width_p'(((op_cnt_r % num_warmup_lines_lp) + sets_p) * cacheline_bytes_lp);
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
        cache_pkt.addr = addr_width_p'(((op_cnt_r % num_warmup_lines_lp) + sets_p) * cacheline_bytes_lp);
        cache_pkt.data = '0; cache_pkt.mask = '0; v_li = 1'b1;
        if (yumi_lo) begin
          send_cnt_n = send_cnt_r + 1;
          if (op_cnt_r == num_read_ops_lp - 1) begin phase_n = READ_GAP; gap_cnt_n = 0; end
          else op_cnt_n = op_cnt_r + 1;
        end
      end

      READ_GAP: begin
        if (gap_cnt_r >= phase_gap_cycles_lp - 1) begin phase_n = SPM_WRITE; op_cnt_n = 0; end
        else gap_cnt_n = gap_cnt_r + 1;
      end

      // ----- SPM WRITE -----
      SPM_WRITE: begin
        sp_en[sp_way_lp]     = 1'b1;
        sp_v[sp_way_lp]      = 1'b1;
        sp_w[sp_way_lp]      = 1'b1;
        sp_addr[sp_way_lp]   = op_cnt_r[0+:lg_sp_bank_els_lp];
        sp_wdata[sp_way_lp]  = lfsr_r;
        sp_w_mask[sp_way_lp] = '1;
        if (op_cnt_r == num_spm_ops_lp - 1) begin phase_n = SPM_WRITE_GAP; gap_cnt_n = 0; end
        else op_cnt_n = op_cnt_r + 1;
      end

      SPM_WRITE_GAP: begin
        sp_en[sp_way_lp] = 1'b1;
        if (gap_cnt_r >= phase_gap_cycles_lp - 1) begin phase_n = SPM_READ; op_cnt_n = 0; end
        else gap_cnt_n = gap_cnt_r + 1;
      end

      // ----- SPM READ -----
      SPM_READ: begin
        sp_en[sp_way_lp]   = 1'b1;
        sp_v[sp_way_lp]    = 1'b1;
        sp_w[sp_way_lp]    = 1'b0;
        sp_addr[sp_way_lp] = op_cnt_r[0+:lg_sp_bank_els_lp];
        if (op_cnt_r == num_spm_ops_lp - 1) begin phase_n = SPM_READ_GAP; gap_cnt_n = 0; end
        else op_cnt_n = op_cnt_r + 1;
      end

      SPM_READ_GAP: begin
        sp_en[sp_way_lp] = 1'b1;
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
  // Operation type enum (for power annotation)
  // -------------------------------------------------------
  typedef enum logic [2:0] {
    OP_INIT, OP_WARMUP, OP_WRITE, OP_READ, OP_SPM_WRITE, OP_SPM_READ, OP_IDLE
  } op_type_e;

  op_type_e op_type;

  always_comb begin
    case (phase_r)
      RESET_WAIT, TAGST_INIT, TAGST_DRAIN,
      EVICT, EVICT_GAP, RE_WARMUP, RE_WARMUP_GAP: op_type = OP_INIT;
      WARMUP, WARMUP_GAP:                          op_type = OP_WARMUP;
      WRITE, WRITE_GAP:                            op_type = OP_WRITE;
      READ, READ_GAP:                              op_type = OP_READ;
      SPM_WRITE, SPM_WRITE_GAP:                    op_type = OP_SPM_WRITE;
      SPM_READ, SPM_READ_GAP:                      op_type = OP_SPM_READ;
      IDLE, DONE:                                  op_type = OP_IDLE;
      default:                                     op_type = OP_INIT;
    endcase
  end

  // -------------------------------------------------------
  // Sequential update
  // -------------------------------------------------------
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
      if (phase_r == TAGST_DRAIN  && phase_n == WARMUP)
        $display("[PHASE_WARMUP_START] cycle=%0d  lines=%0d", cycle_cnt, num_warmup_lines_lp);
      if (phase_r == WARMUP       && phase_n == WARMUP_GAP)
        $display("[PHASE_WARMUP_END]   cycle=%0d  sent=%0d recv=%0d", cycle_cnt, send_cnt_n, recv_cnt_n);
      if (phase_r == WARMUP_GAP   && phase_n == EVICT)
        $display("[PHASE_EVICT_START]  cycle=%0d  ops=%0d", cycle_cnt, num_evict_ops_lp);
      if (phase_r == EVICT        && phase_n == EVICT_GAP)
        $display("[PHASE_EVICT_END]    cycle=%0d", cycle_cnt);
      if (phase_r == RE_WARMUP_GAP && phase_n == WRITE)
        $display("[PHASE_WRITE_START]  cycle=%0d  ops=%0d", cycle_cnt, num_write_ops_lp);
      if (phase_r == WRITE        && phase_n == WRITE_GAP)
        $display("[PHASE_WRITE_END]    cycle=%0d  sent=%0d recv=%0d", cycle_cnt, send_cnt_n, recv_cnt_n);
      if (phase_r == WRITE_GAP    && phase_n == READ)
        $display("[PHASE_READ_START]   cycle=%0d  ops=%0d", cycle_cnt, num_read_ops_lp);
      if (phase_r == READ         && phase_n == READ_GAP)
        $display("[PHASE_READ_END]     cycle=%0d  sent=%0d recv=%0d", cycle_cnt, send_cnt_n, recv_cnt_n);
      if (phase_r == READ_GAP     && phase_n == SPM_WRITE)
        $display("[PHASE_SPM_WR_START] cycle=%0d  ops=%0d  bank=%0d", cycle_cnt, num_spm_ops_lp, sp_way_lp);
      if (phase_r == SPM_WRITE    && phase_n == SPM_WRITE_GAP)
        $display("[PHASE_SPM_WR_END]   cycle=%0d", cycle_cnt);
      if (phase_r == SPM_WRITE_GAP && phase_n == SPM_READ)
        $display("[PHASE_SPM_RD_START] cycle=%0d  ops=%0d  bank=%0d", cycle_cnt, num_spm_ops_lp, sp_way_lp);
      if (phase_r == SPM_READ     && phase_n == SPM_READ_GAP)
        $display("[PHASE_SPM_RD_END]   cycle=%0d", cycle_cnt);
      if (phase_r == SPM_READ_GAP && phase_n == IDLE)
        $display("[PHASE_IDLE_START]   cycle=%0d  cycles=%0d", cycle_cnt, num_idle_cycles_lp);
      if (phase_r == IDLE         && phase_n == DONE)
        $display("[PHASE_IDLE_END]     cycle=%0d", cycle_cnt);
    end
  end

  always_ff @(posedge clk) begin
    if (finish_r) begin
      $display("[BSG_FINISH] L2 SP testbench complete. sent=%0d recv=%0d", send_cnt_r, recv_cnt_r);
      $finish;
    end
  end

  // -------------------------------------------------------
  // Cache read monitor
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
  // SPM read monitor
  // -------------------------------------------------------
  integer spm_rd_cnt_r;
  always_ff @(posedge clk) begin
    if (reset) spm_rd_cnt_r <= 0;
    else if (phase_r == SPM_WRITE_GAP && phase_n == SPM_READ) spm_rd_cnt_r <= 0;
    else if (spm_rd_valid_r) spm_rd_cnt_r <= spm_rd_cnt_r + 1;
  end

  always_ff @(posedge clk) begin
    if (!reset && spm_rd_valid_r) begin
      if (spm_rd_cnt_r < 3)
        $display("  [SPM_RD] #%0d data=0x%016h cycle=%0d", spm_rd_cnt_r, sp_rdata[sp_way_lp], cycle_cnt);
    end
  end

`ifdef FSDB
  initial begin
    $fsdbDumpfile("bsg_cache_l2_sp.fsdb");
    $fsdbDumpvars("+all");
  end
`endif

endmodule
