# debug_boot.tcl -- teste la DDR et suit le demarrage instruction par instruction
#   xsct sw/scripts/debug_boot.tcl
set script_dir [file normalize [file dirname [info script]]]
set root       [file normalize "$script_dir/../.."]
set ws         "$root/sw/workspace"
set bit        "$root/hw/build/out/top.bit"
set elf        "$ws/kws_app/Release/kws_app.elf"
set hdf        [lindex [glob -nocomplain $ws/hw0/*.hdf] 0]
proc hx {a} { if {[catch {set v [format 0x%08X [lindex [mrd -value $a] 0]]} e]} { return "ERREUR" }; return $v }

puts "fichiers : bit=[file exists $bit] elf=[file exists $elf] hdf=$hdf"
puts "date elf : [clock format [file mtime $elf]]"
connect
source $ws/hw0/ps7_init.tcl
targets
targets -set -nocase -filter {name =~ "APU*"}
rst -system
after 3000
fpga -file $bit
targets -set -nocase -filter {name =~ "APU*"}
catch {loadhw -hw $hdf -mem-ranges [list {0x40000000 0xbfffffff}]}
configparams force-mem-access 1
targets -set -nocase -filter {name =~ "APU*"}
ps7_init
ps7_post_config

puts "\n===== 1. TEST DDR ====="
set ok 1
foreach a {0x00100000 0x00200000 0x01000000 0x10000000 0x1F000000} p {0xDEADBEEF 0x12345678 0xA5A5A5A5 0x5A5A5A5A 0x0F0F0F0F} {
    catch {mwr $a $p}
    set r [hx $a]
    if {$r ne [format 0x%08X $p]} { set ok 0 }
    puts [format "%s ecrit %08X lu %s" $a $p $r]
}
puts [expr {$ok ? "DDR OK" : "!!! DDR DEFECTUEUSE (ps7_init / preset carte)"}]

puts "\n===== 2. HORLOGE UART ====="
set uclk [lindex [mrd -value 0xF8000154] 0]
set iopll [lindex [mrd -value 0xF8000108] 0]
set div [expr {($uclk >> 8) & 0x3F}]
set fdiv [expr {($iopll >> 12) & 0x7F}]
set bg [lindex [mrd -value 0xE0001018] 0]
set bd [lindex [mrd -value 0xE0001034] 0]
if {$div > 0 && $bg > 0} {
    set fref [expr {33.333333e6 * $fdiv / $div}]
    puts [format "UART_CLK_CTRL=0x%08X IO_PLL x%d div %d -> ref %.2f MHz ; BAUDGEN=%d BAUDDIV=%d -> %.0f bauds" \
          $uclk $fdiv $div [expr {$fref/1e6}] $bg $bd [expr {$fref/($bg*($bd+1))}]]
} else { puts "UART_CLK_CTRL=[format 0x%08X $uclk] BAUDGEN=$bg" }

targets -set -nocase -filter {name =~ "*A9*#0"}
dow $elf
configparams force-mem-access 0

puts "\n===== 3. VERIFICATION DU CODE EN MEMOIRE ====="
if {[catch {verify $elf} e]} { puts "verify : $e" } else { puts "verify : OK" }
puts "0x00100000 = [hx 0x00100000]   0x00100004 = [hx 0x00100004]"

puts "\n===== 4. DEMARRAGE INSTRUCTION PAR INSTRUCTION ====="
for {set i 0} {$i < 60} {incr i} {
    if {[catch {stpi} e]} { puts "stpi $i : $e"; break }
    if {[catch {set pc [lindex [rrd pc] 1]} e]} { set pc "?" }
    set fn ""
    catch {set fn [lindex [bt] 1]}
    puts "$i  pc=$pc  $fn"
    if {[string match "0000000*" $pc] || [string match "00000010" $pc]} { puts "!!! saut vers les vecteurs bas"; break }
}

puts "\n===== 5. EXECUTION LIBRE 3 s ====="
catch {bpadd -addr &main}
set r [catch {con -block -timeout 3} e]
catch {stop}
after 100
catch {puts "pc = [rrd pc]"}
catch {puts [bt]}
catch {puts "CPSR = [rrd cpsr]"}
catch {puts "DFSR = [rrd cp15 c5]"}
catch {puts "DFAR = [rrd cp15 c6]"}
catch {puts "VBAR = [rrd cp15 c12]"}
puts "\nfin"
