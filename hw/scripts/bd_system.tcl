# ------------------------------------------------------------------------------
# bd_system.tcl -- Block Design "system" pour la Zybo Z7-10
#   PS7 (preset carte) + Clocking Wizard (12.288 MHz) + kws_audio_axi (module ref)
# Appele par build_hw.tcl (le projet doit deja exister et contenir les sources RTL)
# ------------------------------------------------------------------------------

set bd_name system
create_bd_design $bd_name

# --- Zynq PS7 ------------------------------------------------------------------
set ps7 [create_bd_cell -type ip -vlnv xilinx.com:ip:processing_system7 processing_system7_0]
apply_bd_automation -rule xilinx.com:bd_rule:processing_system7 \
    -config {make_external "FIXED_IO, DDR" apply_board_preset "1" Master "Disable" Slave "Disable"} $ps7
set_property -dict [list \
    CONFIG.PCW_FPGA0_PERIPHERAL_FREQMHZ {100} \
    CONFIG.PCW_USE_M_AXI_GP0 {1} \
    CONFIG.PCW_EN_CLK0_PORT {1} \
    CONFIG.PCW_EN_RST0_PORT {1} \
    CONFIG.PCW_UART1_PERIPHERAL_ENABLE {1} \
    CONFIG.PCW_UART1_BAUD_RATE {115200} \
] $ps7

# --- Clocking Wizard : MCLK 12.288 MHz pour le codec ----------------------------
set cw [create_bd_cell -type ip -vlnv xilinx.com:ip:clk_wiz clk_wiz_0]
set_property -dict [list \
    CONFIG.PRIM_SOURCE {No_buffer} \
    CONFIG.PRIM_IN_FREQ {100.000} \
    CONFIG.CLKOUT1_REQUESTED_OUT_FREQ {12.288} \
    CONFIG.USE_RESET {false} \
    CONFIG.USE_LOCKED {true} \
] $cw
connect_bd_net [get_bd_pins processing_system7_0/FCLK_CLK0] [get_bd_pins clk_wiz_0/clk_in1]

# --- peripherique audio (module reference sur l'entite VHDL) ---------------------
set kws [create_bd_cell -type module -reference kws_audio_axi kws_audio_0]

apply_bd_automation -rule xilinx.com:bd_rule:axi4 \
    -config {Master "/processing_system7_0/M_AXI_GP0" Clk "Auto"} \
    [get_bd_intf_pins kws_audio_0/S_AXI]

connect_bd_net [get_bd_pins clk_wiz_0/locked] [get_bd_pins kws_audio_0/mclk_locked]

# --- ports externes (memes noms que dans top.vhd) --------------------------------
create_bd_port -dir O -type clk mclk
connect_bd_net [get_bd_pins clk_wiz_0/clk_out1] [get_bd_ports mclk]

foreach p {ac_bclk ac_reclrc ac_recdat ac_sda_i} {
    create_bd_port -dir I $p
    connect_bd_net [get_bd_ports $p] [get_bd_pins kws_audio_0/$p]
}
foreach p {ac_pbdat ac_muten ac_scl_t ac_sda_t} {
    create_bd_port -dir O $p
    connect_bd_net [get_bd_pins kws_audio_0/$p] [get_bd_ports $p]
}
create_bd_port -dir O -from 3 -to 0 led
connect_bd_net [get_bd_pins kws_audio_0/led] [get_bd_ports led]
create_bd_port -dir O -from 2 -to 0 rgb
connect_bd_net [get_bd_pins kws_audio_0/rgb] [get_bd_ports rgb]
create_bd_port -dir I -from 3 -to 0 sw
connect_bd_net [get_bd_ports sw] [get_bd_pins kws_audio_0/sw]
create_bd_port -dir I -from 3 -to 0 btn
connect_bd_net [get_bd_ports btn] [get_bd_pins kws_audio_0/btn]

# --- adresses : base fixe 0x43C0_0000 (utilisee dans sw/src/kws_hw.h) -------------
assign_bd_address
foreach seg [get_bd_addr_segs -of_objects [get_bd_addr_spaces processing_system7_0/Data]] {
    if {[string match "*kws_audio_0*" $seg]} {
        set_property offset 0x43C00000 $seg
        set_property range 64K $seg
        puts "INFO: segment $seg -> 0x43C00000"
    }
}

regenerate_bd_layout
validate_bd_design
save_bd_design
