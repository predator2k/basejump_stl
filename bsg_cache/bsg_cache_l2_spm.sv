`include "bsg_defines.sv"
`include "bsg_cache.svh"

module bsg_cache_l2_spm
  import bsg_cache_pkg::*;
  #(parameter addr_width_p = 48
    ,parameter data_width_p = 64
    // L2: 512KB, 8-way, 64B cacheline
    ,parameter block_size_in_words_p = 8
    ,parameter sets_p = 1024
    ,parameter ways_p = 8
    ,parameter word_tracking_p = 0
    ,parameter [31:0] amo_support_p = (1 << e_cache_amo_swap)
                                      | (1 << e_cache_amo_or)
    ,parameter dma_data_width_p = data_width_p

    ,localparam bsg_cache_pkt_width_lp = `bsg_cache_pkt_width(addr_width_p, data_width_p)
    ,localparam bsg_cache_dma_pkt_width_lp = `bsg_cache_dma_pkt_width(addr_width_p, block_size_in_words_p)
    ,localparam data_mem_els_lp = sets_p * block_size_in_words_p * (data_width_p / dma_data_width_p)
    ,localparam lg_data_mem_els_lp = `BSG_SAFE_CLOG2(data_mem_els_lp)
    ,localparam dma_data_mask_width_lp = (dma_data_width_p >> 3)
    ,localparam lg_ways_lp = `BSG_SAFE_CLOG2(ways_p)
  )
  (
    input                                          clk_i
    ,input                                         reset_i

    ,input [bsg_cache_pkt_width_lp-1:0]            cache_pkt_i
    ,input                                         v_i
    ,output logic                                  yumi_o

    ,output logic [data_width_p-1:0]               data_o
    ,output logic                                  v_o
    ,input                                         yumi_i

    ,output logic [bsg_cache_dma_pkt_width_lp-1:0] dma_pkt_o
    ,output logic                                  dma_pkt_v_o
    ,input                                         dma_pkt_yumi_i

    ,input [dma_data_width_p-1:0]                  dma_data_i
    ,input                                         dma_data_v_i
    ,output logic                                  dma_data_ready_and_o

    ,output logic [dma_data_width_p-1:0]           dma_data_o
    ,output logic                                  dma_data_v_o
    ,input                                         dma_data_yumi_i

    ,output logic                                  v_we_o

    // Per-way scratchpad interface
    ,input  [ways_p-1:0]                                   sp_en_i
    ,input  [ways_p-1:0]                                   sp_v_i
    ,input  [ways_p-1:0]                                   sp_w_i
    ,input  [ways_p-1:0][lg_data_mem_els_lp-1:0]           sp_addr_i
    ,input  [ways_p-1:0][dma_data_width_p-1:0]             sp_data_i
    ,input  [ways_p-1:0][dma_data_mask_width_lp-1:0]       sp_w_mask_i
    ,output [ways_p-1:0][dma_data_width_p-1:0]             sp_data_o

    // 8-to-2 MUX: select 2 of 8 SP data outputs to top
    ,input  [lg_ways_lp-1:0]                               sp_mux_sel0_i
    ,input  [lg_ways_lp-1:0]                               sp_mux_sel1_i
    ,output logic [dma_data_width_p-1:0]                    sp_data_muxed0_o
    ,output logic [dma_data_width_p-1:0]                    sp_data_muxed1_o
  );

  // -------------------------------------------------------
  // Cache core (serial tag-data with scratchpad)
  // -------------------------------------------------------
  bsg_cache_serial_sp #(
    .addr_width_p(addr_width_p)
    ,.data_width_p(data_width_p)
    ,.block_size_in_words_p(block_size_in_words_p)
    ,.sets_p(sets_p)
    ,.ways_p(ways_p)
    ,.word_tracking_p(word_tracking_p)
    ,.amo_support_p(amo_support_p)
    ,.dma_data_width_p(dma_data_width_p)
  ) cache (
    .clk_i(clk_i)
    ,.reset_i(reset_i)

    ,.cache_pkt_i(cache_pkt_i)
    ,.v_i(v_i)
    ,.yumi_o(yumi_o)

    ,.data_o(data_o)
    ,.v_o(v_o)
    ,.yumi_i(yumi_i)

    ,.dma_pkt_o(dma_pkt_o)
    ,.dma_pkt_v_o(dma_pkt_v_o)
    ,.dma_pkt_yumi_i(dma_pkt_yumi_i)

    ,.dma_data_i(dma_data_i)
    ,.dma_data_v_i(dma_data_v_i)
    ,.dma_data_ready_and_o(dma_data_ready_and_o)

    ,.dma_data_o(dma_data_o)
    ,.dma_data_v_o(dma_data_v_o)
    ,.dma_data_yumi_i(dma_data_yumi_i)

    ,.v_we_o(v_we_o)

    ,.sp_en_i(sp_en_i)
    ,.sp_v_i(sp_v_i)
    ,.sp_w_i(sp_w_i)
    ,.sp_addr_i(sp_addr_i)
    ,.sp_data_i(sp_data_i)
    ,.sp_w_mask_i(sp_w_mask_i)
    ,.sp_data_o(sp_data_o)
  );

  // -------------------------------------------------------
  // 8-to-2 MUX: independently select 2 of 8 SP data outputs
  // Output registered (1-cycle latency)
  // -------------------------------------------------------
  logic [dma_data_width_p-1:0] sp_data_muxed0_comb;
  logic [dma_data_width_p-1:0] sp_data_muxed1_comb;

  bsg_mux #(
    .width_p(dma_data_width_p)
   ,.els_p(ways_p)
  ) sp_mux0 (
    .data_i(sp_data_o)
   ,.sel_i(sp_mux_sel0_i)
   ,.data_o(sp_data_muxed0_comb)
  );

  bsg_mux #(
    .width_p(dma_data_width_p)
   ,.els_p(ways_p)
  ) sp_mux1 (
    .data_i(sp_data_o)
   ,.sel_i(sp_mux_sel1_i)
   ,.data_o(sp_data_muxed1_comb)
  );

  always_ff @(posedge clk_i) begin
    sp_data_muxed0_o <= sp_data_muxed0_comb;
    sp_data_muxed1_o <= sp_data_muxed1_comb;
  end

endmodule
