/**
 *  bsg_lsq_split3.sv — 3-way Split LSQ: SAQ + SDQ + LQ
 *
 *  Store Address Queue and Store Data Queue are decoupled, allowing
 *  address and data to arrive from different pipeline stages independently.
 *  Forwarding logic combines SAQ's CAM match with SDQ's data array.
 *
 *  Architecture (Cortex-A710 style):
 *    SAQ: addr from AGU, CAM for forwarding, in-order commit
 *    SDQ: data from register file, in-order commit (shared IDs with SAQ)
 *    LQ:  addr from AGU, issues to cache or gets forwarded data
 */

`include "bsg_defines.sv"

module bsg_lsq_split3
  #(parameter `BSG_INV_PARAM(sq_entries_p)
   ,parameter `BSG_INV_PARAM(lq_entries_p)
   ,parameter `BSG_INV_PARAM(addr_width_p)
   ,parameter `BSG_INV_PARAM(data_width_p)
   ,localparam sq_id_width_lp     = `BSG_SAFE_CLOG2(sq_entries_p)
   ,localparam lq_id_width_lp     = `BSG_SAFE_CLOG2(lq_entries_p)
   ,localparam data_mask_width_lp = (data_width_p >> 3)
  )
  (
    input                                clk_i
   ,input                                reset_i

   // --- Store dispatch ---
   ,input                                sq_dispatch_v_i
   ,output                               sq_dispatch_ready_o
   ,output [sq_id_width_lp-1:0]          sq_dispatch_id_o

   // --- Load dispatch ---
   ,input                                lq_dispatch_v_i
   ,output                               lq_dispatch_ready_o
   ,output [lq_id_width_lp-1:0]          lq_dispatch_id_o

   // --- Store address write (from AGU, can be different cycle from data) ---
   ,input                                sq_addr_v_i
   ,input [sq_id_width_lp-1:0]           sq_addr_id_i
   ,input [addr_width_p-1:0]             sq_addr_i

   // --- Store data write (from register file, can be different cycle from addr) ---
   ,input                                sq_data_v_i
   ,input [sq_id_width_lp-1:0]           sq_data_id_i
   ,input [data_width_p-1:0]             sq_data_i
   ,input [data_mask_width_lp-1:0]       sq_data_byte_mask_i

   // --- Load address write (from AGU, triggers forwarding check) ---
   ,input                                lq_exe_v_i
   ,input [lq_id_width_lp-1:0]           lq_exe_id_i
   ,input [addr_width_p-1:0]             lq_exe_addr_i

   // --- Forwarding result (1 cycle after lq_exe) ---
   ,output logic                         fwd_v_o
   ,output logic [lq_id_width_lp-1:0]    fwd_lq_id_o
   ,output logic [data_width_p-1:0]      fwd_data_o

   // --- Load cache request ---
   ,output                               lq_cache_req_v_o
   ,output [addr_width_p-1:0]            lq_cache_req_addr_o
   ,output [lq_id_width_lp-1:0]          lq_cache_req_id_o
   ,input                                lq_cache_req_yumi_i

   // --- Load cache response ---
   ,input                                lq_cache_resp_v_i
   ,input [lq_id_width_lp-1:0]           lq_cache_resp_id_i
   ,input [data_width_p-1:0]             lq_cache_resp_data_i

   // --- Store commit (addr+data both ready → write to cache) ---
   ,output                               sq_commit_v_o
   ,output [sq_id_width_lp-1:0]          sq_commit_id_o
   ,output [addr_width_p-1:0]            sq_commit_addr_o
   ,output [data_width_p-1:0]            sq_commit_data_o
   ,output [data_mask_width_lp-1:0]      sq_commit_byte_mask_o
   ,input                                sq_commit_yumi_i

   // --- Load commit ---
   ,output                               lq_commit_v_o
   ,output [lq_id_width_lp-1:0]          lq_commit_id_o
   ,output [data_width_p-1:0]            lq_commit_data_o
   ,input                                lq_commit_yumi_i
  );

  // -------------------------------------------------------
  // Store Address Queue (SAQ)
  // -------------------------------------------------------
  wire [sq_entries_p-1:0] saq_cam_match;
  wire [sq_entries_p-1:0] saq_addr_valid;

  // Forwarding check: registered from lq_exe
  logic                        fwd_check_v;
  logic [addr_width_p-1:0]     fwd_check_addr;
  logic [lq_id_width_lp-1:0]  fwd_check_lq_id;

  always_ff @(posedge clk_i) begin
    if (reset_i)
      fwd_check_v <= 1'b0;
    else begin
      fwd_check_v     <= lq_exe_v_i;
      fwd_check_addr  <= lq_exe_addr_i;
      fwd_check_lq_id <= lq_exe_id_i;
    end
  end

  // SAQ alloc and commit
  wire saq_alloc_v;
  wire [sq_id_width_lp-1:0] saq_alloc_id;
  wire sq_dispatch_fire = sq_dispatch_v_i & sq_dispatch_ready_o;
  wire saq_commit_v;
  wire [sq_id_width_lp-1:0] saq_commit_id;

  bsg_store_addr_queue #(
    .entries_p(sq_entries_p)
   ,.addr_width_p(addr_width_p)
  ) saq (
    .clk_i(clk_i), .reset_i(reset_i)
   ,.alloc_v_o(saq_alloc_v)
   ,.alloc_id_o(saq_alloc_id)
   ,.alloc_yumi_i(sq_dispatch_fire)
   ,.addr_v_i(sq_addr_v_i)
   ,.addr_id_i(sq_addr_id_i)
   ,.addr_i(sq_addr_i)
   ,.commit_v_o(saq_commit_v)
   ,.commit_id_o(saq_commit_id)
   ,.commit_addr_o(sq_commit_addr_o)
   ,.commit_yumi_i(sq_commit_yumi_i)
   ,.fwd_r_v_i(fwd_check_v)
   ,.fwd_r_addr_i(fwd_check_addr)
   ,.fwd_cam_match_o(saq_cam_match)
   ,.fwd_addr_valid_o(saq_addr_valid)
  );

  // -------------------------------------------------------
  // Store Data Queue (SDQ) — only when data_width_p > 0
  // -------------------------------------------------------
  wire [sq_entries_p-1:0]                    sdq_data_valid;
  wire [sq_entries_p-1:0][data_width_p-1:0]  sdq_data_array;
  logic [data_width_p-1:0] fwd_data_muxed;
  logic fwd_hit_raw;

  if (data_width_p > 0) begin : sdq_gen

    wire sdq_alloc_v;
    wire [sq_id_width_lp-1:0] sdq_alloc_id;
    wire sdq_commit_v;

    // Both SAQ and SDQ must be ready for store dispatch
    assign sq_dispatch_ready_o = saq_alloc_v & sdq_alloc_v;
    assign sq_dispatch_id_o    = saq_alloc_id;

    // Store commit requires both SAQ and SDQ to be ready
    assign sq_commit_v_o  = saq_commit_v & sdq_commit_v;
    assign sq_commit_id_o = saq_commit_id;

    bsg_store_data_queue #(
      .entries_p(sq_entries_p)
     ,.data_width_p(data_width_p)
    ) sdq (
      .clk_i(clk_i), .reset_i(reset_i)
     ,.alloc_v_o(sdq_alloc_v)
     ,.alloc_id_o(sdq_alloc_id)
     ,.alloc_yumi_i(sq_dispatch_fire)
     ,.data_v_i(sq_data_v_i)
     ,.data_id_i(sq_data_id_i)
     ,.data_i(sq_data_i)
     ,.byte_mask_i(sq_data_byte_mask_i)
     ,.commit_v_o(sdq_commit_v)
     ,.commit_id_o()
     ,.commit_data_o(sq_commit_data_o)
     ,.commit_byte_mask_o(sq_commit_byte_mask_o)
     ,.commit_yumi_i(sq_commit_yumi_i)
     ,.data_valid_o(sdq_data_valid)
     ,.data_array_o(sdq_data_array)
    );

    // --- Forwarding logic: SAQ CAM match + SDQ data ---
    wire [sq_entries_p-1:0] fwd_candidates = saq_cam_match
                                            & saq_addr_valid
                                            & sdq_data_valid;

    wire [sq_id_width_lp-1:0] sq_head = saq_commit_id;

    logic [sq_entries_p-1:0] sq_rotated;
    assign sq_rotated = (fwd_candidates >> sq_head)
                      | (fwd_candidates << (sq_entries_p - sq_head));

    logic [sq_id_width_lp-1:0] youngest_rot_idx;

    bsg_priority_encode #(
      .width_p(sq_entries_p), .lo_to_hi_p(0)
    ) fwd_pri (
      .i(sq_rotated), .addr_o(youngest_rot_idx), .v_o(fwd_hit_raw)
    );

    wire [sq_id_width_lp-1:0] actual_bit =
      sq_id_width_lp'(sq_entries_p - 1) - youngest_rot_idx;
    wire [sq_id_width_lp-1:0] fwd_store_id =
      (actual_bit + sq_head) % sq_entries_p;

    logic [sq_entries_p-1:0] fwd_onehot;
    bsg_decode_with_v #(.num_out_p(sq_entries_p)) fwd_dec (
      .i(fwd_store_id), .v_i(fwd_hit_raw), .o(fwd_onehot)
    );

    bsg_mux_one_hot #(
      .width_p(data_width_p), .els_p(sq_entries_p)
    ) fwd_mux (
      .data_i(sdq_data_array), .sel_one_hot_i(fwd_onehot), .data_o(fwd_data_muxed)
    );

  end else begin : no_sdq
    // No SDQ: address-only store queue (e.g., for address-only disambiguation)
    assign sq_dispatch_ready_o = saq_alloc_v;
    assign sq_dispatch_id_o    = saq_alloc_id;
    assign sq_commit_v_o       = saq_commit_v;
    assign sq_commit_id_o      = saq_commit_id;
    assign sq_commit_data_o    = '0;
    assign sq_commit_byte_mask_o = '0;
    assign sdq_data_valid      = '0;
    assign sdq_data_array      = '0;
    assign fwd_data_muxed      = '0;
    assign fwd_hit_raw         = 1'b0;
  end

  assign fwd_v_o     = fwd_check_v & fwd_hit_raw;
  assign fwd_lq_id_o = fwd_check_lq_id;
  assign fwd_data_o  = fwd_data_muxed;

  // -------------------------------------------------------
  // Load Queue (LQ)
  // -------------------------------------------------------
  bsg_load_queue #(
    .entries_p(lq_entries_p)
   ,.addr_width_p(addr_width_p)
   ,.data_width_p(data_width_p)
  ) lq (
    .clk_i(clk_i), .reset_i(reset_i)
   ,.alloc_v_o(lq_dispatch_ready_o)
   ,.alloc_id_o(lq_dispatch_id_o)
   ,.alloc_yumi_i(lq_dispatch_v_i & lq_dispatch_ready_o)
   ,.addr_v_i(lq_exe_v_i)
   ,.addr_id_i(lq_exe_id_i)
   ,.addr_i(lq_exe_addr_i)
   ,.cache_req_v_o(lq_cache_req_v_o)
   ,.cache_req_addr_o(lq_cache_req_addr_o)
   ,.cache_req_id_o(lq_cache_req_id_o)
   ,.cache_req_yumi_i(lq_cache_req_yumi_i)
   ,.cache_resp_v_i(lq_cache_resp_v_i)
   ,.cache_resp_id_i(lq_cache_resp_id_i)
   ,.cache_resp_data_i(lq_cache_resp_data_i)
   ,.fwd_v_i(fwd_v_o)
   ,.fwd_id_i(fwd_lq_id_o)
   ,.fwd_data_i(fwd_data_o)
   ,.commit_v_o(lq_commit_v_o)
   ,.commit_id_o(lq_commit_id_o)
   ,.commit_data_o(lq_commit_data_o)
   ,.commit_yumi_i(lq_commit_yumi_i)
  );

endmodule

`BSG_ABSTRACT_MODULE(bsg_lsq_split3)
