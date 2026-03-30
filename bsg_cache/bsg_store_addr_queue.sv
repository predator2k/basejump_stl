/**
 *  bsg_store_addr_queue.sv — Store Address Queue (SAQ)
 *
 *  In-order allocation, holds store addresses until commit.
 *  Contains a CAM for store-to-load forwarding address matching.
 *  Address and data arrive independently (addr from AGU, data from register file).
 *
 *  Paired with bsg_store_data_queue (same entry IDs, separate dispatch/commit).
 */

`include "bsg_defines.sv"

module bsg_store_addr_queue
  #(parameter `BSG_INV_PARAM(entries_p)
   ,parameter `BSG_INV_PARAM(addr_width_p)
   ,localparam id_width_lp = `BSG_SAFE_CLOG2(entries_p)
  )
  (
    input                          clk_i
   ,input                          reset_i

   // --- Dispatch (in-order, shared alloc with SDQ) ---
   ,output                         alloc_v_o          // entry available
   ,output [id_width_lp-1:0]       alloc_id_o         // allocated entry ID
   ,input                          alloc_yumi_i       // consume allocation

   // --- Address write (from AGU) ---
   ,input                          addr_v_i
   ,input  [id_width_lp-1:0]       addr_id_i
   ,input  [addr_width_p-1:0]      addr_i

   // --- Commit (in-order) ---
   ,output                         commit_v_o
   ,output [id_width_lp-1:0]       commit_id_o
   ,output [addr_width_p-1:0]      commit_addr_o
   ,input                          commit_yumi_i

   // --- Forwarding CAM read port (from LQ) ---
   ,input                          fwd_r_v_i
   ,input  [addr_width_p-1:0]      fwd_r_addr_i
   ,output [entries_p-1:0]         fwd_cam_match_o    // one-hot match vector
   ,output [entries_p-1:0]         fwd_addr_valid_o   // which entries have valid addr
  );

  wire alloc_fire  = alloc_yumi_i;
  wire commit_fire = commit_yumi_i;

  // -------------------------------------------------------
  // Pointer tracking (circular FIFO) for in-order alloc/commit
  // -------------------------------------------------------
  logic [id_width_lp-1:0] wptr_r, rptr_r;
  logic full, empty;

  bsg_fifo_tracker #(.els_p(entries_p)) tracker (
    .clk_i(clk_i), .reset_i(reset_i)
   ,.enq_i(alloc_fire & ~full)
   ,.deq_i(commit_fire & ~empty)
   ,.wptr_r_o(wptr_r), .rptr_r_o(rptr_r), .rptr_n_o()
   ,.full_o(full), .empty_o(empty)
  );

  assign alloc_v_o  = ~full;
  assign alloc_id_o = wptr_r;

  // -------------------------------------------------------
  // Per-entry address storage
  // -------------------------------------------------------
  logic [entries_p-1:0]                    addr_valid_r;
  logic [entries_p-1:0][addr_width_p-1:0]  addr_r;

  // Commit: head entry is ready when it has a valid address
  assign commit_id_o   = rptr_r;
  assign commit_v_o    = ~empty & addr_valid_r[rptr_r];
  assign commit_addr_o = addr_r[rptr_r];

  always_ff @(posedge clk_i) begin
    if (reset_i) begin
      addr_valid_r <= '0;
    end else begin
      if (alloc_fire)
        addr_valid_r[alloc_id_o] <= 1'b0;
      if (addr_v_i) begin
        addr_valid_r[addr_id_i] <= 1'b1;
        addr_r[addr_id_i]       <= addr_i;
      end
      if (commit_fire)
        addr_valid_r[commit_id_o] <= 1'b0;
    end
  end

  assign fwd_addr_valid_o = addr_valid_r;

  // -------------------------------------------------------
  // Address CAM for store-to-load forwarding
  // -------------------------------------------------------
  logic [entries_p-1:0] cam_w_v;
  wire cam_insert = addr_v_i;
  wire cam_clear  = commit_fire;

  assign cam_w_v = cam_clear  ? (entries_p'(1) << commit_id_o) :
                   cam_insert ? (entries_p'(1) << addr_id_i)   :
                                '0;

  bsg_cam_1r1w_tag_array #(
    .width_p(addr_width_p)
   ,.els_p(entries_p)
   ,.multiple_entries_p(1)
  ) addr_cam (
    .clk_i(clk_i), .reset_i(reset_i)
   ,.w_v_i(cam_w_v)
   ,.w_set_not_clear_i(~cam_clear & cam_insert)
   ,.w_tag_i(cam_insert ? addr_i : '0)
   ,.w_empty_o()
   ,.r_v_i(fwd_r_v_i)
   ,.r_tag_i(fwd_r_addr_i)
   ,.r_match_o(fwd_cam_match_o)
  );

endmodule

`BSG_ABSTRACT_MODULE(bsg_store_addr_queue)
