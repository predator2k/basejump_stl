#!/bin/bash
set -euo pipefail

BSG_STL=$(cd "$(dirname "$0")/../.." && pwd)

vcs -full64 -timescale=1ns/1ps -sverilog \
    +define+BSG_HIDE_FROM_SYNTHESIS \
    +incdir+$BSG_STL/bsg_misc \
    +incdir+$BSG_STL/bsg_cache \
    +incdir+$BSG_STL/bsg_mem \
    $BSG_STL/bsg_misc/bsg_defines.sv \
    $BSG_STL/bsg_misc/bsg_scan.sv \
    $BSG_STL/bsg_misc/bsg_decode.sv \
    $BSG_STL/bsg_misc/bsg_decode_with_v.sv \
    $BSG_STL/bsg_misc/bsg_dff_en.sv \
    $BSG_STL/bsg_misc/bsg_dff_reset_en.sv \
    $BSG_STL/bsg_misc/bsg_dff_reset_set_clear.sv \
    $BSG_STL/bsg_misc/bsg_mux_one_hot.sv \
    $BSG_STL/bsg_misc/bsg_encode_one_hot.sv \
    $BSG_STL/bsg_misc/bsg_priority_encode_one_hot_out.sv \
    $BSG_STL/bsg_misc/bsg_priority_encode.sv \
    $BSG_STL/bsg_misc/bsg_circular_ptr.sv \
    $BSG_STL/bsg_misc/bsg_counter_up_down.sv \
    $BSG_STL/bsg_mem/bsg_mem_1r1w_synth.sv \
    $BSG_STL/bsg_mem/bsg_mem_1r1w.sv \
    $BSG_STL/bsg_mem/bsg_cam_1r1w_tag_array.sv \
    $BSG_STL/bsg_dataflow/bsg_fifo_tracker.sv \
    $BSG_STL/bsg_dataflow/bsg_fifo_reorder.sv \
    $BSG_STL/bsg_cache/bsg_store_addr_queue.sv \
    $BSG_STL/bsg_cache/bsg_store_data_queue.sv \
    $BSG_STL/bsg_cache/bsg_load_queue.sv \
    $BSG_STL/bsg_cache/bsg_lsq_split3.sv \
    $BSG_STL/testing/bsg_lsq/testbench_split3.sv \
    -top testbench \
    -o $BSG_STL/testing/bsg_lsq/simv_split3

$BSG_STL/testing/bsg_lsq/simv_split3
