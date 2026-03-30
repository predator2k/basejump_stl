/**
 *  bsg_load_queue.sv — Load Queue (LQ)
 *
 *  In-order allocation, issues loads to cache, receives responses.
 *  Also accepts store-to-load forwarded data.
 *  Uses bsg_fifo_reorder for in-order alloc / out-of-order data write / in-order commit.
 */

`include "bsg_defines.sv"

module bsg_load_queue
  #(parameter `BSG_INV_PARAM(entries_p)
   ,parameter `BSG_INV_PARAM(addr_width_p)
   ,parameter `BSG_INV_PARAM(data_width_p)
   ,localparam id_width_lp = `BSG_SAFE_CLOG2(entries_p)
  )
  (
    input                          clk_i
   ,input                          reset_i

   // --- Dispatch (in-order) ---
   ,output                         alloc_v_o
   ,output [id_width_lp-1:0]       alloc_id_o
   ,input                          alloc_yumi_i

   // --- Address write (from AGU) ---
   ,input                          addr_v_i
   ,input  [id_width_lp-1:0]       addr_id_i
   ,input  [addr_width_p-1:0]      addr_i

   // --- Cache request (oldest load needing data) ---
   ,output                         cache_req_v_o
   ,output [addr_width_p-1:0]      cache_req_addr_o
   ,output [id_width_lp-1:0]       cache_req_id_o
   ,input                          cache_req_yumi_i

   // --- Cache response ---
   ,input                          cache_resp_v_i
   ,input  [id_width_lp-1:0]       cache_resp_id_i
   ,input  [data_width_p-1:0]      cache_resp_data_i

   // --- Store forwarding data ---
   ,input                          fwd_v_i
   ,input  [id_width_lp-1:0]       fwd_id_i
   ,input  [data_width_p-1:0]      fwd_data_i

   // --- Commit (in-order) ---
   ,output                         commit_v_o
   ,output [id_width_lp-1:0]       commit_id_o
   ,output [data_width_p-1:0]      commit_data_o
   ,input                          commit_yumi_i
  );

  wire alloc_fire  = alloc_yumi_i;
  wire commit_fire = commit_yumi_i;

  // -------------------------------------------------------
  // Per-entry address storage
  // -------------------------------------------------------
  logic [entries_p-1:0]                    addr_valid_r;
  logic [entries_p-1:0]                    data_valid_r;
  logic [entries_p-1:0][addr_width_p-1:0]  addr_r;

  always_ff @(posedge clk_i) begin
    if (reset_i) begin
      addr_valid_r <= '0;
      data_valid_r <= '0;
    end else begin
      if (alloc_fire) begin
        addr_valid_r[alloc_id_o] <= 1'b0;
        data_valid_r[alloc_id_o] <= 1'b0;
      end
      if (addr_v_i) begin
        addr_valid_r[addr_id_i] <= 1'b1;
        addr_r[addr_id_i]       <= addr_i;
      end
      if (cache_resp_v_i)
        data_valid_r[cache_resp_id_i] <= 1'b1;
      if (fwd_v_i)
        data_valid_r[fwd_id_i] <= 1'b1;
      if (commit_fire) begin
        addr_valid_r[commit_id_o] <= 1'b0;
        data_valid_r[commit_id_o] <= 1'b0;
      end
    end
  end

  // -------------------------------------------------------
  // Reorder buffer: data from cache resp or forwarding
  // -------------------------------------------------------
  wire wr_v = cache_resp_v_i | fwd_v_i;
  wire [id_width_lp-1:0] wr_id   = cache_resp_v_i ? cache_resp_id_i : fwd_id_i;
  wire [data_width_p-1:0] wr_data = cache_resp_v_i ? cache_resp_data_i : fwd_data_i;

  bsg_fifo_reorder #(
    .width_p(data_width_p)
   ,.els_p(entries_p)
  ) reorder (
    .clk_i(clk_i), .reset_i(reset_i)
   ,.fifo_alloc_v_o(alloc_v_o)
   ,.fifo_alloc_id_o(alloc_id_o)
   ,.fifo_alloc_yumi_i(alloc_fire)
   ,.write_v_i(wr_v)
   ,.write_id_i(wr_id)
   ,.write_data_i(wr_data)
   ,.fifo_deq_v_o(commit_v_o)
   ,.fifo_deq_data_o(commit_data_o)
   ,.fifo_deq_id_o(commit_id_o)
   ,.fifo_deq_yumi_i(commit_fire)
   ,.empty_o()
  );

  // -------------------------------------------------------
  // Cache request: oldest load with addr but no data
  // -------------------------------------------------------
  wire [id_width_lp-1:0] head = commit_id_o;

  logic [entries_p-1:0] need_cache;
  for (genvar i = 0; i < entries_p; i++) begin : nc
    assign need_cache[i] = addr_valid_r[i] & ~data_valid_r[i];
  end

  logic [entries_p-1:0] rotated_ready;
  assign rotated_ready = (need_cache >> head) | (need_cache << (entries_p - head));

  logic [id_width_lp-1:0] oldest_rot;
  logic oldest_v;

  bsg_priority_encode #(
    .width_p(entries_p), .lo_to_hi_p(1)
  ) issue_pri (
    .i(rotated_ready), .addr_o(oldest_rot), .v_o(oldest_v)
  );

  wire [id_width_lp-1:0] issue_id = (oldest_rot + head) % entries_p;

  assign cache_req_v_o    = oldest_v;
  assign cache_req_addr_o = addr_r[issue_id];
  assign cache_req_id_o   = issue_id;

endmodule

`BSG_ABSTRACT_MODULE(bsg_load_queue)
