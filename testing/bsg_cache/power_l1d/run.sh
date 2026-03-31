#!/bin/bash
set -euo pipefail

BSG_STL=$(cd "$(dirname "$0")/../../.." && pwd)
TB_DIR=$(cd "$(dirname "$0")" && pwd)
export BSG_STL TB_DIR

vcs -full64 -timescale=1ns/1ps -sverilog -f ${TB_DIR}/tb.f \
    -debug_access+pp+all -kdb -lca +vpi \
    -o ${TB_DIR}/simv

${TB_DIR}/simv
