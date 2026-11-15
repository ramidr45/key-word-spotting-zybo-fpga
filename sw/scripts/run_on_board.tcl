# ------------------------------------------------------------------------------
# run_on_board.tcl -- programme le FPGA + charge l'application via JTAG
#   xsct sw/scripts/run_on_board.tcl
# Sequence identique a celle generee par Xilinx SDK 2018.2 (System Debugger).
# Carte : Zybo Z7-10, JP5 sur JTAG, USB sur PROG/UART, PuTTY 115200 8N1 ouvert AVANT.
# ------------------------------------------------------------------------------
set script_dir [file normalize [file dirname [info script]]]
set root       [file normalize "$script_dir/../.."]
set ws         "$root/sw/workspace"
set bit        "$root/hw/build/out/top.bit"
set ps7init    "$ws/hw0/ps7_init.tcl"
set elf        "$ws/kws_app/Release/kws_app.elf"
set hdf        [lindex [glob -nocomplain $ws/hw0/*.hdf] 0]

foreach f [list $bit $ps7init $elf $hdf] {
    if {$f eq "" || ![file exists $f]} { puts "ERREUR : fichier introuvable ($f)"; exit 1 }
}

connect
source $ps7init
targets -set -nocase -filter {name =~ "APU*"}
rst -system
after 3000
fpga -file $bit
targets -set -nocase -filter {name =~ "APU*"}
loadhw -hw $hdf -mem-ranges [list {0x40000000 0xbfffffff}]
configparams force-mem-access 1
targets -set -nocase -filter {name =~ "APU*"}
ps7_init
ps7_post_config
targets -set -nocase -filter {name =~ "*A9*#0"}
dow $elf
configparams force-mem-access 0
targets -set -nocase -filter {name =~ "*A9*#0"}
con
puts "Application lancee : regardez le terminal serie (115200 8N1)."
