// =========================================================
// Physical SRAM models and RTL wrappers (cacheflex_memory2)
// S1DB/R1DB macros, Leakage-Optimized + Bit-Write
// =========================================================

// ------- RTL wrappers -------
$BSG_STL/sram/rtl2/MBH_ZSNL_IN12LP_S1DB_W02048B256M04S2_LB.v
$BSG_STL/sram/rtl2/MBH_ZSNL_IN12LP_S1DB_W02048B064M04S2_LB.v
$BSG_STL/sram/rtl2/MBH_ZSNL_IN12LP_S1DB_W08192B064M04S8_LB.v
$BSG_STL/sram/rtl2/MBH_ZSNL_IN12LP_S1DB_W08192B128M04S8_LB.v
$BSG_STL/sram/rtl2/MBH_ZSNL_IN12LP_S1DB_W01024B136M04S2_LB.v
$BSG_STL/sram/rtl2/MBH_ZSNL_IN12LP_S1DB_W04096B256M04S4_LB.v
$BSG_STL/sram/rtl2/MBH_ZSNL_IN12LP_S1DB_W04096B032M04S4_LB.v
$BSG_STL/sram/rtl2/MBH_ZSNL_IN12LP_R1DB_W00256B144M02S1_LB.v
$BSG_STL/sram/rtl2/MBH_ZSNL_IN12LP_R1DB_W00256B008M02S1_LB.v
$BSG_STL/sram/rtl2/MBH_ZSNL_IN12LP_R1DB_W01024B015M02S2_LB.v

// ------- bsg_mem SRAM wrappers (replaces behavioral) -------
$BSG_STL/sram/bsg_mem_1rw_sync_mask_write_byte2.sv
$BSG_STL/sram/bsg_mem_1rw_sync_mask_write_bit2.sv
