# ------------------------------------------------------------------------------
# create_sdk.tcl -- cree le workspace Xilinx SDK (2018.x) et compile l'application
#   xsct sw/scripts/create_sdk.tcl
# Utilise hw/build/out/top.hdf (produit par build_hw.tcl).
# ------------------------------------------------------------------------------
set script_dir [file normalize [file dirname [info script]]]
set root       [file normalize "$script_dir/../.."]
set ws         "$root/sw/workspace"
set hdf        "$root/hw/build/out/top.hdf"
set src        "$root/sw/src"

if {![file exists $hdf]} {
    puts "ERREUR : $hdf introuvable -> lancez d'abord build_hw.tcl"
    exit 1
}

file delete -force $ws
file mkdir $ws
setws $ws

createhw  -name hw0  -hwspec $hdf
createbsp -name bsp0 -hwproject hw0 -proc ps7_cortexa9_0 -os standalone
configbsp -bsp bsp0 stdin  ps7_uart_1
configbsp -bsp bsp0 stdout ps7_uart_1
updatemss -mss $ws/bsp0/system.mss
regenbsp  -bsp bsp0

createapp -name kws_app -hwproject hw0 -bsp bsp0 -proc ps7_cortexa9_0 -os standalone \
          -lang C -app {Empty Application}
importsources -name kws_app -path $src
configapp -app kws_app build-config release
configapp -app kws_app compiler-optimization {Optimize most (-O3)}
configapp -app kws_app libraries m

# pile / tas plus grands pour printf flottant
set ld "$ws/kws_app/src/lscript.ld"
if {[file exists $ld]} {
    set f [open $ld r]; set t [read $f]; close $f
    regsub {_STACK_SIZE = DEFINED\(_STACK_SIZE\) \? _STACK_SIZE : 0x[0-9A-Fa-f]+;} $t \
        {_STACK_SIZE = DEFINED(_STACK_SIZE) ? _STACK_SIZE : 0x10000;} t
    regsub {_HEAP_SIZE = DEFINED\(_HEAP_SIZE\) \? _HEAP_SIZE : 0x[0-9A-Fa-f]+;} $t \
        {_HEAP_SIZE = DEFINED(_HEAP_SIZE) ? _HEAP_SIZE : 0x10000;} t
    set f [open $ld w]; puts -nonewline $f $t; close $f
}

projects -build

set elf "$ws/kws_app/Release/kws_app.elf"
if {![file exists $elf]} { puts "ERREUR : compilation echouee"; exit 1 }
puts "=============================================================================="
puts "LOGICIEL OK : $elf"
puts "=============================================================================="
