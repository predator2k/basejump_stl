#!/bin/bash
set -euo pipefail

BSG_STL=/home/mhnie/develop/basejump_stl
TB_DIR=$(cd "$(dirname "$0")" && pwd)
SRAM_MODEL2=/home/mhnie/develop/cacheflex_memory2/model/verilog

vcs -full64 -timescale=1ns/1ps -sverilog \
    +incdir+$BSG_STL/bsg_misc \
    +incdir+$BSG_STL/bsg_cache \
    +define+IVCS_CYCLE_SIM \
    +define+FSDB \
    +nospecify +notimingchecks \
    -debug_access+pp+all -kdb -lca +vpi \
    $BSG_STL/bsg_cache/bsg_cache_pkg.sv \
    /home/mhnie/develop/cacheflex/l1i/snps_pnr/rm_icc2/work/bsg_cache_l1i.v.gz \
    -v $SRAM_MODEL2/IN12LP_S1DB_W02048B256M04S2_LB.v \
    -v $SRAM_MODEL2/IN12LP_S1DB_W02048B064M04S2_LB.v \
    -v $SRAM_MODEL2/IN12LP_S1DB_W08192B064M04S8_LB.v \
    -v $SRAM_MODEL2/IN12LP_S1DB_W08192B128M04S8_LB.v \
    -v $SRAM_MODEL2/IN12LP_S1DB_W01024B136M04S2_LB.v \
    -v $SRAM_MODEL2/IN12LP_S1DB_W04096B256M04S4_LB.v \
    -v $SRAM_MODEL2/IN12LP_S1DB_W04096B032M04S4_LB.v \
    -v $SRAM_MODEL2/IN12LP_R1DB_W00256B144M02S1_LB.v \
    -v $SRAM_MODEL2/IN12LP_R1DB_W00256B008M02S1_LB.v \
    -v $SRAM_MODEL2/IN12LP_R1DB_W01024B015M02S2_LB.v \
    /mnt/ssd/pdk/gf12/v-logic_in_gf12lp_sc7p5t_84cpp_base_ssc14l/IN12LP_SC7P5T_84CPP_BASE_SSC14L_FDK_RELV00R60/model/verilog/prim.v \
    /mnt/ssd/pdk/gf12/v-logic_in_gf12lp_sc7p5t_84cpp_base_ssc14sl/IN12LP_SC7P5T_84CPP_BASE_SSC14SL_FDK_RELV00R60/model/verilog/prim.v \
    /mnt/ssd/pdk/gf12/v-logic_in_gf12lp_sc7p5t_84cpp_base_ssc14r/IN12LP_SC7P5T_84CPP_BASE_SSC14R_FDK_RELV00R60/model/verilog/prim.v \
    -v /mnt/ssd/pdk/gf12/v-logic_in_gf12lp_sc7p5t_84cpp_base_ssc14l/IN12LP_SC7P5T_84CPP_BASE_SSC14L_FDK_RELV00R60/model/verilog/IN12LP_SC7P5T_84CPP_BASE_SSC14L.v \
    -v /mnt/ssd/pdk/gf12/v-logic_in_gf12lp_sc7p5t_84cpp_base_ssc14sl/IN12LP_SC7P5T_84CPP_BASE_SSC14SL_FDK_RELV00R60/model/verilog/IN12LP_SC7P5T_84CPP_BASE_SSC14SL.v \
    -v /mnt/ssd/pdk/gf12/v-logic_in_gf12lp_sc7p5t_84cpp_base_ssc14r/IN12LP_SC7P5T_84CPP_BASE_SSC14R_FDK_RELV00R60/model/verilog/IN12LP_SC7P5T_84CPP_BASE_SSC14R.v \
    $BSG_STL/bsg_misc/bsg_mux.sv \
    $BSG_STL/bsg_test/bsg_nonsynth_clock_gen.sv \
    $BSG_STL/bsg_test/bsg_nonsynth_reset_gen.sv \
    $BSG_STL/testing/bsg_cache/common/bsg_nonsynth_dma_model.sv \
    ${TB_DIR}/testbench_gate.sv \
    -top testbench \
    -o ${TB_DIR}/simv_gate

cd ${TB_DIR}
${TB_DIR}/simv_gate -no_save
