`timescale 1ns/1ps

module testbench;

  localparam DEPTH  = 1024;
  localparam WIDTH  = 104;
  localparam ADDR_W = 10;
  localparam HAS_BW = 1;

  logic clk;
  logic cen;
  logic rdwen;
  logic [ADDR_W-1:0] a;
  logic [WIDTH-1:0] d;
  logic [WIDTH-1:0] bw;
  logic [WIDTH-1:0] q;

  MBH_ZSNL_IN12LP_S1PB_W01024B104M04S2_HB sram (
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
