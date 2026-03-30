/**
 *  bsg_lsq_split.sv — Split Load Queue + Store Queue
 *
 *  Separate LQ and SQ with independent allocation, like Cortex-A710.
 *  - Store Queue (SQ): in-order alloc, holds addr+data until commit.
 *    On commit, store is sent to cache. Address CAM for forwarding.
 *  - Load Queue (LQ): in-order alloc, issues to cache, receives response.
 *    Checks SQ CAM for store-to-load forwarding before cache access.
 *  - Both queues retire in-order independently (ROB commits loads and stores
 *    in program order by driving the respective commit ports).
 *
 *  BSG STL components used:
 *    - bsg_fifo_reorder (×2)     : SQ data buffer + LQ data buffer
 *    - bsg_cam_1r1w_tag_array    : SQ address CAM for forwarding
 *    - bsg_priority_encode       : age-ordered store selection
 *    - bsg_mux_one_hot           : forwarded data mux
 */

`include "bsg_defines.sv"

module bsg_lsq_split
  #(parameter `BSG_INV_PARAM(sq_entries_p)    // Store Queue depth
   ,parameter `BSG_INV_PARAM(lq_entries_p)    // Load Queue depth
   ,parameter `BSG_INV_PARAM(addr_width_p)
   ,parameter `BSG_INV_PARAM(data_width_p)
   ,localparam sq_id_width_lp  = `BSG_SAFE_CLOG2(sq_entries_p)
   ,localparam lq_id_width_lp  = `BSG_SAFE_CLOG2(lq_entries_p)
   ,localparam data_mask_width_lp = (data_width_p >> 3)
  )
  (
    input                                clk_i
   ,input                                reset_i

   // -------------------------------------------------------
   // Store dispatch (in-order)
   // -------------------------------------------------------
   ,input                                sq_dispatch_v_i
   ,output                               sq_dispatch_ready_o
   ,output [sq_id_width_lp-1:0]          sq_dispatch_id_o

   // -------------------------------------------------------
   // Load dispatch (in-order)
   // -------------------------------------------------------
   ,input                                lq_dispatch_v_i
   ,output                               lq_dispatch_ready_o
   ,output [lq_id_width_lp-1:0]          lq_dispatch_id_o

   // -------------------------------------------------------
   // Store execute: write address + data into SQ
   // -------------------------------------------------------
   ,input                                sq_exe_v_i
   ,input [sq_id_width_lp-1:0]           sq_exe_id_i
   ,input [addr_width_p-1:0]             sq_exe_addr_i
   ,input [data_width_p-1:0]             sq_exe_data_i
   ,input [data_mask_width_lp-1:0]       sq_exe_byte_mask_i

   // -------------------------------------------------------
   // Load execute: write address into LQ, triggers forwarding check
   // -------------------------------------------------------
   ,input                                lq_exe_v_i
   ,input [lq_id_width_lp-1:0]           lq_exe_id_i
   ,input [addr_width_p-1:0]             lq_exe_addr_i

   // -------------------------------------------------------
   // Store-to-load forwarding result (available 1 cycle after lq_exe)
   // -------------------------------------------------------
   ,output logic                         fwd_v_o
   ,output logic [lq_id_width_lp-1:0]    fwd_lq_id_o
   ,output logic [data_width_p-1:0]      fwd_data_o

   // -------------------------------------------------------
   // Load cache request (issued by LQ for non-forwarded loads)
   // -------------------------------------------------------
   ,output                               lq_cache_req_v_o
   ,output [addr_width_p-1:0]            lq_cache_req_addr_o
   ,output [lq_id_width_lp-1:0]          lq_cache_req_id_o
   ,input                                lq_cache_req_yumi_i

   // -------------------------------------------------------
   // Load cache response
   // -------------------------------------------------------
   ,input                                lq_cache_resp_v_i
   ,input [lq_id_width_lp-1:0]           lq_cache_resp_id_i
   ,input [data_width_p-1:0]             lq_cache_resp_data_i

   // -------------------------------------------------------
   // Store commit (in-order, from ROB → writes to cache)
   // -------------------------------------------------------
   ,output                               sq_commit_v_o
   ,output [sq_id_width_lp-1:0]          sq_commit_id_o
   ,output [addr_width_p-1:0]            sq_commit_addr_o
   ,output [data_width_p-1:0]            sq_commit_data_o
   ,output [data_mask_width_lp-1:0]      sq_commit_byte_mask_o
   ,input                                sq_commit_yumi_i

   // -------------------------------------------------------
   // Load commit (in-order, from ROB)
   // -------------------------------------------------------
   ,output                               lq_commit_v_o
   ,output [lq_id_width_lp-1:0]          lq_commit_id_o
   ,output [data_width_p-1:0]            lq_commit_data_o
   ,input                                lq_commit_yumi_i
  );

  // ================================================================
  //  STORE QUEUE
  // ================================================================

  wire sq_dispatch_fire = sq_dispatch_v_i & sq_dispatch_ready_o;
  wire sq_commit_fire   = sq_commit_yumi_i;

  // --- SQ metadata registers ---
  logic [sq_entries_p-1:0]                           sq_addr_valid_r;
  logic [sq_entries_p-1:0]                           sq_data_valid_r;
  logic [sq_entries_p-1:0][addr_width_p-1:0]         sq_addr_r;
  logic [sq_entries_p-1:0][data_width_p-1:0]         sq_data_r;
  logic [sq_entries_p-1:0][data_mask_width_lp-1:0]   sq_byte_mask_r;

  always_ff @(posedge clk_i) begin
    if (reset_i) begin
      sq_addr_valid_r <= '0;
      sq_data_valid_r <= '0;
    end else begin
      if (sq_dispatch_fire) begin
        sq_addr_valid_r[sq_dispatch_id_o] <= 1'b0;
        sq_data_valid_r[sq_dispatch_id_o] <= 1'b0;
      end
      if (sq_exe_v_i) begin
        sq_addr_valid_r[sq_exe_id_i] <= 1'b1;
        sq_data_valid_r[sq_exe_id_i] <= 1'b1;
        sq_addr_r[sq_exe_id_i]       <= sq_exe_addr_i;
        sq_data_r[sq_exe_id_i]       <= sq_exe_data_i;
        sq_byte_mask_r[sq_exe_id_i]  <= sq_exe_byte_mask_i;
      end
      if (sq_commit_fire) begin
        sq_addr_valid_r[sq_commit_id_o] <= 1'b0;
        sq_data_valid_r[sq_commit_id_o] <= 1'b0;
      end
    end
  end

  // --- SQ reorder buffer (for in-order commit) ---
  bsg_fifo_reorder #(
    .width_p(data_width_p)
   ,.els_p(sq_entries_p)
  ) sq_reorder (
    .clk_i(clk_i), .reset_i(reset_i)
   ,.fifo_alloc_v_o(sq_dispatch_ready_o)
   ,.fifo_alloc_id_o(sq_dispatch_id_o)
   ,.fifo_alloc_yumi_i(sq_dispatch_fire)
   ,.write_v_i(sq_exe_v_i)
   ,.write_id_i(sq_exe_id_i)
   ,.write_data_i(sq_exe_data_i)
   ,.fifo_deq_v_o(sq_commit_v_o)
   ,.fifo_deq_data_o(sq_commit_data_o)
   ,.fifo_deq_id_o(sq_commit_id_o)
   ,.fifo_deq_yumi_i(sq_commit_fire)
   ,.empty_o()
  );

  assign sq_commit_addr_o      = sq_addr_r[sq_commit_id_o];
  assign sq_commit_byte_mask_o = sq_byte_mask_r[sq_commit_id_o];

  // ================================================================
  //  STORE-TO-LOAD FORWARDING (SQ → LQ)
  // ================================================================

  // Forwarding check signals (registered from lq_exe)
  logic                          fwd_check_v;
  logic [addr_width_p-1:0]       fwd_check_addr;
  logic [lq_id_width_lp-1:0]    fwd_check_lq_id;

  always_ff @(posedge clk_i) begin
    if (reset_i) begin
      fwd_check_v <= 1'b0;
    end else begin
      fwd_check_v     <= lq_exe_v_i;
      fwd_check_addr  <= lq_exe_addr_i;
      fwd_check_lq_id <= lq_exe_id_i;
    end
  end

  // --- SQ address CAM for store-to-load forwarding ---
  logic [sq_entries_p-1:0] sq_cam_w_v;
  wire sq_cam_insert = sq_exe_v_i;
  wire sq_cam_clear  = sq_commit_fire;

  assign sq_cam_w_v = sq_cam_clear  ? (sq_entries_p'(1) << sq_commit_id_o) :
                      sq_cam_insert ? (sq_entries_p'(1) << sq_exe_id_i)    :
                                      '0;

  logic [sq_entries_p-1:0] sq_cam_match;

  bsg_cam_1r1w_tag_array #(
    .width_p(addr_width_p)
   ,.els_p(sq_entries_p)
   ,.multiple_entries_p(1)
  ) sq_addr_cam (
    .clk_i(clk_i), .reset_i(reset_i)
   ,.w_v_i(sq_cam_w_v)
   ,.w_set_not_clear_i(~sq_cam_clear & sq_cam_insert)
   ,.w_tag_i(sq_cam_insert ? sq_exe_addr_i : '0)
   ,.w_empty_o()
   ,.r_v_i(fwd_check_v)
   ,.r_tag_i(fwd_check_addr)
   ,.r_match_o(sq_cam_match)
  );

  // Age mask: filter SQ entries older than the load.
  // In a split design, ALL committed stores have left the SQ, so ALL
  // SQ entries with valid addr+data are potentially forwardable.
  // Among matching entries, pick the youngest (most recently allocated).
  wire [sq_entries_p-1:0] sq_fwd_candidates = sq_cam_match
                                             & sq_addr_valid_r
                                             & sq_data_valid_r;

  // Find youngest matching store: rotate by SQ head, pick MSB
  wire [sq_id_width_lp-1:0] sq_head = sq_commit_id_o;

  logic [sq_entries_p-1:0] sq_rotated;
  assign sq_rotated = (sq_fwd_candidates >> sq_head)
                    | (sq_fwd_candidates << (sq_entries_p - sq_head));

  logic [sq_id_width_lp-1:0] sq_youngest_rot_idx;
  logic sq_fwd_hit_raw;

  bsg_priority_encode #(
    .width_p(sq_entries_p)
   ,.lo_to_hi_p(0)
  ) sq_fwd_pri (
    .i(sq_rotated)
   ,.addr_o(sq_youngest_rot_idx)
   ,.v_o(sq_fwd_hit_raw)
  );

  wire [sq_id_width_lp-1:0] sq_actual_bit =
    sq_id_width_lp'(sq_entries_p - 1) - sq_youngest_rot_idx;
  wire [sq_id_width_lp-1:0] sq_fwd_store_id =
    (sq_actual_bit + sq_head) % sq_entries_p;

  // Data mux
  logic [sq_entries_p-1:0] sq_fwd_onehot;
  bsg_decode_with_v #(.num_out_p(sq_entries_p)) sq_fwd_dec (
    .i(sq_fwd_store_id), .v_i(sq_fwd_hit_raw), .o(sq_fwd_onehot)
  );

  logic [data_width_p-1:0] sq_fwd_data;
  bsg_mux_one_hot #(
    .width_p(data_width_p)
   ,.els_p(sq_entries_p)
  ) sq_fwd_mux (
    .data_i(sq_data_r)
   ,.sel_one_hot_i(sq_fwd_onehot)
   ,.data_o(sq_fwd_data)
  );

  // Forwarding output (1 cycle after lq_exe)
  assign fwd_v_o     = fwd_check_v & sq_fwd_hit_raw;
  assign fwd_lq_id_o = fwd_check_lq_id;
  assign fwd_data_o  = sq_fwd_data;

  // ================================================================
  //  LOAD QUEUE
  // ================================================================

  wire lq_dispatch_fire = lq_dispatch_v_i & lq_dispatch_ready_o;
  wire lq_commit_fire   = lq_commit_yumi_i;

  // --- LQ metadata ---
  logic [lq_entries_p-1:0]                    lq_addr_valid_r;
  logic [lq_entries_p-1:0]                    lq_data_valid_r;
  logic [lq_entries_p-1:0][addr_width_p-1:0]  lq_addr_r;

  always_ff @(posedge clk_i) begin
    if (reset_i) begin
      lq_addr_valid_r <= '0;
      lq_data_valid_r <= '0;
    end else begin
      if (lq_dispatch_fire) begin
        lq_addr_valid_r[lq_dispatch_id_o] <= 1'b0;
        lq_data_valid_r[lq_dispatch_id_o] <= 1'b0;
      end
      if (lq_exe_v_i) begin
        lq_addr_valid_r[lq_exe_id_i] <= 1'b1;
        lq_addr_r[lq_exe_id_i]       <= lq_exe_addr_i;
      end
      // Data arrives from cache response or forwarding
      if (lq_cache_resp_v_i)
        lq_data_valid_r[lq_cache_resp_id_i] <= 1'b1;
      if (fwd_v_o)
        lq_data_valid_r[fwd_lq_id_o] <= 1'b1;
      if (lq_commit_fire)
        lq_data_valid_r[lq_commit_id_o] <= 1'b0;
    end
  end

  // --- LQ reorder buffer ---
  // Write from cache response or forwarding
  wire lq_wr_v = lq_cache_resp_v_i | fwd_v_o;
  wire [lq_id_width_lp-1:0] lq_wr_id =
    lq_cache_resp_v_i ? lq_cache_resp_id_i : fwd_lq_id_o;
  wire [data_width_p-1:0] lq_wr_data =
    lq_cache_resp_v_i ? lq_cache_resp_data_i : sq_fwd_data;

  bsg_fifo_reorder #(
    .width_p(data_width_p)
   ,.els_p(lq_entries_p)
  ) lq_reorder (
    .clk_i(clk_i), .reset_i(reset_i)
   ,.fifo_alloc_v_o(lq_dispatch_ready_o)
   ,.fifo_alloc_id_o(lq_dispatch_id_o)
   ,.fifo_alloc_yumi_i(lq_dispatch_fire)
   ,.write_v_i(lq_wr_v)
   ,.write_id_i(lq_wr_id)
   ,.write_data_i(lq_wr_data)
   ,.fifo_deq_v_o(lq_commit_v_o)
   ,.fifo_deq_data_o(lq_commit_data_o)
   ,.fifo_deq_id_o(lq_commit_id_o)
   ,.fifo_deq_yumi_i(lq_commit_fire)
   ,.empty_o()
  );

  // --- LQ cache request: oldest load with addr but no data ---
  wire [lq_id_width_lp-1:0] lq_head = lq_commit_id_o;
  logic [lq_entries_p-1:0] lq_need_cache;

  for (genvar i = 0; i < lq_entries_p; i++) begin : lq_rdy
    assign lq_need_cache[i] = lq_addr_valid_r[i] & ~lq_data_valid_r[i];
  end

  logic [lq_entries_p-1:0] lq_rotated_ready;
  assign lq_rotated_ready = (lq_need_cache >> lq_head)
                          | (lq_need_cache << (lq_entries_p - lq_head));

  logic [lq_id_width_lp-1:0] lq_oldest_rot;
  logic lq_oldest_v;

  bsg_priority_encode #(
    .width_p(lq_entries_p)
   ,.lo_to_hi_p(1)
  ) lq_issue_pri (
    .i(lq_rotated_ready)
   ,.addr_o(lq_oldest_rot)
   ,.v_o(lq_oldest_v)
  );

  wire [lq_id_width_lp-1:0] lq_issue_id =
    (lq_oldest_rot + lq_head) % lq_entries_p;

  assign lq_cache_req_v_o    = lq_oldest_v;
  assign lq_cache_req_addr_o = lq_addr_r[lq_issue_id];
  assign lq_cache_req_id_o   = lq_issue_id;

endmodule

`BSG_ABSTRACT_MODULE(bsg_lsq_split)
