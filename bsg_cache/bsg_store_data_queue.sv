/**
 *  bsg_store_data_queue.sv — Store Data Queue (SDQ)
 *
 *  Holds store data + byte mask until commit. Data can arrive
 *  independently from address (from a different pipeline stage).
 *  Uses bsg_fifo_reorder for in-order alloc / out-of-order data write / in-order commit.
 *
 *  Entry IDs are shared with the paired bsg_store_addr_queue.
 *  Allocation and commit are driven externally (same yumi as SAQ).
 */

`include "bsg_defines.sv"

module bsg_store_data_queue
  #(parameter `BSG_INV_PARAM(entries_p)
   ,parameter `BSG_INV_PARAM(data_width_p)
   ,localparam id_width_lp = `BSG_SAFE_CLOG2(entries_p)
   ,localparam data_mask_width_lp = (data_width_p >> 3)
  )
  (
    input                                clk_i
   ,input                                reset_i

   // --- Dispatch (shared with SAQ — same alloc_yumi) ---
   ,output                               alloc_v_o
   ,output [id_width_lp-1:0]             alloc_id_o
   ,input                                alloc_yumi_i

   // --- Data write (from register file / execute) ---
   ,input                                data_v_i
   ,input  [id_width_lp-1:0]             data_id_i
   ,input  [data_width_p-1:0]            data_i
   ,input  [data_mask_width_lp-1:0]      byte_mask_i

   // --- Commit (in-order, same commit_yumi as SAQ) ---
   ,output                               commit_v_o
   ,output [id_width_lp-1:0]             commit_id_o
   ,output [data_width_p-1:0]            commit_data_o
   ,output [data_mask_width_lp-1:0]      commit_byte_mask_o
   ,input                                commit_yumi_i

   // --- Forwarding data read (indexed by SAQ's CAM match) ---
   ,output [entries_p-1:0]               data_valid_o
   ,output [entries_p-1:0][data_width_p-1:0] data_array_o   // for forwarding mux
  );

  wire alloc_fire  = alloc_yumi_i;
  wire commit_fire = commit_yumi_i;

  // -------------------------------------------------------
  // Reorder buffer: in-order alloc, out-of-order data write, in-order dequeue
  // -------------------------------------------------------
  bsg_fifo_reorder #(
    .width_p(data_width_p)
   ,.els_p(entries_p)
  ) reorder (
    .clk_i(clk_i), .reset_i(reset_i)
   ,.fifo_alloc_v_o(alloc_v_o)
   ,.fifo_alloc_id_o(alloc_id_o)
   ,.fifo_alloc_yumi_i(alloc_fire)
   ,.write_v_i(data_v_i)
   ,.write_id_i(data_id_i)
   ,.write_data_i(data_i)
   ,.fifo_deq_v_o(commit_v_o)
   ,.fifo_deq_data_o(commit_data_o)
   ,.fifo_deq_id_o(commit_id_o)
   ,.fifo_deq_yumi_i(commit_fire)
   ,.empty_o()
  );

  // -------------------------------------------------------
  // Per-entry data valid + byte mask (not in reorder buffer)
  // -------------------------------------------------------
  logic [entries_p-1:0]                          data_valid_r;
  logic [entries_p-1:0][data_width_p-1:0]        data_r;
  logic [entries_p-1:0][data_mask_width_lp-1:0]  byte_mask_r;

  always_ff @(posedge clk_i) begin
    if (reset_i) begin
      data_valid_r <= '0;
    end else begin
      if (alloc_fire)
        data_valid_r[alloc_id_o] <= 1'b0;
      if (data_v_i) begin
        data_valid_r[data_id_i] <= 1'b1;
        data_r[data_id_i]       <= data_i;
        byte_mask_r[data_id_i]  <= byte_mask_i;
      end
      if (commit_fire)
        data_valid_r[commit_id_o] <= 1'b0;
    end
  end

  assign data_valid_o      = data_valid_r;
  assign data_array_o      = data_r;
  assign commit_byte_mask_o = byte_mask_r[commit_id_o];

endmodule

`BSG_ABSTRACT_MODULE(bsg_store_data_queue)
