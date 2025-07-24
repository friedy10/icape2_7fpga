# vivado.tcl
#	Cmod A7 simple build script
#	Version 1.0
# 
# Copyright (C) 2017 H.Poetzl

set ODIR .

# STEP#1: setup design sources and constraints

read_vhdl ../top.vhd

read_xdc ../top.xdc

set_property PART xc7a35tcpg236-1 [current_project]
set_property BOARD_PART digilentinc.com:cmod_a7-35t:part0:1.1 [current_project]
set_property TARGET_LANGUAGE VHDL [current_project]

# STEP#2: run synthesis, write checkpoint design

synth_design -top top 

# STEP#3: run placement and logic optimzation, write checkpoint design

opt_design -propconst -sweep -retarget -remap
place_design -directive ExtraTimingOpt
phys_opt_design -critical_cell_opt -critical_pin_opt -placement_opt -hold_fix -rewire -retime

# STEP#4: run router, write checkpoint design

route_design -directive NoTimingRelaxation
# write_checkpoint -force $ODIR/post_route

report_timing -no_header -path_type summary -max_paths 1000 -slack_lesser_than 0 -setup
report_timing -no_header -path_type summary -max_paths 1000 -slack_lesser_than 0 -hold

# STEP#5: generate a bitstream

set_property CONFIG_VOLTAGE 3.3 [current_design]
set_property CFGBVS VCCO [current_design]

set_property BITSTREAM.GENERAL.COMPRESS False [current_design]
set_property BITSTREAM.GENERAL.CRC "DISABLE" [current_design]
set_property BITSTREAM.CONFIG.USERID "DEADC0DE" [current_design]
set_property BITSTREAM.CONFIG.USR_ACCESS "00000000" [current_design]
set_property BITSTREAM.READBACK.ACTIVERECONFIG Yes [current_design]

write_bitstream -raw_bitfile -readback_file -bin_file -force $ODIR/icap

# STEP#6: generate reports

report_clocks

report_utilization -hierarchical -file utilization.rpt
report_clock_utilization -file utilization.rpt -append
report_datasheet -file datasheet.rpt
report_timing_summary -file timing.rpt

puts "MESSAGE: build done."
source ../vivado_upload.tcl
