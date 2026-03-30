/**
 *  bsg_lsq.sv — Unified Load-Store Queue
 *
 *  In-order allocation (from dispatch), out-of-order completion (from cache),
 *  in-order retirement (to ROB). Store-to-load forwarding via address CAM
 *  with circular-age-ordered youngest-older-store selection.
 *
 *  Built from BSG STL components:
 *    - bsg_fifo_reorder       : core alloc/retire buffer
 *    - bsg_cam_1r1w_tag_array : address CAM for store forwarding
 *    - bsg_priority_encode    : age-ordered store selection
 *    - bsg_mux_one_hot        : forwarded data mux
 *    - bsg_counter_up_down    : occupancy counter
 */

`include "bsg_defines.sv"

module bsg_lsq
  #(parameter `BSG_INV_PARAM(lsq_entries_p)
   ,parameter `BSG_INV_PARAM(addr_width_p)
   ,parameter `BSG_INV_PARAM(data_width_p)
   ,localparam entry_id_width_lp = `BSG_SAFE_CLOG2(lsq_entries_p)
   ,localparam data_mask_width_lp = (data_width_p >> 3)
  )
  (
    input                                clk_i
   ,input                                reset_i

   // -------------------------------------------------------
   // Dispatch port (in-order allocation)
   // -------------------------------------------------------
   ,input                                dispatch_v_i
   ,input                                dispatch_is_store_i
   ,output                               dispatch_ready_o
   ,output [entry_id_width_lp-1:0]       dispatch_id_o

   // -------------------------------------------------------
   // Address / store-data write-back port (from execute unit)
   // -------------------------------------------------------
   ,input                                exe_v_i
   ,input [entry_id_width_lp-1:0]        exe_id_i
   ,input [addr_width_p-1:0]             exe_addr_i
   ,input [data_width_p-1:0]             exe_data_i          // store data (ignored for loads)
   ,input [data_mask_width_lp-1:0]       exe_byte_mask_i     // store byte enables

   // -------------------------------------------------------
   // Cache request port (issued by LSQ)
   // -------------------------------------------------------
   ,output                               cache_req_v_o
   ,output                               cache_req_is_store_o
   ,output [addr_width_p-1:0]            cache_req_addr_o
   ,output [data_width_p-1:0]            cache_req_data_o
   ,output [data_mask_width_lp-1:0]      cache_req_byte_mask_o
   ,output [entry_id_width_lp-1:0]       cache_req_id_o
   ,input                                cache_req_yumi_i

   // -------------------------------------------------------
   // Cache response port (load data from cache/memory)
   // -------------------------------------------------------
   ,input                                cache_resp_v_i
   ,input [entry_id_width_lp-1:0]        cache_resp_id_i
   ,input [data_width_p-1:0]             cache_resp_data_i

   // -------------------------------------------------------
   // Store-to-load forwarding check (combinational)
   // -------------------------------------------------------
   ,input                                fwd_check_v_i
   ,input [entry_id_width_lp-1:0]        fwd_check_id_i      // load's entry ID
   ,input [addr_width_p-1:0]             fwd_check_addr_i
   ,output                               fwd_hit_o
   ,output [data_width_p-1:0]            fwd_data_o

   // -------------------------------------------------------
   // Commit/retire port (in-order, from ROB)
   // -------------------------------------------------------
   ,output                               commit_v_o
   ,output [entry_id_width_lp-1:0]       commit_id_o
   ,output                               commit_is_store_o
   ,output [data_width_p-1:0]            commit_data_o
   ,output [addr_width_p-1:0]            commit_addr_o
   ,input                                commit_yumi_i
  );

  // -------------------------------------------------------
  // Per-entry metadata registers
  // -------------------------------------------------------
  logic [lsq_entries_p-1:0]                          is_store_r;
  logic [lsq_entries_p-1:0]                          addr_valid_r;
  logic [lsq_entries_p-1:0]                          data_valid_r;
  logic [lsq_entries_p-1:0][addr_width_p-1:0]        addr_r;
  logic [lsq_entries_p-1:0][data_width_p-1:0]        data_r;
  logic [lsq_entries_p-1:0][data_mask_width_lp-1:0]  byte_mask_r;

  // Decode dispatch ID and exe ID to one-hot
  logic [lsq_entries_p-1:0] dispatch_id_decoded;
  logic [lsq_entries_p-1:0] exe_id_decoded;
  logic [lsq_entries_p-1:0] commit_id_decoded;

  wire dispatch_fire = dispatch_v_i & dispatch_ready_o;
  wire commit_fire   = commit_yumi_i;

  bsg_decode_with_v #(.num_out_p(lsq_entries_p)) dispatch_dec (
    .i(dispatch_id_o), .v_i(dispatch_fire), .o(dispatch_id_decoded)
  );

  bsg_decode_with_v #(.num_out_p(lsq_entries_p)) exe_dec (
    .i(exe_id_i), .v_i(exe_v_i), .o(exe_id_decoded)
  );

  bsg_decode_with_v #(.num_out_p(lsq_entries_p)) commit_dec (
    .i(commit_id_o), .v_i(commit_fire), .o(commit_id_decoded)
  );

  // Metadata write logic — single always_ff with indexed writes
  always_ff @(posedge clk_i) begin
    if (reset_i) begin
      is_store_r   <= '0;
      addr_valid_r <= '0;
      data_valid_r <= '0;
    end else begin
      // Dispatch: record is_store for new entry
      if (dispatch_fire) begin
        is_store_r[dispatch_id_o] <= dispatch_is_store_i;
        // Clear stale valid bits for the new entry
        addr_valid_r[dispatch_id_o] <= 1'b0;
        data_valid_r[dispatch_id_o] <= 1'b0;
      end

      // Execute writeback: set address (and store data)
      if (exe_v_i) begin
        addr_valid_r[exe_id_i] <= 1'b1;
        addr_r[exe_id_i]       <= exe_addr_i;
        if (is_store_r[exe_id_i]) begin
          data_valid_r[exe_id_i] <= 1'b1;
          data_r[exe_id_i]       <= exe_data_i;
          byte_mask_r[exe_id_i]  <= exe_byte_mask_i;
        end
      end

      // Cache response: mark load data valid
      if (cache_resp_v_i)
        data_valid_r[cache_resp_id_i] <= 1'b1;

      // Commit: clear entry metadata
      if (commit_fire) begin
        is_store_r[commit_id_o]   <= 1'b0;
        addr_valid_r[commit_id_o] <= 1'b0;
        data_valid_r[commit_id_o] <= 1'b0;
      end
    end
  end

  // -------------------------------------------------------
  // Reorder buffer: in-order alloc, out-of-order write, in-order dequeue
  // -------------------------------------------------------
  // Write port arbitration: cache response (loads) wins over store execute
  wire reorder_write_v    = cache_resp_v_i;
  wire [entry_id_width_lp-1:0] reorder_write_id = cache_resp_id_i;
  wire [data_width_p-1:0] reorder_write_data    = cache_resp_data_i;

  // For stores, write data at execute time
  wire store_exe_fire = exe_v_i & is_store_r[exe_id_i];
  wire reorder_wr_v   = reorder_write_v | (store_exe_fire & ~reorder_write_v);
  wire [entry_id_width_lp-1:0] reorder_wr_id =
    reorder_write_v ? reorder_write_id : exe_id_i;
  wire [data_width_p-1:0] reorder_wr_data =
    reorder_write_v ? reorder_write_data : exe_data_i;

  bsg_fifo_reorder #(
    .width_p(data_width_p)
   ,.els_p(lsq_entries_p)
  ) reorder_buf (
    .clk_i(clk_i)
   ,.reset_i(reset_i)

   ,.fifo_alloc_v_o(dispatch_ready_o)
   ,.fifo_alloc_id_o(dispatch_id_o)
   ,.fifo_alloc_yumi_i(dispatch_fire)

   ,.write_v_i(reorder_wr_v)
   ,.write_id_i(reorder_wr_id)
   ,.write_data_i(reorder_wr_data)

   ,.fifo_deq_v_o(commit_v_o)
   ,.fifo_deq_data_o(commit_data_o)
   ,.fifo_deq_id_o(commit_id_o)
   ,.fifo_deq_yumi_i(commit_fire)

   ,.empty_o()
  );

  assign commit_is_store_o = is_store_r[commit_id_o];
  assign commit_addr_o     = addr_r[commit_id_o];

  // -------------------------------------------------------
  // Address CAM for store-to-load forwarding
  //   tag = address, match output = one-hot of entries with same addr
  //   multiple_entries_p = 1: allow multiple stores to same address
  // -------------------------------------------------------
  // CAM write: insert when store gets valid address, clear on commit
  wire cam_insert = exe_v_i & is_store_r[exe_id_i];
  wire cam_clear  = commit_fire & is_store_r[commit_id_o];

  // Priority: clear on commit > insert (avoid deadlock by freeing entries)
  wire [lsq_entries_p-1:0] cam_w_v;
  wire cam_w_set_not_clear;

  assign cam_w_v = cam_clear  ? commit_id_decoded :
                   cam_insert ? exe_id_decoded     :
                                '0;
  assign cam_w_set_not_clear = ~cam_clear & cam_insert;

  logic [lsq_entries_p-1:0] cam_match;

  bsg_cam_1r1w_tag_array #(
    .width_p(addr_width_p)
   ,.els_p(lsq_entries_p)
   ,.multiple_entries_p(1)
  ) addr_cam (
    .clk_i(clk_i)
   ,.reset_i(reset_i)

   ,.w_v_i(cam_w_v)
   ,.w_set_not_clear_i(cam_w_set_not_clear)
   ,.w_tag_i(cam_insert ? exe_addr_i : '0)
   ,.w_empty_o()

   ,.r_v_i(fwd_check_v_i)
   ,.r_tag_i(fwd_check_addr_i)
   ,.r_match_o(cam_match)
  );

  // -------------------------------------------------------
  // Age-ordered youngest-older-store selection
  // -------------------------------------------------------
  // Filter: must be a store, have valid data, and be older than the load
  logic [lsq_entries_p-1:0] older_mask;

  // Circular-buffer age mask: entries between head (oldest) and load_id (exclusive)
  wire [entry_id_width_lp-1:0] head_ptr = commit_id_o;  // rptr = oldest entry
  wire [entry_id_width_lp-1:0] load_id  = fwd_check_id_i;

  for (genvar i = 0; i < lsq_entries_p; i++) begin : age
    wire [entry_id_width_lp-1:0] idx = entry_id_width_lp'(i);
    // Entry i is "older" than load if it's in the range [head_ptr, load_id)
    // in circular order
    if (lsq_entries_p == (1 << entry_id_width_lp)) begin : pow2
      // Power-of-2: use unsigned subtraction modulo
      wire [entry_id_width_lp-1:0] age_i    = idx - head_ptr;
      wire [entry_id_width_lp-1:0] age_load = load_id - head_ptr;
      assign older_mask[i] = (age_i < age_load);
    end else begin : non_pow2
      // General case with explicit circular comparison
      wire in_range_nowrap = (idx >= head_ptr) & (idx < load_id);
      wire in_range_wrap   = (idx >= head_ptr) | (idx < load_id);
      assign older_mask[i] = (head_ptr <= load_id) ? in_range_nowrap : in_range_wrap;
    end
  end

  // Candidate stores for forwarding
  wire [lsq_entries_p-1:0] fwd_candidates = cam_match
                                           & is_store_r
                                           & data_valid_r
                                           & older_mask;

  // Rotate candidates so load's position is at bit 0,
  // then priority-encode from MSB to find youngest older store
  logic [lsq_entries_p-1:0] rotated_candidates;
  assign rotated_candidates = (fwd_candidates >> load_id)
                            | (fwd_candidates << (lsq_entries_p - load_id));

  logic [entry_id_width_lp-1:0] youngest_rotated_idx;
  logic fwd_hit_raw;

  // lo_to_hi_p=0: scan from MSB (= entry just before load = youngest older)
  bsg_priority_encode #(
    .width_p(lsq_entries_p)
   ,.lo_to_hi_p(0)
  ) age_pri_enc (
    .i(rotated_candidates)
   ,.addr_o(youngest_rotated_idx)
   ,.v_o(fwd_hit_raw)
  );

  // lo_to_hi_p=0 returns MSB-relative index (0 = bit N-1).
  // Convert to absolute bit position, then rotate back.
  wire [entry_id_width_lp-1:0] actual_rotated_bit =
    entry_id_width_lp'(lsq_entries_p - 1) - youngest_rotated_idx;
  wire [entry_id_width_lp-1:0] youngest_store_id =
    (actual_rotated_bit + load_id) % lsq_entries_p;

  // One-hot select for data mux
  logic [lsq_entries_p-1:0] youngest_store_onehot;
  bsg_decode_with_v #(.num_out_p(lsq_entries_p)) fwd_sel_dec (
    .i(youngest_store_id)
   ,.v_i(fwd_hit_raw)
   ,.o(youngest_store_onehot)
  );

  // Forwarded data mux
  bsg_mux_one_hot #(
    .width_p(data_width_p)
   ,.els_p(lsq_entries_p)
  ) fwd_data_mux (
    .data_i(data_r)
   ,.sel_one_hot_i(youngest_store_onehot)
   ,.data_o(fwd_data_o)
  );

  assign fwd_hit_o = fwd_hit_raw;

  // -------------------------------------------------------
  // Cache request port: issue loads/stores to cache
  // -------------------------------------------------------
  // Simple policy: loads issue when address is valid and no forwarding hit;
  // stores issue at commit time.
  // For simplicity, expose ready entries and let external scheduler drive.
  // Here we expose the oldest ready-to-issue load.

  logic [lsq_entries_p-1:0] load_ready;
  for (genvar i = 0; i < lsq_entries_p; i++) begin : lr
    assign load_ready[i] = ~is_store_r[i] & addr_valid_r[i] & ~data_valid_r[i];
  end

  // Find oldest ready load (priority from head)
  logic [lsq_entries_p-1:0] rotated_load_ready;
  assign rotated_load_ready = (load_ready >> head_ptr)
                            | (load_ready << (lsq_entries_p - head_ptr));

  logic [entry_id_width_lp-1:0] oldest_load_rotated;
  logic oldest_load_v;

  bsg_priority_encode #(
    .width_p(lsq_entries_p)
   ,.lo_to_hi_p(1)
  ) load_issue_enc (
    .i(rotated_load_ready)
   ,.addr_o(oldest_load_rotated)
   ,.v_o(oldest_load_v)
  );

  wire [entry_id_width_lp-1:0] oldest_load_id =
    (oldest_load_rotated + head_ptr) % lsq_entries_p;

  // Store commit issues to cache
  wire store_commit_req = commit_v_o & commit_is_store_o;

  // Prioritize store commit over load issue
  assign cache_req_v_o        = store_commit_req | oldest_load_v;
  assign cache_req_is_store_o = store_commit_req;
  assign cache_req_id_o       = store_commit_req ? commit_id_o : oldest_load_id;
  assign cache_req_addr_o     = store_commit_req ? addr_r[commit_id_o] : addr_r[oldest_load_id];
  assign cache_req_data_o     = store_commit_req ? data_r[commit_id_o] : '0;
  assign cache_req_byte_mask_o = store_commit_req ? byte_mask_r[commit_id_o] : '1;

  // -------------------------------------------------------
  // Occupancy counter
  // -------------------------------------------------------
  logic [`BSG_WIDTH(lsq_entries_p)-1:0] occupancy_lo;

  bsg_counter_up_down #(
    .max_val_p(lsq_entries_p)
   ,.init_val_p(0)
   ,.max_step_p(1)
  ) occupancy_ctr (
    .clk_i(clk_i)
   ,.reset_i(reset_i)
   ,.up_i(dispatch_fire)
   ,.down_i(commit_fire)
   ,.count_o(occupancy_lo)
  );

endmodule

`BSG_ABSTRACT_MODULE(bsg_lsq)
