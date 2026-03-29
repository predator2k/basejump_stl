/**
 *  bsg_cache_sp_data_mem.sv
 *
 *  Per-way banked data memory with independent scratchpad switching.
 *  Drop-in replacement for the monolithic data_mem in bsg_cache.
 *
 *  Each way has its own SRAM bank. When sp_en_i[i] is asserted,
 *  bank i is controlled by the scratchpad interface (sp_*) instead
 *  of the cache pipeline.
 */

`include "bsg_defines.sv"

module bsg_cache_sp_data_mem
  #(parameter `BSG_INV_PARAM(ways_p)
   ,parameter `BSG_INV_PARAM(bank_width_p)       // dma_data_width_p (bits per way)
   ,parameter `BSG_INV_PARAM(els_p)               // data_mem_els = sets * burst_len
   ,parameter latch_last_read_p = 1
   ,parameter addr_width_lp = `BSG_SAFE_CLOG2(els_p)
   ,parameter bank_mask_width_lp = (bank_width_p >> 3)
  )
  (
    input                                              clk_i
   ,input                                              reset_i

   // cache-side interface (same logical shape as original monolithic data_mem)
   ,input                                              cache_v_i
   ,input                                              cache_w_i
   ,input  [addr_width_lp-1:0]                         cache_addr_i
   ,input  [ways_p-1:0][bank_width_p-1:0]              cache_data_i
   ,input  [ways_p-1:0][bank_mask_width_lp-1:0]        cache_w_mask_i
   ,output [ways_p-1:0][bank_width_p-1:0]              cache_data_o

   // per-way scratchpad enable
   ,input  [ways_p-1:0]                                sp_en_i

   // scratchpad interface (directly exposed per bank)
   ,input  [ways_p-1:0]                                sp_v_i
   ,input  [ways_p-1:0]                                sp_w_i
   ,input  [ways_p-1:0][addr_width_lp-1:0]             sp_addr_i
   ,input  [ways_p-1:0][bank_width_p-1:0]              sp_data_i
   ,input  [ways_p-1:0][bank_mask_width_lp-1:0]        sp_w_mask_i
   ,output [ways_p-1:0][bank_width_p-1:0]              sp_data_o
  );

  for (genvar i = 0; i < ways_p; i++) begin : bank

    logic                          v_li;
    logic                          w_li;
    logic [addr_width_lp-1:0]      addr_li;
    logic [bank_width_p-1:0]       data_li;
    logic [bank_mask_width_lp-1:0] w_mask_li;
    logic [bank_width_p-1:0]       data_lo;

    // mux between cache control and scratchpad control
    assign v_li      = sp_en_i[i] ? sp_v_i[i]      : cache_v_i;
    assign w_li      = sp_en_i[i] ? sp_w_i[i]      : cache_w_i;
    assign addr_li   = sp_en_i[i] ? sp_addr_i[i]   : cache_addr_i;
    assign data_li   = sp_en_i[i] ? sp_data_i[i]   : cache_data_i[i];
    assign w_mask_li = sp_en_i[i] ? sp_w_mask_i[i] : cache_w_mask_i[i];

    bsg_mem_1rw_sync_mask_write_byte #(
      .data_width_p(bank_width_p)
     ,.els_p(els_p)
     ,.latch_last_read_p(latch_last_read_p)
    ) mem (
      .clk_i(clk_i)
     ,.reset_i(reset_i)
     ,.v_i(v_li)
     ,.w_i(w_li)
     ,.addr_i(addr_li)
     ,.data_i(data_li)
     ,.write_mask_i(w_mask_li)
     ,.data_o(data_lo)
    );

    // both cache and scratchpad sides can read the same SRAM output
    assign cache_data_o[i] = data_lo;
    assign sp_data_o[i]    = data_lo;

  end

endmodule

`BSG_ABSTRACT_MODULE(bsg_cache_sp_data_mem)
