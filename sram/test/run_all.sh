#!/bin/bash
set -e

SRAM_RTL=/home/mhnie/develop/basejump_stl/sram/rtl
SRAM_MODEL=/home/mhnie/develop/cacheflex_memory/model/verilog
TEST_DIR=$(cd "$(dirname "$0")" && pwd)

# SRAM list: (testbench, wrapper_file, model_file)
SRAMS=(
  "tb_s1pb_w02048b128m04s2_hb:MBH_ZSNL_IN12LP_S1PB_W02048B128M04S2_HB:IN12LP_S1PB_W02048B128M04S2_HB"
  "tb_s1pb_w08192b128m04s8_hb:MBH_ZSNL_IN12LP_S1PB_W08192B128M04S8_HB:IN12LP_S1PB_W08192B128M04S8_HB"
  "tb_s1pb_w08192b064m04s8_hb:MBH_ZSNL_IN12LP_S1PB_W08192B064M04S8_HB:IN12LP_S1PB_W08192B064M04S8_HB"
  "tb_s1pb_w01024b104m04s2_hb:MBH_ZSNL_IN12LP_S1PB_W01024B104M04S2_HB:IN12LP_S1PB_W01024B104M04S2_HB"
  "tb_s1pb_w04096b192m04s4_hb:MBH_ZSNL_IN12LP_S1PB_W04096B192M04S4_HB:IN12LP_S1PB_W04096B192M04S4_HB"
  "tb_s1pb_w04096b032m04s4_hb:MBH_ZSNL_IN12LP_S1PB_W04096B032M04S4_HB:IN12LP_S1PB_W04096B032M04S4_HB"
  "tb_r1pb_w00256b112m02s1_hb:MBH_ZSNL_IN12LP_R1PB_W00256B112M02S1_HB:IN12LP_R1PB_W00256B112M02S1_HB"
  "tb_r1pb_w00256b007m02s1_hb:MBH_ZSNL_IN12LP_R1PB_W00256B007M02S1_HB:IN12LP_R1PB_W00256B007M02S1_HB"
  "tb_r1pb_w01024b015m04s1_hb:MBH_ZSNL_IN12LP_R1PB_W01024B015M04S1_HB:IN12LP_R1PB_W01024B015M04S1_HB"
  "tb_r1pb_w01024b128m02s2_h:MBH_ZSNL_IN12LP_R1PB_W01024B128M02S2_H:IN12LP_R1PB_W01024B128M02S2_H"
)

PASS_CNT=0
FAIL_CNT=0
RESULTS=()

for entry in "${SRAMS[@]}"; do
  IFS=':' read -r tb wrapper model <<< "$entry"
  echo "========================================"
  echo "Testing: $wrapper"
  echo "========================================"

  WORK_DIR="/tmp/sram_test_$$_${tb}"
  mkdir -p "$WORK_DIR"

  # Compile
  cd "$WORK_DIR"
  vcs -sverilog -full64 +v2k -notice \
    +incdir+"$TEST_DIR" \
    +define+IVCS_CYCLE_SIM \
    "$SRAM_MODEL/${model}.v" \
    "$SRAM_RTL/${wrapper}.v" \
    "$TEST_DIR/${tb}.sv" \
    -top testbench \
    -o simv \
    -l compile.log 2>&1 | tail -5

  if [ ! -x simv ]; then
    echo "[COMPILE FAIL] $wrapper"
    FAIL_CNT=$((FAIL_CNT + 1))
    RESULTS+=("COMPILE_FAIL: $wrapper")
    continue
  fi

  # Run
  ./simv -l sim.log 2>&1 | grep -E '\[TEST|\[RESULT|\[FAIL|\[ABORT'

  if grep -q "ALL TESTS PASSED" sim.log; then
    PASS_CNT=$((PASS_CNT + 1))
    RESULTS+=("PASS: $wrapper")
  else
    FAIL_CNT=$((FAIL_CNT + 1))
    RESULTS+=("FAIL: $wrapper")
  fi

  # Cleanup
  rm -rf "$WORK_DIR"
done

echo ""
echo "========================================"
echo "SUMMARY: $PASS_CNT passed, $FAIL_CNT failed"
echo "========================================"
for r in "${RESULTS[@]}"; do
  echo "  $r"
done
