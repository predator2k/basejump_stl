/**
 *  bsg_mem_1rw_sync_mask_write_bit.sv — SRAM technology wrapper (S1DB/R1DB)
 *
 *  Drop-in replacement for behavioral bsg_mem_1rw_sync_mask_write_bit.
 *
 *  Supported configurations:
 *    L1I/L1D tag_mem:   256 × 144  → 1 × R1DB_W00256B144M02S1_LB
 *    L1I/L1D stat_mem:  256 × 7    → 1 × R1DB_W00256B008M02S1_LB (pad to 8)
 *    L2/L2SP tag_mem:  1024 × 272  → 2 × S1DB_W01024B136M04S2_LB
 *    L2/L2SP stat_mem: 1024 × 15   → 1 × R1DB_W01024B015M02S2_LB
 *    L3      tag_mem:  4096 × 512  → 2 × S1DB_W04096B256M04S4_LB
 *    L3      stat_mem: 4096 × 31   → 1 × S1DB_W04096B032M04S4_LB (pad to 32)
 */

`include "bsg_defines.sv"

module bsg_mem_1rw_sync_mask_write_bit
  #(parameter `BSG_INV_PARAM(width_p)
   ,parameter `BSG_INV_PARAM(els_p)
   ,parameter latch_last_read_p = 0
   ,parameter enable_clock_gating_p = 0
   ,parameter addr_width_lp = `BSG_SAFE_CLOG2(els_p)
  )
  (input                          clk_i
  ,input                          reset_i
  ,input                          v_i
  ,input                          w_i
  ,input  [addr_width_lp-1:0]    addr_i
  ,input  [width_p-1:0]          data_i
  ,input  [width_p-1:0]          w_mask_i
  ,output logic [width_p-1:0]    data_o
  );

  wire cen   = ~v_i;
  wire rdwen = ~w_i;

  // -------------------------------------------------------
  // L1I/L1D tag_mem: 256 × 144 → R1DB_W00256B144
  // -------------------------------------------------------
  if (els_p == 256 && width_p == 144) begin : cfg

    MBH_ZSNL_IN12LP_R1DB_W00256B144M02S1_LB sram (
      .clk(clk_i), .cen(cen), .rdwen(rdwen),
      .a(addr_i), .d(data_i), .bw(w_mask_i), .q(data_o)
    );

  // -------------------------------------------------------
  // L1I/L1D stat_mem: 256 × 7 → R1DB_W00256B008 (pad to 8)
  // -------------------------------------------------------
  end else if (els_p == 256 && width_p == 7) begin : cfg

    wire [7:0] sram_d  = {1'b0, data_i};
    wire [7:0] sram_bw = {1'b0, w_mask_i};
    wire [7:0] sram_q;

    MBH_ZSNL_IN12LP_R1DB_W00256B008M02S1_LB sram (
      .clk(clk_i), .cen(cen), .rdwen(rdwen),
      .a(addr_i), .d(sram_d), .bw(sram_bw), .q(sram_q)
    );

    assign data_o = sram_q[width_p-1:0];

  // -------------------------------------------------------
  // L2/L2SP tag_mem: 1024 × 272 → 2 × S1DB_W01024B136
  // -------------------------------------------------------
  end else if (els_p == 1024 && width_p == 272) begin : cfg

    for (genvar s = 0; s < 2; s++) begin : slice
      MBH_ZSNL_IN12LP_S1DB_W01024B136M04S2_LB sram (
        .clk(clk_i), .cen(cen), .rdwen(rdwen),
        .a(addr_i),
        .d(data_i[s*136+:136]),
        .bw(w_mask_i[s*136+:136]),
        .q(data_o[s*136+:136])
      );
    end

  // -------------------------------------------------------
  // L2/L2SP stat_mem: 1024 × 15 → R1DB_W01024B015
  // -------------------------------------------------------
  end else if (els_p == 1024 && width_p == 15) begin : cfg

    MBH_ZSNL_IN12LP_R1DB_W01024B015M02S2_LB sram (
      .clk(clk_i), .cen(cen), .rdwen(rdwen),
      .a(addr_i), .d(data_i), .bw(w_mask_i), .q(data_o)
    );

  // -------------------------------------------------------
  // L3 tag_mem: 4096 × 512 → 2 × S1DB_W04096B256
  // -------------------------------------------------------
  end else if (els_p == 4096 && width_p == 512) begin : cfg

    for (genvar s = 0; s < 2; s++) begin : slice
      MBH_ZSNL_IN12LP_S1DB_W04096B256M04S4_LB sram (
        .clk(clk_i), .cen(cen), .rdwen(rdwen),
        .a(addr_i),
        .d(data_i[s*256+:256]),
        .bw(w_mask_i[s*256+:256]),
        .q(data_o[s*256+:256])
      );
    end

  // -------------------------------------------------------
  // L3 stat_mem: 4096 × 31 → S1DB_W04096B032 (pad to 32)
  // -------------------------------------------------------
  end else if (els_p == 4096 && width_p == 31) begin : cfg

    wire [31:0] sram_d  = {1'b0, data_i};
    wire [31:0] sram_bw = {1'b0, w_mask_i};
    wire [31:0] sram_q;

    MBH_ZSNL_IN12LP_S1DB_W04096B032M04S4_LB sram (
      .clk(clk_i), .cen(cen), .rdwen(rdwen),
      .a(addr_i), .d(sram_d), .bw(sram_bw), .q(sram_q)
    );

    assign data_o = sram_q[width_p-1:0];

  // -------------------------------------------------------
  // Unsupported
  // -------------------------------------------------------
  end else begin : cfg
    initial begin
      $fatal(1, "bsg_mem_1rw_sync_mask_write_bit: unsupported (els_p=%0d, width_p=%0d)", els_p, width_p);
    end
  end

endmodule

`BSG_ABSTRACT_MODULE(bsg_mem_1rw_sync_mask_write_bit)
