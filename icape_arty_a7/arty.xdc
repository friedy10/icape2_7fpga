# Arty A7 Constraints for ICAP Example
# Save this as: icap_arty_a7.xdc

# Clock signal (100 MHz)
set_property PACKAGE_PIN E3 [get_ports clk]
set_property IOSTANDARD LVCMOS33 [get_ports clk]
create_clock -add -name sys_clk_pin -period 10.00 -waveform {0 5} [get_ports clk]

# Reset button (BTN0 - active low)
set_property PACKAGE_PIN D9 [get_ports rst_n]
set_property IOSTANDARD LVCMOS33 [get_ports rst_n]

# UART TX (to USB-UART bridge)
set_property PACKAGE_PIN D10 [get_ports uart_tx]
set_property IOSTANDARD LVCMOS33 [get_ports uart_tx]

# Configuration Mode Settings
set_property CFGBVS VCCO [current_design]
set_property CONFIG_VOLTAGE 3.3 [current_design]

# Bitstream Settings for faster programming
set_property BITSTREAM.GENERAL.COMPRESS TRUE [current_design]
set_property BITSTREAM.CONFIG.CONFIGRATE 33 [current_design]
set_property CONFIG_MODE SPIx4 [current_design]