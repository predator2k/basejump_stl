`timescale 1ns/1ps

module testbench;

  localparam DEPTH  = 8192;
  localparam WIDTH  = 128;
  localparam ADDR_W = 13;
  localparam HAS_BW = 1;

  logic clk;
  logic cen;
  logic rdwen;
  logic [ADDR_W-1:0] a;
  logic [WIDTH-1:0] d;
  logic [WIDTH-1:0] bw;
  logic [WIDTH-1:0] q;

  MBH_ZSNL_IN12LP_S1PB_W08192B128M04S8_HB sram (
    .clk(clk)
    ,.cen(cen)
    ,.rdwen(rdwen)
    ,.a(a)
    ,.d(d)
    ,.bw(bw)
    ,.q(q)
  );

  `include "sram_test_core.svh"

endmodule
