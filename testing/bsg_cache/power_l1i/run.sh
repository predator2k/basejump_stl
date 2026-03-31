#!/bin/bash
set -euo pipefail

BSG_STL=$(cd "$(dirname "$0")/../../.." && pwd)
TB_DIR=$(cd "$(dirname "$0")" && pwd)

export BSG_STL TB_DIR

# Compile
vcs -full64 -timescale=1ns/1ps -sverilog -f ${TB_DIR}/tb.f \
    -debug_access+pp+all -kdb -lca +vpi \
    +define+FSDB \
    -o ${TB_DIR}/simv

# Run
${TB_DIR}/simv +wave=1
