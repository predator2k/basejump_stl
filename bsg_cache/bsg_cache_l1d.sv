`include "bsg_defines.sv"
`include "bsg_cache.svh"

module bsg_cache_l1d
  import bsg_cache_pkg::*;
  #(parameter addr_width_p = 48
    ,parameter data_width_p = 64
    // L1D: 64KB, 4-way (serial tag-data), 64B cacheline
    // sets = 64KB / (4 * 64B) = 256
    ,parameter block_size_in_words_p = 8  // 64B / 8B = 8 words
    ,parameter sets_p = 256
    ,parameter ways_p = 4
    ,parameter word_tracking_p = 0
    ,parameter [31:0] amo_support_p = (1 << e_cache_amo_swap)
                                      | (1 << e_cache_amo_or)
    ,parameter dma_data_width_p = data_width_p

    ,localparam bsg_cache_pkt_width_lp = `bsg_cache_pkt_width(addr_width_p, data_width_p)
    ,localparam bsg_cache_dma_pkt_width_lp = `bsg_cache_dma_pkt_width(addr_width_p, block_size_in_words_p)
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
  );

  bsg_cache_serial #(
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
  );

endmodule
