/**
 *  bsg_mem_1rw_sync_mask_write_bit.sv — SRAM technology wrapper
 *
 *  Drop-in replacement for behavioral bsg_mem_1rw_sync_mask_write_bit.
 *  Instantiates physical SRAM macros (MBH_ZSNL_IN12LP_*) based on
 *  (els_p, width_p) parameters.
 *
 *  Supported configurations:
 *    L1  tag_mem:  256 × 112 → 1 × R1PB_W00256B112M02S1_HB
 *    L1  stat_mem: 256 × 7   → 1 × R1PB_W00256B007M02S1_HB
 *    L2  tag_mem:  1024 × 208 → 2 × S1PB_W01024B104M04S2_HB
 *    L2  stat_mem: 1024 × 15  → 1 × R1PB_W01024B015M04S1_HB
 *    L3  tag_mem:  4096 × 384 → 2 × S1PB_W04096B192M04S4_HB
 *    L3  stat_mem: 4096 × 31  → 1 × S1PB_W04096B032M04S4_HB (pad to 32)
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
  // L1 tag_mem: 256 × 112 → 1 × R1PB_W00256B112M02S1_HB
  // -------------------------------------------------------
  if (els_p == 256 && width_p == 112) begin : cfg

    MBH_ZSNL_IN12LP_R1PB_W00256B112M02S1_HB sram (
      .clk(clk_i), .cen(cen), .rdwen(rdwen),
      .a(addr_i),
      .d(data_i),
      .bw(w_mask_i),
      .q(data_o)
    );

  // -------------------------------------------------------
  // L1 stat_mem: 256 × 7 → 1 × R1PB_W00256B007M02S1_HB
  // -------------------------------------------------------
  end else if (els_p == 256 && width_p == 7) begin : cfg

    MBH_ZSNL_IN12LP_R1PB_W00256B007M02S1_HB sram (
      .clk(clk_i), .cen(cen), .rdwen(rdwen),
      .a(addr_i),
      .d(data_i),
      .bw(w_mask_i),
      .q(data_o)
    );

  // -------------------------------------------------------
  // L2/L2_SP tag_mem: 1024 × 208 → 2 × S1PB_W01024B104M04S2_HB
  // -------------------------------------------------------
  end else if (els_p == 1024 && width_p == 208) begin : cfg

    for (genvar s = 0; s < 2; s++) begin : slice
      MBH_ZSNL_IN12LP_S1PB_W01024B104M04S2_HB sram (
        .clk(clk_i), .cen(cen), .rdwen(rdwen),
        .a(addr_i),
        .d(data_i[s*104+:104]),
        .bw(w_mask_i[s*104+:104]),
        .q(data_o[s*104+:104])
      );
    end

  // -------------------------------------------------------
  // L2/L2_SP stat_mem: 1024 × 15 → 1 × R1PB_W01024B015M04S1_HB
  // -------------------------------------------------------
  end else if (els_p == 1024 && width_p == 15) begin : cfg

    MBH_ZSNL_IN12LP_R1PB_W01024B015M04S1_HB sram (
      .clk(clk_i), .cen(cen), .rdwen(rdwen),
      .a(addr_i),
      .d(data_i),
      .bw(w_mask_i),
      .q(data_o)
    );

  // -------------------------------------------------------
  // L3 tag_mem: 4096 × 384 → 2 × S1PB_W04096B192M04S4_HB
  // -------------------------------------------------------
  end else if (els_p == 4096 && width_p == 384) begin : cfg

    for (genvar s = 0; s < 2; s++) begin : slice
      MBH_ZSNL_IN12LP_S1PB_W04096B192M04S4_HB sram (
        .clk(clk_i), .cen(cen), .rdwen(rdwen),
        .a(addr_i),
        .d(data_i[s*192+:192]),
        .bw(w_mask_i[s*192+:192]),
        .q(data_o[s*192+:192])
      );
    end

  // -------------------------------------------------------
  // L3 stat_mem: 4096 × 31 → 1 × S1PB_W04096B032M04S4_HB (pad to 32)
  // -------------------------------------------------------
  end else if (els_p == 4096 && width_p == 31) begin : cfg

    wire [31:0] sram_d  = {1'b0, data_i};
    wire [31:0] sram_bw = {1'b0, w_mask_i};
    wire [31:0] sram_q;

    MBH_ZSNL_IN12LP_S1PB_W04096B032M04S4_HB sram (
      .clk(clk_i), .cen(cen), .rdwen(rdwen),
      .a(addr_i),
      .d(sram_d),
      .bw(sram_bw),
      .q(sram_q)
    );

    assign data_o = sram_q[width_p-1:0];

  // -------------------------------------------------------
  // Unsupported configuration — compile-time error
  // -------------------------------------------------------
  end else begin : cfg
    initial begin
      $fatal(1, "bsg_mem_1rw_sync_mask_write_bit: unsupported (els_p=%0d, width_p=%0d)", els_p, width_p);
    end
  end

endmodule

`BSG_ABSTRACT_MODULE(bsg_mem_1rw_sync_mask_write_bit)
