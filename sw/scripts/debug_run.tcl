# debug_run.tcl -- relance l'application sous debogueur et indique OU elle plante
#   xsct sw/scripts/debug_run.tcl
set script_dir [file normalize [file dirname [info script]]]
set root       [file normalize "$script_dir/../.."]
set ws         "$root/sw/workspace"
set bit        "$root/hw/build/out/top.bit"
set elf        "$ws/kws_app/Release/kws_app.elf"
set hdf        [lindex [glob -nocomplain $ws/hw0/*.hdf] 0]

proc where {} {
    if {[catch {set b [bt]}]} { set b "(bt indisponible)" }
    if {[catch {set p [rrd pc]}]} { set p "?" }
    return "$p\n$b"
}

connect
source $ws/hw0/ps7_init.tcl
targets -set -nocase -filter {name =~ "APU*"}
rst -system
after 3000
fpga -file $bit
targets -set -nocase -filter {name =~ "APU*"}
if {$hdf ne ""} { catch {loadhw -hw $hdf -mem-ranges [list {0x40000000 0xbfffffff}]} }
configparams force-mem-access 1
targets -set -nocase -filter {name =~ "APU*"}
ps7_init
ps7_post_config
targets -set -nocase -filter {name =~ "*A9*#0"}
dow $elf
configparams force-mem-access 0

puts "\n===== Horloge UART (vitesse reelle) ====="
if {[catch {
    set uclk [lindex [mrd -value 0xF8000154] 0]
    set iopll [lindex [mrd -value 0xF8000108] 0]
    set armpll [lindex [mrd -value 0xF8000100] 0]
    set ddrpll [lindex [mrd -value 0xF8000104] 0]
    set div [expr {($uclk >> 8) & 0x3F}]
    set src [expr {($uclk >> 4) & 0x3}]
    switch $src { 2 {set pll $armpll} 3 {set pll $ddrpll} default {set pll $iopll} }
    set fdiv [expr {($pll >> 12) & 0x7F}]
    set fpll [expr {33.333333e6 * $fdiv}]
    set fref [expr {$fpll / $div}]
    set bg [lindex [mrd -value 0xE0001018] 0]
    set bd [lindex [mrd -value 0xE0001034] 0]
    set baud [expr {$fref / ($bg * ($bd + 1))}]
    puts [format "UART_CLK_CTRL=0x%08X src=%d div=%d  PLL=%.1f MHz  ref UART=%.3f MHz" $uclk $src $div [expr {$fpll/1e6}] [expr {$fref/1e6}]]
    puts [format "BAUDGEN=%d BAUDDIV=%d  -> VITESSE REELLE = %.0f bauds" $bg $bd $baud]
} e]} { puts "lecture horloge impossible : $e" }

puts "\n===== Registres du peripherique audio (lus par JTAG) ====="
after 1000
foreach {off name} {0x04 STATUS 0x0C FRAMES 0x14 VERSION 0x0C FRAMES_1s_plus_tard} {
    after 500
    if {[catch {set v [format 0x%08X [lindex [mrd -value [expr {0x43C00000 + $off}]] 0]]} e]} { set v "ERREUR : $e" }
    puts [format "%-8s %s" $name $v]
}

# points d'arret : etapes du programme + gestionnaires d'exception
set bps {main mfcc_init resample_init set_leds
         Xil_DataAbortHandler Xil_PrefetchAbortHandler Xil_UndefinedExceptionHandler
         Xil_SWIHandler FIQInterrupt IRQInterrupt}
foreach f $bps {
    if {[catch {bpadd -addr &$f} e]} { puts "(pas de point d'arret sur $f)" }
}

puts "\n===== Execution pas a pas (points d'arret) ====="
for {set i 0} {$i < 8} {incr i} {
    set r [catch {con -block -timeout 6} e]
    set w [where]
    if {$r} {
        catch {stop}
        after 200
        puts "\n>>> AUCUN point d'arret atteint en 6 s (timeout) : le programme tourne ou boucle ici :"
        puts [where]
        break
    }
    puts "\n>>> arret $i :"
    puts $w
    if {[string match "*Abort*" $w] || [string match "*Undefined*" $w] || [string match "*SWI*" $w]} {
        puts "\n!!! EXCEPTION. Adresse fautive :"
        foreach v {DataAbortAddr PrefetchAbortAddr UndefinedExceptionAddr} {
            catch {puts "$v = [print $v]"}
        }
        catch {puts "DFSR/DFAR (cause) : [rrd cp15 c5]  [rrd cp15 c6]"}
        catch {puts "registres :\n[rrd]"}
        break
    }
    if {[string match "*set_leds*" $w]} {
        puts "\n=== set_leds atteint : le programme a demarre normalement (regardez PuTTY) ==="
        bpremove -all
        con
        break
    }
}
puts "\nfin du diagnostic"
