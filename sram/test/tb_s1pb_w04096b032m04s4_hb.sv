`timescale 1ns/1ps

module testbench;

  localparam DEPTH  = 4096;
  localparam WIDTH  = 32;
  localparam ADDR_W = 12;
  localparam HAS_BW = 1;

  logic clk;
  logic cen;
  logic rdwen;
  logic [ADDR_W-1:0] a;
  logic [WIDTH-1:0] d;
  logic [WIDTH-1:0] bw;
  logic [WIDTH-1:0] q;

  MBH_ZSNL_IN12LP_S1PB_W04096B032M04S4_HB sram (
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
