/**
 *  bsg_cache_serial_sp_data_mem.sv
 *
 *  Per-way banked data memory with:
 *  - Selective bank activation (serial tag-data pipeline)
 *  - Per-way scratchpad mode switching (sp_en_i)
 *
 *  When sp_en_i[w]=1, way w's bank is controlled by the SP interface.
 *  When sp_en_i[w]=0, way w's bank is controlled by the cache pipeline
 *  with selective activation (only activated when that way is hit/targeted).
 */

`include "bsg_defines.sv"

module bsg_cache_serial_sp_data_mem
  #(parameter `BSG_INV_PARAM(ways_p)
   ,parameter `BSG_INV_PARAM(bank_width_p)
   ,parameter `BSG_INV_PARAM(els_p)
   ,parameter latch_last_read_p = 1
   ,localparam addr_width_lp = `BSG_SAFE_CLOG2(els_p)
   ,localparam bank_mask_width_lp = (bank_width_p >> 3)
   ,localparam lg_ways_lp = `BSG_SAFE_CLOG2(ways_p)
  )
  (
    input                                              clk_i
   ,input                                              reset_i

   // --- Pipeline read (selective, 1 bank) ---
   ,input                                              pipe_v_i
   ,input  [lg_ways_lp-1:0]                            pipe_way_id_i
   ,input  [addr_width_lp-1:0]                         pipe_addr_i
   ,output [bank_width_p-1:0]                          pipe_data_o

   // --- Write port (sbuf / DMA fill) ---
   ,input                                              w_v_i
   ,input  [lg_ways_lp-1:0]                            w_way_id_i
   ,input  [addr_width_lp-1:0]                         w_addr_i
   ,input  [bank_width_p-1:0]                          w_data_i
   ,input  [bank_mask_width_lp-1:0]                    w_mask_i

   // --- DMA evict read ---
   ,input                                              dma_rd_v_i
   ,input  [lg_ways_lp-1:0]                            dma_rd_way_id_i
   ,input  [addr_width_lp-1:0]                         dma_rd_addr_i
   ,output [bank_width_p-1:0]                          dma_rd_data_o

   // --- Per-way scratchpad enable ---
   ,input  [ways_p-1:0]                                sp_en_i

   // --- Scratchpad interface (per-way) ---
   ,input  [ways_p-1:0]                                sp_v_i
   ,input  [ways_p-1:0]                                sp_w_i
   ,input  [ways_p-1:0][addr_width_lp-1:0]             sp_addr_i
   ,input  [ways_p-1:0][bank_width_p-1:0]              sp_data_i
   ,input  [ways_p-1:0][bank_mask_width_lp-1:0]        sp_w_mask_i
   ,output [ways_p-1:0][bank_width_p-1:0]              sp_data_o
  );

  // -------------------------------------------------------
  // Per-way SRAM banks (bank_factor_p=1 for SP, always 1 way per bank)
  // -------------------------------------------------------
  logic [ways_p-1:0][bank_width_p-1:0] bank_data_lo;

  for (genvar i = 0; i < ways_p; i++) begin : bank

    // --- Cache-side access for this bank ---
    wire this_pipe_v   = pipe_v_i   & (pipe_way_id_i   == lg_ways_lp'(i));
    wire this_w_v      = w_v_i      & (w_way_id_i      == lg_ways_lp'(i));
    wire this_dma_rd_v = dma_rd_v_i & (dma_rd_way_id_i == lg_ways_lp'(i));

    wire cache_v = this_w_v | this_dma_rd_v | this_pipe_v;
    wire cache_w = this_w_v;

    wire [addr_width_lp-1:0] cache_addr =
      this_w_v      ? w_addr_i :
      this_dma_rd_v ? dma_rd_addr_i :
                      pipe_addr_i;

    // --- Mux: SP mode vs cache mode ---
    wire                          mem_v      = sp_en_i[i] ? sp_v_i[i]      : cache_v;
    wire                          mem_w      = sp_en_i[i] ? sp_w_i[i]      : cache_w;
    wire [addr_width_lp-1:0]      mem_addr   = sp_en_i[i] ? sp_addr_i[i]   : cache_addr;
    wire [bank_width_p-1:0]       mem_data   = sp_en_i[i] ? sp_data_i[i]   : w_data_i;
    wire [bank_mask_width_lp-1:0] mem_mask   = sp_en_i[i] ? sp_w_mask_i[i] : w_mask_i;

    bsg_mem_1rw_sync_mask_write_byte #(
      .data_width_p(bank_width_p)
     ,.els_p(els_p)
     ,.latch_last_read_p(latch_last_read_p)
    ) mem (
      .clk_i(clk_i), .reset_i(reset_i)
     ,.v_i(mem_v), .w_i(mem_w)
     ,.addr_i(mem_addr), .data_i(mem_data)
     ,.write_mask_i(mem_mask), .data_o(bank_data_lo[i])
    );

    assign sp_data_o[i] = bank_data_lo[i];
  end

  // --- Pipeline read output: mux the hit bank ---
  assign pipe_data_o = bank_data_lo[pipe_way_id_i];

  // --- DMA read output ---
  assign dma_rd_data_o = bank_data_lo[dma_rd_way_id_i];

endmodule

`BSG_ABSTRACT_MODULE(bsg_cache_serial_sp_data_mem)
