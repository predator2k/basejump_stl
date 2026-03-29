// =========================================================
// bsg_cache_sp L2 (512KB, 8-way) - Testbench Filelist (VCS)
// =========================================================

// Synthesis filelist
-f $TB_DIR/synth_sram.f

// Additional include directories
+incdir+$BSG_STL/bsg_cache
+incdir+$BSG_STL/bsg_misc

// ------- Testbench support -------
$BSG_STL/bsg_test/bsg_nonsynth_clock_gen.sv
$BSG_STL/bsg_test/bsg_nonsynth_reset_gen.sv
$BSG_STL/testing/bsg_cache/common/bsg_nonsynth_dma_model.sv

// ------- L2 SPM top module -------
$TB_DIR/bsg_cache_l2_spm.sv

// ------- Testbench -------
$TB_DIR/testbench.sv
