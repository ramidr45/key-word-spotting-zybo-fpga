# ------------------------------------------------------------------------------
# build_hw.tcl -- construit tout le materiel en mode batch
#   vivado -mode batch -source hw/scripts/build_hw.tcl
# Resultats dans hw/build/out : top.bit, top.hdf (Vivado <= 2019.1) ou top.xsa
# Prerequis : fichiers de carte Digilent 'zybo' (Zybo 1re generation) installes dans Vivado.
# ------------------------------------------------------------------------------

set script_dir [file normalize [file dirname [info script]]]
set hw_dir     [file normalize "$script_dir/.."]
set build_dir  "$hw_dir/build"
set out_dir    "$build_dir/out"
set proj_name  kws_zybo

file mkdir $out_dir

# --- carte ---------------------------------------------------------------------
set part xc7z010clg400-1
set boards [get_board_parts -quiet -latest_file_version "*digilentinc.com:zybo:*"]
if {[llength $boards] == 0} {
    puts "=============================================================================="
    puts "ERREUR : fichiers de carte Digilent 'zybo' (1re generation) introuvables."
    puts "Copiez le dossier 'zybo' (PAS zybo-z7-10) du depot github.com/Digilent/vivado-boards"
    puts "(new/board_files) dans <Vivado>/data/boards/board_files/ puis relancez."
    puts "=============================================================================="
    exit 1
}
set board [lindex $boards 0]
puts "INFO: carte = $board"

# --- projet --------------------------------------------------------------------
create_project -force $proj_name $build_dir -part $part
set_property board_part $board [current_project]
set_property target_language VHDL [current_project]

add_files -norecurse [list \
    $hw_dir/rtl/i2c_master.vhd \
    $hw_dir/rtl/ssm2603_ctrl.vhd \
    $hw_dir/rtl/i2s_rx.vhd \
    $hw_dir/rtl/audio_fifo.vhd \
    $hw_dir/rtl/kws_audio_axi.vhd \
]
update_compile_order -fileset sources_1

# --- block design --------------------------------------------------------------
source $script_dir/bd_system.tcl

set bd_file [get_files system.bd]
generate_target all $bd_file
make_wrapper -files $bd_file -top
set wrapper [glob -nocomplain $build_dir/$proj_name.srcs/sources_1/bd/system/hdl/system_wrapper.vhd]
if {$wrapper eq ""} {
    set wrapper [glob $build_dir/$proj_name.gen/sources_1/bd/system/hdl/system_wrapper.vhd]
}
add_files -norecurse $wrapper

add_files -norecurse $hw_dir/rtl/top.vhd
add_files -fileset constrs_1 -norecurse $hw_dir/constraints/zybo.xdc
set_property top top [current_fileset]
update_compile_order -fileset sources_1

# --- synthese / implementation / bitstream -------------------------------------
launch_runs synth_1 -jobs 4
wait_on_run synth_1
if {[get_property PROGRESS [get_runs synth_1]] != "100%"} { puts "ERREUR synthese"; exit 1 }

launch_runs impl_1 -to_step write_bitstream -jobs 4
wait_on_run impl_1
if {[get_property PROGRESS [get_runs impl_1]] != "100%"} { puts "ERREUR implementation"; exit 1 }

open_run impl_1
report_timing_summary -file $out_dir/timing_summary.rpt
report_utilization    -file $out_dir/utilization.rpt
set wns [get_property SLACK [get_timing_paths -max_paths 1 -nworst 1 -setup]]
puts "INFO: WNS = $wns ns"

set bit [glob $build_dir/$proj_name.runs/impl_1/*.bit]
file copy -force $bit $out_dir/top.bit

# --- export materiel pour SDK / Vitis -----------------------------------------
scan [version -short] "%d.%d" vmaj vmin
if {$vmaj < 2019 || ($vmaj == 2019 && $vmin < 2)} {
    # Vivado 2018.x / 2019.1 -> .hdf pour Xilinx SDK
    write_hwdef -force -file $out_dir/top.hwdef
    write_sysdef -force -hwdef $out_dir/top.hwdef -bitfile $out_dir/top.bit -file $out_dir/top.hdf
    puts "INFO: export -> $out_dir/top.hdf"
} else {
    write_hw_platform -fixed -include_bit -force -file $out_dir/top.xsa
    puts "INFO: export -> $out_dir/top.xsa"
}

puts "=============================================================================="
puts "MATERIEL OK : $out_dir"
puts "=============================================================================="
