/**
 *  bsg_cache_l2_spm.sv
 *
 *  L2 cache/scratchpad top module.
 *  Wraps bsg_cache_sp with L2 parameters (512KB, 8-way, 1024 sets, 64B line).
 *  Each of the 8 data SRAM banks (64KB each) can independently switch
 *  between cache mode and scratchpad mode.
 */

`include "bsg_defines.sv"
`include "bsg_cache.svh"

module bsg_cache_l2_spm
  import bsg_cache_pkg::*;
  #(parameter addr_width_p            = 40
   ,parameter data_width_p            = 64
   ,parameter block_size_in_words_p   = 8
   ,parameter sets_p                  = 1024
   ,parameter ways_p                  = 8
   ,parameter word_tracking_p         = 0
   ,parameter [31:0] amo_support_p    = (1 << e_cache_amo_swap)
                                      | (1 << e_cache_amo_or)
   ,parameter dma_data_width_p        = data_width_p

   // derived
   ,localparam bsg_cache_pkt_width_lp     = `bsg_cache_pkt_width(addr_width_p, data_width_p)
   ,localparam bsg_cache_dma_pkt_width_lp = `bsg_cache_dma_pkt_width(addr_width_p, block_size_in_words_p)
   ,localparam sp_addr_width_lp           = `BSG_SAFE_CLOG2(sets_p * block_size_in_words_p
                                              * data_width_p / dma_data_width_p)
   ,localparam sp_data_width_lp           = dma_data_width_p
   ,localparam sp_mask_width_lp           = (dma_data_width_p >> 3)
  )
  (
    input                                            clk_i
   ,input                                            reset_i

   // ---- cache packet interface ----
   ,input  [bsg_cache_pkt_width_lp-1:0]              cache_pkt_i
   ,input                                            v_i
   ,output logic                                     yumi_o

   ,output logic [data_width_p-1:0]                  data_o
   ,output logic                                     v_o
   ,input                                            yumi_i

   // ---- DMA interface ----
   ,output logic [bsg_cache_dma_pkt_width_lp-1:0]    dma_pkt_o
   ,output logic                                     dma_pkt_v_o
   ,input                                            dma_pkt_yumi_i

   ,input  [dma_data_width_p-1:0]                    dma_data_i
   ,input                                            dma_data_v_i
   ,output logic                                     dma_data_ready_and_o

   ,output logic [dma_data_width_p-1:0]              dma_data_o
   ,output logic                                     dma_data_v_o
   ,input                                            dma_data_yumi_i

   // ---- per-way scratchpad interface ----
   ,input  [ways_p-1:0]                              sp_en_i
   ,input  [ways_p-1:0]                              sp_v_i
   ,input  [ways_p-1:0]                              sp_w_i
   ,input  [ways_p-1:0][sp_addr_width_lp-1:0]        sp_addr_i
   ,input  [ways_p-1:0][sp_data_width_lp-1:0]        sp_data_i
   ,input  [ways_p-1:0][sp_mask_width_lp-1:0]        sp_w_mask_i
   ,output [ways_p-1:0][sp_data_width_lp-1:0]        sp_data_o
  );

  bsg_cache_sp #(
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

   ,.v_we_o()

   ,.sp_en_i(sp_en_i)
   ,.sp_v_i(sp_v_i)
   ,.sp_w_i(sp_w_i)
   ,.sp_addr_i(sp_addr_i)
   ,.sp_data_i(sp_data_i)
   ,.sp_w_mask_i(sp_w_mask_i)
   ,.sp_data_o(sp_data_o)
  );

endmodule
