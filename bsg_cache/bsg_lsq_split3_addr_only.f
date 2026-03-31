// =========================================================
// bsg_lsq_split3_addr_only — Synthesis Filelist
//   32-entry LQ + 16-entry SAQ, addr_width=48, data_width=0
//   Wraps bsg_lsq_split3 with data_width_p=0 (no SDQ)
// =========================================================

+incdir+$BSG_STL/bsg_misc
+incdir+$BSG_STL/bsg_cache
+incdir+$BSG_STL/bsg_mem

// --- bsg_misc ---
$BSG_STL/bsg_misc/bsg_defines.sv
$BSG_STL/bsg_misc/bsg_scan.sv
$BSG_STL/bsg_misc/bsg_decode.sv
$BSG_STL/bsg_misc/bsg_decode_with_v.sv
$BSG_STL/bsg_misc/bsg_dff_en.sv
$BSG_STL/bsg_misc/bsg_dff_reset_en.sv
$BSG_STL/bsg_misc/bsg_dff_reset_set_clear.sv
$BSG_STL/bsg_misc/bsg_mux_one_hot.sv
$BSG_STL/bsg_misc/bsg_encode_one_hot.sv
$BSG_STL/bsg_misc/bsg_priority_encode_one_hot_out.sv
$BSG_STL/bsg_misc/bsg_priority_encode.sv
$BSG_STL/bsg_misc/bsg_circular_ptr.sv
$BSG_STL/bsg_misc/bsg_counter_up_down.sv

// --- bsg_mem ---
$BSG_STL/bsg_mem/bsg_mem_1r1w_synth.sv
$BSG_STL/bsg_mem/bsg_mem_1r1w.sv
$BSG_STL/bsg_mem/bsg_cam_1r1w_tag_array.sv

// --- bsg_dataflow ---
$BSG_STL/bsg_dataflow/bsg_fifo_tracker.sv
$BSG_STL/bsg_dataflow/bsg_fifo_reorder.sv

// --- LSQ modules ---
$BSG_STL/bsg_cache/bsg_store_addr_queue.sv
$BSG_STL/bsg_cache/bsg_store_data_queue.sv
$BSG_STL/bsg_cache/bsg_load_queue.sv
$BSG_STL/bsg_cache/bsg_lsq_split3.sv
$BSG_STL/bsg_cache/bsg_lsq_split3_addr_only.sv
