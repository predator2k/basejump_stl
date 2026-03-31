/**
 *  bsg_cache_serial_data_mem.sv
 *
 *  Per-way (or merged-way) banked data memory with selective bank activation.
 *  Used by bsg_cache_serial for tag-data serial pipeline.
 *
 *  bank_factor_p controls bank merging:
 *    bank_factor_p=1: one SRAM per way (L1D, L2)
 *    bank_factor_p=2: two ways share one wider SRAM (L3 with 16 ways → 8 banks)
 *
 *  Only the selected bank is activated per cycle, saving dynamic power.
 */

`include "bsg_defines.sv"

module bsg_cache_serial_data_mem
  #(parameter `BSG_INV_PARAM(ways_p)
   ,parameter `BSG_INV_PARAM(bank_width_p)       // dma_data_width_p (bits per way)
   ,parameter `BSG_INV_PARAM(els_p)               // sets * burst_len
   ,parameter bank_factor_p = 1                    // ways per physical bank
   ,parameter latch_last_read_p = 1
   ,localparam num_banks_lp = ways_p / bank_factor_p
   ,localparam merged_width_lp = bank_width_p * bank_factor_p
   ,localparam addr_width_lp = `BSG_SAFE_CLOG2(els_p)
   ,localparam bank_mask_width_lp = (bank_width_p >> 3)
   ,localparam merged_mask_width_lp = (merged_width_lp >> 3)
   ,localparam lg_ways_lp = `BSG_SAFE_CLOG2(ways_p)
   ,localparam lg_bank_factor_lp = `BSG_SAFE_CLOG2(bank_factor_p)
  )
  (
    input                                              clk_i
   ,input                                              reset_i

   // --- Pipeline read (from TM stage, only 1 bank active) ---
   ,input                                              pipe_v_i
   ,input  [lg_ways_lp-1:0]                            pipe_way_id_i     // which way to read
   ,input  [addr_width_lp-1:0]                         pipe_addr_i
   ,output [bank_width_p-1:0]                          pipe_data_o       // single-way output

   // --- Write port (sbuf drain / DMA fill, per-way) ---
   ,input                                              w_v_i
   ,input  [lg_ways_lp-1:0]                            w_way_id_i
   ,input  [addr_width_lp-1:0]                         w_addr_i
   ,input  [bank_width_p-1:0]                          w_data_i
   ,input  [bank_mask_width_lp-1:0]                    w_mask_i

   // --- DMA evict read (from specific way) ---
   ,input                                              dma_rd_v_i
   ,input  [lg_ways_lp-1:0]                            dma_rd_way_id_i
   ,input  [addr_width_lp-1:0]                         dma_rd_addr_i
   ,output [bank_width_p-1:0]                          dma_rd_data_o
  );

  // -------------------------------------------------------
  // Bank index and sub-way extraction
  // -------------------------------------------------------
  wire [$clog2(num_banks_lp)-1:0] pipe_bank_idx =
    (bank_factor_p == 1) ? pipe_way_id_i : pipe_way_id_i[lg_ways_lp-1:lg_bank_factor_lp];
  wire [$clog2(num_banks_lp)-1:0] w_bank_idx =
    (bank_factor_p == 1) ? w_way_id_i : w_way_id_i[lg_ways_lp-1:lg_bank_factor_lp];
  wire [$clog2(num_banks_lp)-1:0] dma_rd_bank_idx =
    (bank_factor_p == 1) ? dma_rd_way_id_i : dma_rd_way_id_i[lg_ways_lp-1:lg_bank_factor_lp];

  // Sub-way index within merged bank (only used when bank_factor_p > 1)
  logic [lg_bank_factor_lp-1:0] pipe_sub_way_r;
  if (bank_factor_p > 1) begin : sub_way_gen
    always_ff @(posedge clk_i) begin
      if (pipe_v_i)
        pipe_sub_way_r <= pipe_way_id_i[lg_bank_factor_lp-1:0];
    end
  end else begin : no_sub_way
    assign pipe_sub_way_r = '0;
  end

  logic [lg_bank_factor_lp-1:0] dma_rd_sub_way_r;
  if (bank_factor_p > 1) begin : dma_sub_way_gen
    always_ff @(posedge clk_i) begin
      if (dma_rd_v_i)
        dma_rd_sub_way_r <= dma_rd_way_id_i[lg_bank_factor_lp-1:0];
    end
  end else begin : no_dma_sub_way
    assign dma_rd_sub_way_r = '0;
  end

  // -------------------------------------------------------
  // Per-bank SRAM instantiation
  // -------------------------------------------------------
  logic [num_banks_lp-1:0][merged_width_lp-1:0] bank_data_lo;

  for (genvar i = 0; i < num_banks_lp; i++) begin : bank

    // Arbitrate access: write > dma_rd > pipe_rd
    wire this_pipe_v   = pipe_v_i   & (pipe_bank_idx   == i[$clog2(num_banks_lp)-1:0]);
    wire this_w_v      = w_v_i      & (w_bank_idx      == i[$clog2(num_banks_lp)-1:0]);
    wire this_dma_rd_v = dma_rd_v_i & (dma_rd_bank_idx == i[$clog2(num_banks_lp)-1:0]);

    wire mem_v = this_w_v | this_dma_rd_v | this_pipe_v;
    wire mem_w = this_w_v;

    wire [addr_width_lp-1:0] mem_addr =
      this_w_v      ? w_addr_i :
      this_dma_rd_v ? dma_rd_addr_i :
                      pipe_addr_i;

    // Write data: expand to merged width, place in correct sub-way slot
    logic [merged_width_lp-1:0]      mem_data;
    logic [merged_mask_width_lp-1:0] mem_mask;

    if (bank_factor_p == 1) begin : direct
      assign mem_data = w_data_i;
      assign mem_mask = w_mask_i;
    end else begin : merged
      // Place write data at the correct sub-way position
      wire [lg_bank_factor_lp-1:0] w_sub_way = w_way_id_i[lg_bank_factor_lp-1:0];
      always_comb begin
        mem_data = '0;
        mem_mask = '0;
        for (int s = 0; s < bank_factor_p; s++) begin
          if (s[lg_bank_factor_lp-1:0] == w_sub_way) begin
            mem_data[s*bank_width_p+:bank_width_p] = w_data_i;
            mem_mask[s*bank_mask_width_lp+:bank_mask_width_lp] = w_mask_i;
          end
        end
      end
    end

    bsg_mem_1rw_sync_mask_write_byte #(
      .data_width_p(merged_width_lp)
     ,.els_p(els_p)
     ,.latch_last_read_p(latch_last_read_p)
    ) mem (
      .clk_i(clk_i)
     ,.reset_i(reset_i)
     ,.v_i(mem_v)
     ,.w_i(mem_w)
     ,.addr_i(mem_addr)
     ,.data_i(mem_data)
     ,.write_mask_i(mem_mask)
     ,.data_o(bank_data_lo[i])
    );
  end

  // -------------------------------------------------------
  // Output mux: extract single-way data from (possibly merged) bank output
  // Latch the bank index when pipe read fires, so output stays stable
  // even after pipe_way_id_i changes (TM advances to next instruction).
  // -------------------------------------------------------
  logic [$clog2(num_banks_lp)-1:0] pipe_bank_idx_r;
  always_ff @(posedge clk_i) begin
    if (pipe_v_i)
      pipe_bank_idx_r <= pipe_bank_idx;
  end

  // Pipeline read output
  wire [merged_width_lp-1:0] pipe_bank_out = bank_data_lo[pipe_bank_idx_r];
  if (bank_factor_p == 1) begin : pipe_out_direct
    assign pipe_data_o = pipe_bank_out[bank_width_p-1:0];
  end else begin : pipe_out_mux
    bsg_mux #(
      .width_p(bank_width_p), .els_p(bank_factor_p)
    ) pipe_sub_mux (
      .data_i(pipe_bank_out), .sel_i(pipe_sub_way_r), .data_o(pipe_data_o)
    );
  end

  // DMA read output (latch bank index when DMA read fires)
  logic [$clog2(num_banks_lp)-1:0] dma_rd_bank_idx_r;
  always_ff @(posedge clk_i) begin
    if (dma_rd_v_i)
      dma_rd_bank_idx_r <= dma_rd_bank_idx;
  end
  wire [merged_width_lp-1:0] dma_bank_out = bank_data_lo[dma_rd_bank_idx_r];
  if (bank_factor_p == 1) begin : dma_out_direct
    assign dma_rd_data_o = dma_bank_out[bank_width_p-1:0];
  end else begin : dma_out_mux
    bsg_mux #(
      .width_p(bank_width_p), .els_p(bank_factor_p)
    ) dma_sub_mux (
      .data_i(dma_bank_out), .sel_i(dma_rd_sub_way_r), .data_o(dma_rd_data_o)
    );
  end

endmodule

`BSG_ABSTRACT_MODULE(bsg_cache_serial_data_mem)
