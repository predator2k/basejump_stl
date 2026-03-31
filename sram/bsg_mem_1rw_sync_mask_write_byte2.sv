/**
 *  bsg_mem_1rw_sync_mask_write_byte.sv — SRAM technology wrapper (S1DB/R1DB)
 *
 *  Drop-in replacement for behavioral bsg_mem_1rw_sync_mask_write_byte.
 *  Instantiates physical SRAM macros (MBH_ZSNL_IN12LP_*DB_*) based on
 *  (els_p, data_width_p) parameters.
 *
 *  Supported configurations:
 *    L1I  data_mem:   2048 × 256  → 1 × S1DB_W02048B256M04S2_LB
 *    L1D  data_mem:   2048 × 64   → 1 × S1DB_W02048B064M04S2_LB  (×4 banks)
 *    L2   data_mem:   8192 × 64   → 1 × S1DB_W08192B064M04S8_LB  (×8 banks)
 *    L3   data_mem:  32768 × 128  → 4 × S1DB_W08192B128M04S8_LB  (×8 banks, 4 depth)
 *    L2SP data_mem:   8192 × 64   → 1 × S1DB_W08192B064M04S8_LB  (×8 banks)
 */

`include "bsg_defines.sv"

module bsg_mem_1rw_sync_mask_write_byte
  #(parameter `BSG_INV_PARAM(els_p)
   ,parameter `BSG_INV_PARAM(data_width_p)
   ,parameter latch_last_read_p = 0
   ,parameter enable_clock_gating_p = 0
   ,parameter addr_width_lp = `BSG_SAFE_CLOG2(els_p)
   ,parameter write_mask_width_lp = data_width_p>>3
  )
  (input                             clk_i
  ,input                             reset_i
  ,input                             v_i
  ,input                             w_i
  ,input  [addr_width_lp-1:0]        addr_i
  ,input  [data_width_p-1:0]         data_i
  ,input  [write_mask_width_lp-1:0]  write_mask_i
  ,output logic [data_width_p-1:0]   data_o
  );

  // Expand byte mask to bit mask
  logic [data_width_p-1:0] bw;
  for (genvar i = 0; i < write_mask_width_lp; i++) begin : mask_expand
    assign bw[i*8+:8] = {8{write_mask_i[i]}};
  end

  wire cen   = ~v_i;
  wire rdwen = ~w_i;

  // -------------------------------------------------------
  // L1I data_mem: 2048 × 256 → 1 × S1DB_W02048B256
  // -------------------------------------------------------
  if (els_p == 2048 && data_width_p == 256) begin : cfg

    MBH_ZSNL_IN12LP_S1DB_W02048B256M04S2_LB sram (
      .clk(clk_i), .cen(cen), .rdwen(rdwen),
      .a(addr_i), .d(data_i), .bw(bw), .q(data_o)
    );

  // -------------------------------------------------------
  // L1D data_mem per-way: 2048 × 64 → 1 × S1DB_W02048B064
  // -------------------------------------------------------
  end else if (els_p == 2048 && data_width_p == 64) begin : cfg

    MBH_ZSNL_IN12LP_S1DB_W02048B064M04S2_LB sram (
      .clk(clk_i), .cen(cen), .rdwen(rdwen),
      .a(addr_i), .d(data_i), .bw(bw), .q(data_o)
    );

  // -------------------------------------------------------
  // L2/L2SP data_mem per-way: 8192 × 64 → 1 × S1DB_W08192B064
  // -------------------------------------------------------
  end else if (els_p == 8192 && data_width_p == 64) begin : cfg

    MBH_ZSNL_IN12LP_S1DB_W08192B064M04S8_LB sram (
      .clk(clk_i), .cen(cen), .rdwen(rdwen),
      .a(addr_i), .d(data_i), .bw(bw), .q(data_o)
    );

  // -------------------------------------------------------
  // L3 data_mem per-bank: 32768 × 128 → 4 depth × S1DB_W08192B128
  // -------------------------------------------------------
  end else if (els_p == 32768 && data_width_p == 128) begin : cfg

    localparam DEPTH_SLICES = 4;
    localparam SRAM_ADDR_W  = 13; // log2(8192)
    localparam DSEL_W       = 2;  // log2(4)

    wire [DSEL_W-1:0]       depth_sel  = addr_i[addr_width_lp-1-:DSEL_W];
    wire [SRAM_ADDR_W-1:0]  sram_addr  = addr_i[SRAM_ADDR_W-1:0];

    wire [data_width_p-1:0] slice_q [DEPTH_SLICES];

    for (genvar d = 0; d < DEPTH_SLICES; d++) begin : depth
      wire slice_cen = cen | (depth_sel != d[DSEL_W-1:0]);

      MBH_ZSNL_IN12LP_S1DB_W08192B128M04S8_LB sram (
        .clk(clk_i), .cen(slice_cen), .rdwen(rdwen),
        .a(sram_addr), .d(data_i), .bw(bw), .q(slice_q[d])
      );
    end

    logic [DSEL_W-1:0] depth_sel_r;
    always_ff @(posedge clk_i) begin
      if (v_i & ~w_i)
        depth_sel_r <= depth_sel;
    end

    assign data_o = slice_q[depth_sel_r];

  // -------------------------------------------------------
  // Unsupported configuration
  // -------------------------------------------------------
  end else begin : cfg
    initial begin
      $fatal(1, "bsg_mem_1rw_sync_mask_write_byte: unsupported (els_p=%0d, data_width_p=%0d)", els_p, data_width_p);
    end
  end

endmodule

`BSG_ABSTRACT_MODULE(bsg_mem_1rw_sync_mask_write_byte)
