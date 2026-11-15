#!/usr/bin/env bash
# build_all.sh -- equivalent Linux de build_all.bat
#   XILINX=/opt/Xilinx VER=2018.2 ./build_all.sh [run]
set -e
XILINX=${XILINX:-/opt/Xilinx}
VER=${VER:-2018.2}
cd "$(dirname "$0")"
source "$XILINX/Vivado/$VER/settings64.sh"
echo "=== [1/3] Vivado ==="
vivado -mode batch -nojournal -log hw/build_hw.log -source hw/scripts/build_hw.tcl
echo "=== [2/3] SDK ==="
source "$XILINX/SDK/$VER/settings64.sh"
xsct sw/scripts/create_sdk.tcl
if [ "$1" == "run" ]; then
  echo "=== [3/3] carte ==="
  xsct sw/scripts/run_on_board.tcl
fi
echo "TERMINE."
