// =========================================================
// bsg_cache L3 (4MB, 16-way) - Testbench Filelist (VCS)
// =========================================================

// Synthesis filelist
-f $TB_DIR/synth.f

// Additional include directories
+incdir+$BSG_STL/bsg_cache
+incdir+$BSG_STL/bsg_misc

// ------- Testbench support -------
$BSG_STL/bsg_test/bsg_nonsynth_clock_gen.sv
$BSG_STL/bsg_test/bsg_nonsynth_reset_gen.sv
$BSG_STL/testing/bsg_cache/common/bsg_nonsynth_dma_model.sv

// ------- Testbench -------
$TB_DIR/testbench.sv
