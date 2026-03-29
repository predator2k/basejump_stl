// =========================================================
// bsg_cache L3 (4MB, 16-way) - Synthesis Filelist (VCS)
// =========================================================

// Include directories/
+incdir+$BSG_STL/bsg_misc
// +incdir+$BSG_STL/bsg_cache

// Package
$BSG_STL/bsg_cache/bsg_cache_pkg.sv

// ------- bsg_misc (leaf cells) -------
$BSG_STL/bsg_misc/bsg_dff.sv
$BSG_STL/bsg_misc/bsg_dff_en.sv
$BSG_STL/bsg_misc/bsg_dff_en_bypass.sv
$BSG_STL/bsg_misc/bsg_dff_reset_set_clear.sv
$BSG_STL/bsg_misc/bsg_clkgate_optional.sv
$BSG_STL/bsg_misc/bsg_mux.sv
$BSG_STL/bsg_misc/bsg_mux_one_hot.sv
$BSG_STL/bsg_misc/bsg_mux_segmented.sv
$BSG_STL/bsg_misc/bsg_mux_bitwise.sv
$BSG_STL/bsg_misc/bsg_decode.sv
$BSG_STL/bsg_misc/bsg_encode_one_hot.sv
$BSG_STL/bsg_misc/bsg_scan.sv
$BSG_STL/bsg_misc/bsg_priority_encode_one_hot_out.sv
$BSG_STL/bsg_misc/bsg_priority_encode.sv
$BSG_STL/bsg_misc/bsg_expand_bitmask.sv
$BSG_STL/bsg_misc/bsg_crossbar_o_by_i.sv
$BSG_STL/bsg_misc/bsg_circular_ptr.sv
$BSG_STL/bsg_misc/bsg_counter_clear_up.sv
$BSG_STL/bsg_misc/bsg_lru_pseudo_tree_decode.sv
$BSG_STL/bsg_misc/bsg_lru_pseudo_tree_encode.sv
$BSG_STL/bsg_misc/bsg_lru_pseudo_tree_backup.sv
$BSG_STL/bsg_misc/bsg_dlatch.sv

// ------- bsg_mem (behavioral + SRAM-backed) -------
-f $BSG_STL/sram/sram.f
$BSG_STL/bsg_mem/bsg_mem_1rw_sync_synth.sv
$BSG_STL/bsg_mem/bsg_mem_1rw_sync.sv
$BSG_STL/bsg_mem/bsg_mem_1r1w_synth.sv
$BSG_STL/bsg_mem/bsg_mem_1r1w.sv
$BSG_STL/bsg_mem/bsg_mem_1r1w_sync_synth.sv
$BSG_STL/bsg_mem/bsg_mem_1r1w_sync.sv

// ------- bsg_dataflow (FIFOs) -------
$BSG_STL/bsg_dataflow/bsg_fifo_tracker.sv
$BSG_STL/bsg_dataflow/bsg_fifo_1r1w_small_unhardened.sv
$BSG_STL/bsg_dataflow/bsg_fifo_1r1w_small_hardened.sv
$BSG_STL/bsg_dataflow/bsg_fifo_1r1w_small.sv
$BSG_STL/bsg_dataflow/bsg_two_fifo.sv

// ------- bsg_cache (DUT) -------
$BSG_STL/bsg_cache/bsg_cache.svh
$BSG_STL/bsg_cache/bsg_cache_decode.sv
$BSG_STL/bsg_cache/bsg_cache_buffer_queue.sv
$BSG_STL/bsg_cache/bsg_cache_sbuf.sv
$BSG_STL/bsg_cache/bsg_cache_tbuf.sv
$BSG_STL/bsg_cache/bsg_cache_miss.sv
$BSG_STL/bsg_cache/bsg_cache_dma.sv
$BSG_STL/bsg_cache/bsg_cache.sv
$BSG_STL/bsg_cache/bsg_cache_l3.sv
