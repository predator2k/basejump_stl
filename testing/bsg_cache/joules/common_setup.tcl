# Use newer Verdi FSDB reader
set env(VERDI_HOME) /eda/installed_tools/verdi/X-2025.06
set env(NOVAS_HOME) /eda/installed_tools/verdi/X-2025.06

#-------------------------------------------------------------------------------
# common_setup.tcl — shared PDK / library / path setup for Joules
#-------------------------------------------------------------------------------

# Paths
set BSG_STL   /home/mhnie/develop/basejump_stl
set PDK       /mnt/ssd/pdk/gf12
set SRAM_IP   /home/mhnie/develop/cacheflex_memory

#-------------------------------------------------------------------------------
# Standard cell libraries (SC7P5T 84CPP, TT 0.80V 25C)
#   SSC14L  — base low-Vt
#   SSC14SL — base super-low-Vt
#   SSC14R  — base regular-Vt
#-------------------------------------------------------------------------------
set STDCELL_SSC14L_DIR  $PDK/v-logic_in_gf12lp_sc7p5t_84cpp_base_ssc14l/IN12LP_SC7P5T_84CPP_BASE_SSC14L_FDK_RELV00R60
set STDCELL_SSC14SL_DIR $PDK/v-logic_in_gf12lp_sc7p5t_84cpp_base_ssc14sl/IN12LP_SC7P5T_84CPP_BASE_SSC14SL_FDK_RELV00R60
set STDCELL_SSC14R_DIR  $PDK/v-logic_in_gf12lp_sc7p5t_84cpp_base_ssc14r/IN12LP_SC7P5T_84CPP_BASE_SSC14R_FDK_RELV00R60

set STDCELL_LIB_LIST [list \
    $STDCELL_SSC14L_DIR/model/timing/lib/IN12LP_SC7P5T_84CPP_BASE_SSC14L_TT_0P80V_25C.lib.gz \
    $STDCELL_SSC14SL_DIR/model/timing/lib/IN12LP_SC7P5T_84CPP_BASE_SSC14SL_TT_0P80V_25C.lib.gz \
    $STDCELL_SSC14R_DIR/model/timing/lib/IN12LP_SC7P5T_84CPP_BASE_SSC14R_TT_0P80V_25C.lib.gz \
]

set STDCELL_LEF_LIST [list \
    $STDCELL_SSC14L_DIR/lef/IN12LP_SC7P5T_84CPP_BASE_SSC14L.lef \
    $STDCELL_SSC14SL_DIR/lef/IN12LP_SC7P5T_84CPP_BASE_SSC14SL.lef \
    $STDCELL_SSC14R_DIR/lef/IN12LP_SC7P5T_84CPP_BASE_SSC14R.lef \
]

#-------------------------------------------------------------------------------
# Technology LEF (13M: 3Mx+2Cx+4Kx+2Hx+2Gx+LB, 7.5T 84cpp)
#-------------------------------------------------------------------------------
set TECH_LEF_DIR $PDK/12LP-V1.0_7.0b/PlaceRoute/Innovus/Techfiles/13M_3Mx_2Cx_4Kx_2Hx_2Gx_LB
set TECH_LEF     $TECH_LEF_DIR/12LP_13M_3Mx_2Cx_4Kx_2Hx_2Gx_LB_7p5t_84cpp_tech.lef

#-------------------------------------------------------------------------------
# SRAM IP (cacheflex) — LEF + liberty
#-------------------------------------------------------------------------------
set SRAM_TECH_LEF  $SRAM_IP/lef/12lp_tech_11M_3Mx_4Cx_2Kx_2Gx_LB.lef
set SRAM_OVL_LEF   $SRAM_IP/lef/OVL_tech.lef

# Per-macro LEFs
set SRAM_LEF_LIST [glob $SRAM_IP/lef/IN12LP_*.lef]

# Per-macro liberty (TT 0.80V 25C)
set SRAM_LIB_LIST [glob $SRAM_IP/model/timing/lib/*_TT_0P800V_025C.lib]

#-------------------------------------------------------------------------------
# RTL search paths
#-------------------------------------------------------------------------------
set RTL_INCDIRS [list \
    $BSG_STL/bsg_misc \
    $BSG_STL/bsg_cache \
]

#-------------------------------------------------------------------------------
# Common RTL files (bsg_cache dependency tree)
#-------------------------------------------------------------------------------
set RTL_BSG_MISC [list \
    $BSG_STL/bsg_cache/bsg_cache_pkg.sv \
    $BSG_STL/bsg_misc/bsg_dff.sv \
    $BSG_STL/bsg_misc/bsg_dff_en.sv \
    $BSG_STL/bsg_misc/bsg_dff_en_bypass.sv \
    $BSG_STL/bsg_misc/bsg_dff_reset_set_clear.sv \
    $BSG_STL/bsg_misc/bsg_dlatch.sv \
    $BSG_STL/bsg_misc/bsg_clkgate_optional.sv \
    $BSG_STL/bsg_misc/bsg_mux.sv \
    $BSG_STL/bsg_misc/bsg_mux_one_hot.sv \
    $BSG_STL/bsg_misc/bsg_mux_segmented.sv \
    $BSG_STL/bsg_misc/bsg_mux_bitwise.sv \
    $BSG_STL/bsg_misc/bsg_decode.sv \
    $BSG_STL/bsg_misc/bsg_encode_one_hot.sv \
    $BSG_STL/bsg_misc/bsg_scan.sv \
    $BSG_STL/bsg_misc/bsg_priority_encode_one_hot_out.sv \
    $BSG_STL/bsg_misc/bsg_priority_encode.sv \
    $BSG_STL/bsg_misc/bsg_expand_bitmask.sv \
    $BSG_STL/bsg_misc/bsg_crossbar_o_by_i.sv \
    $BSG_STL/bsg_misc/bsg_circular_ptr.sv \
    $BSG_STL/bsg_misc/bsg_counter_clear_up.sv \
    $BSG_STL/bsg_misc/bsg_lru_pseudo_tree_decode.sv \
    $BSG_STL/bsg_misc/bsg_lru_pseudo_tree_encode.sv \
    $BSG_STL/bsg_misc/bsg_lru_pseudo_tree_backup.sv \
]

set RTL_BSG_MEM [list \
    $BSG_STL/sram/bsg_mem_1rw_sync_mask_write_byte.sv \
    $BSG_STL/sram/bsg_mem_1rw_sync_mask_write_bit.sv \
    $BSG_STL/sram/rtl/MBH_ZSNL_IN12LP_S1PB_W02048B128M04S2_HB.v \
    $BSG_STL/sram/rtl/MBH_ZSNL_IN12LP_S1PB_W08192B128M04S8_HB.v \
    $BSG_STL/sram/rtl/MBH_ZSNL_IN12LP_S1PB_W08192B064M04S8_HB.v \
    $BSG_STL/sram/rtl/MBH_ZSNL_IN12LP_S1PB_W01024B104M04S2_HB.v \
    $BSG_STL/sram/rtl/MBH_ZSNL_IN12LP_S1PB_W04096B192M04S4_HB.v \
    $BSG_STL/sram/rtl/MBH_ZSNL_IN12LP_S1PB_W04096B032M04S4_HB.v \
    $BSG_STL/sram/rtl/MBH_ZSNL_IN12LP_R1PB_W00256B112M02S1_HB.v \
    $BSG_STL/sram/rtl/MBH_ZSNL_IN12LP_R1PB_W00256B007M02S1_HB.v \
    $BSG_STL/sram/rtl/MBH_ZSNL_IN12LP_R1PB_W01024B015M04S1_HB.v \
]

set RTL_BSG_DATAFLOW [list \
    $BSG_STL/bsg_dataflow/bsg_fifo_tracker.sv \
    $BSG_STL/bsg_dataflow/bsg_fifo_1r1w_small_unhardened.sv \
    $BSG_STL/bsg_dataflow/bsg_fifo_1r1w_small_hardened.sv \
    $BSG_STL/bsg_dataflow/bsg_fifo_1r1w_small.sv \
    $BSG_STL/bsg_dataflow/bsg_two_fifo.sv \
]

# bsg_mem behavioral models still needed for FIFOs (bsg_mem_1r1w etc.)
set RTL_BSG_MEM_BEHAV [list \
    $BSG_STL/bsg_mem/bsg_mem_1rw_sync_synth.sv \
    $BSG_STL/bsg_mem/bsg_mem_1rw_sync.sv \
    $BSG_STL/bsg_mem/bsg_mem_1r1w_synth.sv \
    $BSG_STL/bsg_mem/bsg_mem_1r1w.sv \
    $BSG_STL/bsg_mem/bsg_mem_1r1w_sync_synth.sv \
    $BSG_STL/bsg_mem/bsg_mem_1r1w_sync.sv \
]

set RTL_BSG_CACHE_CORE [list \
    $BSG_STL/bsg_cache/bsg_cache_decode.sv \
    $BSG_STL/bsg_cache/bsg_cache_buffer_queue.sv \
    $BSG_STL/bsg_cache/bsg_cache_sbuf.sv \
    $BSG_STL/bsg_cache/bsg_cache_tbuf.sv \
    $BSG_STL/bsg_cache/bsg_cache_miss.sv \
    $BSG_STL/bsg_cache/bsg_cache_dma.sv \
]


set CLK_PERIOD 400

#-------------------------------------------------------------------------------
# Joules global settings
#-------------------------------------------------------------------------------
set SYN_EFF medium
set MAP_EFF medium
set pwra_mode "time_based"
