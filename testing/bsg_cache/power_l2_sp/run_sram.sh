#!/bin/bash
set -euo pipefail

BSG_STL=$(cd "$(dirname "$0")/../../.." && pwd)
TB_DIR=$(cd "$(dirname "$0")" && pwd)
SRAM_MODEL=/home/mhnie/develop/cacheflex_memory/model/verilog

export BSG_STL TB_DIR SRAM_MODEL

# Compile with SRAM models (cycle-sim, no timing checks)
vcs -full64 -timescale=1ns/1ps -sverilog -f ${TB_DIR}/tb_sram.f \
    +define+IVCS_CYCLE_SIM \
    +define+FSDB \
    +nospecify +notimingchecks \
    -debug_access+pp+all -kdb -lca +vpi \
    -o ${TB_DIR}/simv_sram

# Run
${TB_DIR}/simv_sram -no_save
