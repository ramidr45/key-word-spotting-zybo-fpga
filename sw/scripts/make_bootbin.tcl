# ------------------------------------------------------------------------------
# make_bootbin.tcl -- (optionnel) BOOT.BIN pour demarrer depuis la carte SD
#   xsct sw/scripts/make_bootbin.tcl
# Copier sw/boot/BOOT.BIN a la racine d'une carte SD FAT32, cavalier JP5 sur SD.
# ------------------------------------------------------------------------------
set script_dir [file normalize [file dirname [info script]]]
set root       [file normalize "$script_dir/../.."]
set ws         "$root/sw/workspace"
set bit        "$root/hw/build/out/top.bit"
set elf        "$ws/kws_app/Release/kws_app.elf"
set out        "$root/sw/boot"

setws $ws
if {![file exists "$ws/fsbl"]} {
    createapp -name fsbl -hwproject hw0 -proc ps7_cortexa9_0 -os standalone -lang C -app {Zynq FSBL}
    configapp -app fsbl build-config release
}
projects -build
set fsbl "$ws/fsbl/Release/fsbl.elf"

file mkdir $out
set bif "$out/boot.bif"
set f [open $bif w]
puts $f "the_ROM_image:\n{\n\t\[bootloader\]$fsbl\n\t$bit\n\t$elf\n}"
close $f

exec bootgen -image $bif -arch zynq -o "$out/BOOT.BIN" -w on
puts "BOOT.BIN -> $out/BOOT.BIN"
