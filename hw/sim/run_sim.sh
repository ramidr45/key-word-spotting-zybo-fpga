#!/usr/bin/env bash
# Simulation GHDL du peripherique audio (sans Vivado).
# Usage : ./run_sim.sh            (ajoutez --wave pour generer tb.ghw a ouvrir avec GTKWave)
set -e
cd "$(dirname "$0")"
W=work_ghdl
rm -rf "$W" && mkdir -p "$W"
RTL=../rtl
ghdl -a --std=08 --workdir=$W $RTL/i2c_master.vhd $RTL/ssm2603_ctrl.vhd $RTL/i2s_rx.vhd \
     $RTL/audio_fifo.vhd $RTL/kws_audio_axi.vhd tb_kws_audio.vhd
ghdl -e --std=08 --workdir=$W tb_kws_audio
if [ "$1" == "--wave" ]; then
  ghdl -r --std=08 --workdir=$W tb_kws_audio --wave=tb.ghw --stop-time=10ms
else
  ghdl -r --std=08 --workdir=$W tb_kws_audio --stop-time=10ms
fi
