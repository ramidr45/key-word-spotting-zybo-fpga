# diag_board.tcl -- diagnostic : ou en est le processeur, l'UART, le peripherique audio
#   xsct sw/scripts/diag_board.tcl      (l'application doit avoir ete lancee avant)
connect
targets -set -nocase -filter {name =~ "*A9*#0"}
puts "\n===== 1. ETAT DU PROCESSEUR ====="
catch {stop}
after 200
if {[catch {puts [bt]} e]} { puts "bt indisponible : $e" }
catch {puts "PC = [rrd pc]"}

puts "\n===== 2. PERIPHERIQUE AUDIO (0x43C00000) ====="
foreach {off name} {0x00 CTRL 0x04 STATUS 0x0C FRAMES 0x10 LEDS 0x14 VERSION 0x1C INPUTS 0x24 LEVEL} {
    if {[catch {set v [lindex [mrd -value [expr {0x43C00000 + $off}]] 0]} e]} { set v "ERREUR($e)" } else { set v [format 0x%08X $v] }
    puts [format "%-8s %s" $name $v]
}

puts "\n===== 3. UART1 (0xE0001000, port USB de la Zybo) ====="
foreach {off name} {0x00 CR 0x04 MR 0x18 BAUDGEN 0x34 BAUDDIV 0x2C SR} {
    if {[catch {set v [format 0x%08X [lindex [mrd -value [expr {0xE0001000 + $off}]] 0]]} e]} { set v "ERREUR" }
    puts [format "%-8s %s" $name $v]
}
puts "\n===== 4. UART0 (0xE0000000, pour comparaison) ====="
foreach {off name} {0x00 CR 0x18 BAUDGEN 0x34 BAUDDIV} {
    if {[catch {set v [format 0x%08X [lindex [mrd -value [expr {0xE0000000 + $off}]] 0]]} e]} { set v "ERREUR" }
    puts [format "%-8s %s" $name $v]
}

puts "\n===== 5. TEST ECRITURE DIRECTE SUR UART1 ====="
foreach c [split "\r\n*** TEST UART ZYBO : si vous lisez ceci dans PuTTY, le port COM est bon ***\r\n" ""] {
    scan $c %c code
    catch {mwr 0xE0001030 $code}
    after 2
}
puts "Texte envoye -> regardez PuTTY"

catch {con}
puts "\nProcesseur relance."
