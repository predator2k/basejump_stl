#!/bin/bash
set -euo pipefail

BSG_STL=$(cd "$(dirname "$0")/../../.." && pwd)
TB_DIR=$(cd "$(dirname "$0")" && pwd)
SRAM_MODEL2=/home/mhnie/develop/cacheflex_memory2/model/verilog

export BSG_STL TB_DIR SRAM_MODEL2

# Compile with SRAM models (cycle-sim, no timing checks)
vcs -full64 -timescale=1ns/1ps -sverilog -f ${TB_DIR}/tb_sram2.f \
    +define+IVCS_CYCLE_SIM \
    +define+FSDB \
    +nospecify +notimingchecks \
    -debug_access+pp+all -kdb -lca +vpi \
    -o ${TB_DIR}/simv_sram2

# Run simulation (generates FSDB)
cd ${TB_DIR}
${TB_DIR}/simv_sram2 -no_save
