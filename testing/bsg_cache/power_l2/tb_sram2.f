+define+IVCS_CYCLE_SIM
-v $SRAM_MODEL2/IN12LP_S1DB_W02048B256M04S2_LB.v
-v $SRAM_MODEL2/IN12LP_S1DB_W02048B064M04S2_LB.v
-v $SRAM_MODEL2/IN12LP_S1DB_W08192B064M04S8_LB.v
-v $SRAM_MODEL2/IN12LP_S1DB_W08192B128M04S8_LB.v
-v $SRAM_MODEL2/IN12LP_S1DB_W01024B136M04S2_LB.v
-v $SRAM_MODEL2/IN12LP_S1DB_W04096B256M04S4_LB.v
-v $SRAM_MODEL2/IN12LP_S1DB_W04096B032M04S4_LB.v
-v $SRAM_MODEL2/IN12LP_R1DB_W00256B144M02S1_LB.v
-v $SRAM_MODEL2/IN12LP_R1DB_W00256B008M02S1_LB.v
-v $SRAM_MODEL2/IN12LP_R1DB_W01024B015M02S2_LB.v

// =========================================================
// bsg_cache L2 (512KB, 8-way) - Testbench Filelist (VCS)
// =========================================================

// Synthesis filelist
-f $TB_DIR/synth_sram2.f

// Additional include directories
// +incdir+$BSG_STL/bsg_cache
// +incdir+$BSG_STL/bsg_misc

// ------- Testbench support -------
$BSG_STL/bsg_test/bsg_nonsynth_clock_gen.sv
$BSG_STL/bsg_test/bsg_nonsynth_reset_gen.sv
$BSG_STL/testing/bsg_cache/common/bsg_nonsynth_dma_model.sv

// ------- Testbench -------
$TB_DIR/testbench.sv
