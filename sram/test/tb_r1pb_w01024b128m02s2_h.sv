`timescale 1ns/1ps

module testbench;

  localparam DEPTH  = 1024;
  localparam WIDTH  = 128;
  localparam ADDR_W = 10;
  localparam HAS_BW = 0;

  logic clk;
  logic cen;
  logic rdwen;
  logic [ADDR_W-1:0] a;
  logic [WIDTH-1:0] d;
  logic [WIDTH-1:0] bw;
  logic [WIDTH-1:0] q;

  MBH_ZSNL_IN12LP_R1PB_W01024B128M02S2_H sram (
    .clk(clk)
    ,.cen(cen)
    ,.rdwen(rdwen)
    ,.a(a)
    ,.d(d)
    ,.q(q)
  );

  `include "sram_test_core.svh"

endmodule
