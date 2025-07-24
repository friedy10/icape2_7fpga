
add_force sys_clk {0} {1 500ps} -repeat_every 1ns
add_force clk_sel {1} -cancel_after 2us

open_vcd sim.vcd
log_vcd -level 1 [get_objects 				\
	/top/CLK /top/I /top/CSIB /top/RDWRB /top/O	\
	/top/FAR /top/SYNDROME /top/SYNWORD /top/SYNBIT	\
	/top/CRCERROR /top/ECCERROR /top/ECCERRORSINGLE	\
	/top/SYNDROMEVALID ]

run 2ms
current_time

flush_vcd 
close_vcd

quit
