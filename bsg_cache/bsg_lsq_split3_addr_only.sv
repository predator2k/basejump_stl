/**
 *  bsg_lsq_split3_addr_only.sv
 *
 *  Address-only LSQ for memory disambiguation.
 *  32-entry Load Queue + 16-entry Store Address Queue, no Store Data Queue.
 *  Wraps bsg_lsq_split3 with data_width_p=0.
 */

`include "bsg_defines.sv"

module bsg_lsq_split3_addr_only
  #(parameter addr_width_p  = 48
   ,parameter sq_entries_p  = 16
   ,parameter lq_entries_p  = 32
   ,localparam sq_id_width_lp = `BSG_SAFE_CLOG2(sq_entries_p)
   ,localparam lq_id_width_lp = `BSG_SAFE_CLOG2(lq_entries_p)
  )
  (
    input                                clk_i
   ,input                                reset_i

   // Store dispatch
   ,input                                sq_dispatch_v_i
   ,output                               sq_dispatch_ready_o
   ,output [sq_id_width_lp-1:0]          sq_dispatch_id_o

   // Load dispatch
   ,input                                lq_dispatch_v_i
   ,output                               lq_dispatch_ready_o
   ,output [lq_id_width_lp-1:0]          lq_dispatch_id_o

   // Store address write
   ,input                                sq_addr_v_i
   ,input [sq_id_width_lp-1:0]           sq_addr_id_i
   ,input [addr_width_p-1:0]             sq_addr_i

   // Load address write
   ,input                                lq_exe_v_i
   ,input [lq_id_width_lp-1:0]           lq_exe_id_i
   ,input [addr_width_p-1:0]             lq_exe_addr_i

   // Address-only forwarding check result (hit = older store has same addr)
   ,output                               fwd_v_o
   ,output [lq_id_width_lp-1:0]          fwd_lq_id_o

   // Store commit
   ,output                               sq_commit_v_o
   ,output [sq_id_width_lp-1:0]          sq_commit_id_o
   ,output [addr_width_p-1:0]            sq_commit_addr_o
   ,input                                sq_commit_yumi_i

   // Load commit
   ,output                               lq_commit_v_o
   ,output [lq_id_width_lp-1:0]          lq_commit_id_o
   ,input                                lq_commit_yumi_i
  );

  bsg_lsq_split3 #(
    .sq_entries_p(sq_entries_p)
   ,.lq_entries_p(lq_entries_p)
   ,.addr_width_p(addr_width_p)
   ,.data_width_p(0)
  ) lsq (
    .clk_i(clk_i)
   ,.reset_i(reset_i)

   ,.sq_dispatch_v_i(sq_dispatch_v_i)
   ,.sq_dispatch_ready_o(sq_dispatch_ready_o)
   ,.sq_dispatch_id_o(sq_dispatch_id_o)

   ,.lq_dispatch_v_i(lq_dispatch_v_i)
   ,.lq_dispatch_ready_o(lq_dispatch_ready_o)
   ,.lq_dispatch_id_o(lq_dispatch_id_o)

   ,.sq_addr_v_i(sq_addr_v_i)
   ,.sq_addr_id_i(sq_addr_id_i)
   ,.sq_addr_i(sq_addr_i)

   // No store data (data_width_p=0)
   ,.sq_data_v_i(1'b0)
   ,.sq_data_id_i('0)
   ,.sq_data_i('0)
   ,.sq_data_byte_mask_i('0)

   ,.lq_exe_v_i(lq_exe_v_i)
   ,.lq_exe_id_i(lq_exe_id_i)
   ,.lq_exe_addr_i(lq_exe_addr_i)

   ,.fwd_v_o(fwd_v_o)
   ,.fwd_lq_id_o(fwd_lq_id_o)
   ,.fwd_data_o()

   // No load cache ports (address-only)
   ,.lq_cache_req_v_o()
   ,.lq_cache_req_addr_o()
   ,.lq_cache_req_id_o()
   ,.lq_cache_req_yumi_i(1'b0)

   ,.lq_cache_resp_v_i(1'b0)
   ,.lq_cache_resp_id_i('0)
   ,.lq_cache_resp_data_i('0)

   ,.sq_commit_v_o(sq_commit_v_o)
   ,.sq_commit_id_o(sq_commit_id_o)
   ,.sq_commit_addr_o(sq_commit_addr_o)
   ,.sq_commit_data_o()
   ,.sq_commit_byte_mask_o()
   ,.sq_commit_yumi_i(sq_commit_yumi_i)

   ,.lq_commit_v_o(lq_commit_v_o)
   ,.lq_commit_id_o(lq_commit_id_o)
   ,.lq_commit_data_o()
   ,.lq_commit_yumi_i(lq_commit_yumi_i)
  );

endmodule
