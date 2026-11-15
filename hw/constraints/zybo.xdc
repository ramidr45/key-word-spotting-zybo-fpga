## Zybo (premiere generation, Zynq-7010, avec port VGA) -- Keyword Spotting audio
## Broches issues du fichier maitre Digilent ZYBO_Master.xdc (Rev B)

## Switches SW0..SW3
set_property -dict { PACKAGE_PIN G15 IOSTANDARD LVCMOS33 } [get_ports { sw[0] }]
set_property -dict { PACKAGE_PIN P15 IOSTANDARD LVCMOS33 } [get_ports { sw[1] }]
set_property -dict { PACKAGE_PIN W13 IOSTANDARD LVCMOS33 } [get_ports { sw[2] }]
set_property -dict { PACKAGE_PIN T16 IOSTANDARD LVCMOS33 } [get_ports { sw[3] }]

## Boutons BTN0..BTN3
set_property -dict { PACKAGE_PIN R18 IOSTANDARD LVCMOS33 } [get_ports { btn[0] }]
set_property -dict { PACKAGE_PIN P16 IOSTANDARD LVCMOS33 } [get_ports { btn[1] }]
set_property -dict { PACKAGE_PIN V16 IOSTANDARD LVCMOS33 } [get_ports { btn[2] }]
set_property -dict { PACKAGE_PIN Y16 IOSTANDARD LVCMOS33 } [get_ports { btn[3] }]

## LEDs LD0..LD3
set_property -dict { PACKAGE_PIN M14 IOSTANDARD LVCMOS33 } [get_ports { led[0] }]
set_property -dict { PACKAGE_PIN M15 IOSTANDARD LVCMOS33 } [get_ports { led[1] }]
set_property -dict { PACKAGE_PIN G14 IOSTANDARD LVCMOS33 } [get_ports { led[2] }]
set_property -dict { PACKAGE_PIN D18 IOSTANDARD LVCMOS33 } [get_ports { led[3] }]

## Codec audio SSM2603
set_property -dict { PACKAGE_PIN K18 IOSTANDARD LVCMOS33 } [get_ports { ac_bclk }]
set_property -dict { PACKAGE_PIN T19 IOSTANDARD LVCMOS33 } [get_ports { ac_mclk }]
set_property -dict { PACKAGE_PIN P18 IOSTANDARD LVCMOS33 } [get_ports { ac_muten }]
set_property -dict { PACKAGE_PIN M17 IOSTANDARD LVCMOS33 } [get_ports { ac_pbdat }]
set_property -dict { PACKAGE_PIN K17 IOSTANDARD LVCMOS33 } [get_ports { ac_recdat }]
set_property -dict { PACKAGE_PIN M18 IOSTANDARD LVCMOS33 } [get_ports { ac_reclrc }]
set_property -dict { PACKAGE_PIN N18 IOSTANDARD LVCMOS33 PULLUP true } [get_ports { ac_scl }]
set_property -dict { PACKAGE_PIN N17 IOSTANDARD LVCMOS33 PULLUP true } [get_ports { ac_sda }]

## Timing : E/S lentes et asynchrones (resynchronisees dans le domaine 100 MHz)
set_false_path -from [get_ports { ac_bclk ac_reclrc ac_recdat ac_sda ac_scl sw[*] btn[*] }]
set_false_path -to   [get_ports { ac_pbdat ac_muten ac_scl ac_sda led[*] }]
