# vivado_upload.tcl
#	Cmod A7 simple upload script
#	Version 1.0
# 
# Copyright (C) 2017 H.Poetzl

set ODIR .

open_hw
connect_hw_server
open_hw_target
set_property PROGRAM.FILE $ODIR/icap.bit [get_hw_devices xc7a*]
program_hw_devices [get_hw_devices xc7a*]

puts "MESSAGE: upload done."

