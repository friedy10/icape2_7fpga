----------------------------------------------------------------------------
--  top.vhd
--	Cmod A7 simple VHDL example
--	Version 1.0
--
--  Copyright (C) 2017 H.Poetzl
--
--	This program is free software: you can redistribute it and/or
--	modify it under the terms of the GNU General Public License
--	as published by the Free Software Foundation, either version
--	2 of the License, or (at your option) any later version.
--
--  Vivado 2017.2:
--    mkdir -p build.vivado
--    (cd build.vivado && vivado -mode tcl -source ../vivado.tcl)
--
--  Simulation:
--    mkdir -p sim.vivado
--    (cd sim.vivado && xvhdl ../top.vhd)
--    (cd sim.vivado && xelab -debug typical top -s sim)
--    (cd sim.vivado && xsim sim -tclbatch ../vivado_sim.tcl)
----------------------------------------------------------------------------


library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.ALL;

library STD;
use STD.textio.ALL;

library unisim;
use unisim.VCOMPONENTS.ALL;


entity top is
    port (
	sys_clk : in std_logic;
	--
	uart_tx : out std_logic
    );
end entity top;


architecture RTL of top is

    pure function ord (ch : character)
	return natural is
	variable pos_v : natural;
    begin
	return character'pos(ch);
    end ord;

    pure function asc (ch : character)
	return std_logic_vector is
    begin
	return std_logic_vector(to_unsigned(ord(ch), 8));
    end asc;

    type htoa_t is array (natural range <>) of
	std_logic_vector (7 downto 0);

    constant htoa_c : htoa_t(0 to 15) := (
	asc('0'), asc('1'), asc('2'), asc('3'),
	asc('4'), asc('5'), asc('6'), asc('7'),
	asc('8'), asc('9'), asc('A'), asc('B'),
	asc('C'), asc('D'), asc('E'), asc('F') );

    function htoa_f (hex : std_logic_vector)
	return std_logic_vector is
    begin
	return htoa_c(to_integer(
	    unsigned(hex(hex'low+3 downto hex'low))));
    end function;


    pure function rev_f(v : std_logic_vector(31 downto 0)) 
	return std_logic_vector is
	variable j_v : natural;
	variable res_v : std_logic_vector(v'range);	
    begin
	for I in v'range loop
	    j_v := (7-(I mod 8)) + (I/8)*8;
	    res_v(j_v) := v(I);
	end loop;
	return res_v;
    end rev_f;

    --------------------------------------------------------------------
    -- ICAP Signals
    --------------------------------------------------------------------

    signal I : std_logic_vector(31 downto 0) := (others => '0');
    signal O : std_logic_vector(31 downto 0);

    signal CLK : std_logic := '0';
    signal CSIB : std_logic := '0';
    signal RDWRB : std_logic := '0';

    --------------------------------------------------------------------
    -- FRAME_ECC Signals
    --------------------------------------------------------------------

    signal FAR : std_logic_vector(25 downto 0);
    signal SYNDROME : std_logic_vector(12 downto 0);
    signal SYNWORD : std_logic_vector(6 downto 0);
    signal SYNBIT : std_logic_vector(4 downto 0);
 
    signal CRCERROR : std_logic;
    signal ECCERROR : std_logic;
    signal ECCERRORSINGLE : std_logic;
    signal SYNDROMEVALID : std_logic;

    --------------------------------------------------------------------
    -- UART/Output Signals
    --------------------------------------------------------------------

    signal result : std_logic_vector(127 downto 0);

    signal cout : std_logic_vector(7 downto 0) := (others => '0');
    signal cout_en : std_logic := '0';
    signal cout_clk : std_logic;

    signal icap : std_logic_vector(33 downto 0) := (others => '1');
    signal icap_en : std_logic := '0';
    signal icap_clk : std_logic;

    signal isep_en : std_logic := '0';

    signal clk_sel : std_logic := '0';

    --------------------------------------------------------------------
    -- ICAP Sequence
    --------------------------------------------------------------------

    type seq_t is array (natural range <>) of
	std_logic_vector(33 downto 0);

    constant SEQ_WRITE : seq_t(0 to 13) := (
	"00" & x"AA995566",	-- Sync word
	"00" & x"20000000",	-- NOP

	"00" & x"30008001",	-- Write #1 @CMD
	"00" & x"00000007",	-- CMD RCRC
	"00" & x"20000000",	-- NOP
	"00" & x"20000000",	-- NOP

	"00" & x"30018001",	-- Write #1 @IDCODE
	"00" & x"0362D093",	-- Data

	"00" & x"30008001",	-- Write #1 @CMD
	"00" & x"00000001",	-- CMD WCFG
	"00" & x"20000000",	-- NOP

	"00" & x"30002001",	-- Write #1 @FAR
	"00" & x"0002051A",	-- Frame = 0002051A

	"00" & x"300040CA" );	-- Write #202 @FDRI

    constant SEQ_RBACK : seq_t(0 to 10) := (
	"00" & x"AA995566",	-- Sync word
	"00" & x"20000000",	-- NOP
	"00" & x"20000000",	-- NOP
	"00" & x"20000000",	-- NOP

	"00" & x"30008001",	-- Write #1 @CMD
	"00" & x"00000004",	-- CMD RCFG
	"00" & x"20000000",	-- NOP

	"00" & x"30002001",	-- Write #1 @FAR
	"00" & x"0002051A",	-- Frame = 0002051A

	"00" & x"2800612F",	-- Read #303 @FDRO
	"11" & x"20000000" );	-- NOP #CE,R

    constant SEQ_DESYN : seq_t(0 to 6) := (
	"00" & x"30008001",	-- Write #1 @CMD
	"00" & x"0000000D",	-- CMD DESYNC
	"00" & x"20000000",	-- NOP
	"00" & x"20000000",	-- NOP
	"00" & x"20000000",	-- NOP
	"11" & x"20000000",	-- NOP #CE,R
	"11" & x"FFFFFFFF" );	-- Dymmy #CE,R


    constant OFF_WRITE : natural := 256;
    constant OFF_WDATA : natural := OFF_WRITE + SEQ_WRITE'length;

    constant OFF_FAULT : natural := OFF_WDATA + 5;

    constant OFF_WDSYN : natural := OFF_WDATA + 202;
    constant OFF_WDONE : natural := OFF_WDSYN + SEQ_DESYN'length;

    constant OFF_RBACK : natural := 512;
    constant OFF_RDATA : natural := OFF_RBACK + SEQ_RBACK'length;

    constant OFF_RDSYN : natural := OFF_RDATA + 303;
    constant OFF_RDONE : natural := OFF_RDSYN + SEQ_DESYN'length;

    --------------------------------------------------------------------
    -- Simulation
    --------------------------------------------------------------------

    file fout : text open write_mode is "serial.out";

begin

    --------------------------------------------------------------------
    -- ICAP Interface
    --------------------------------------------------------------------

    ICAP_inst : ICAPE2
	generic map ( 
	    DEVICE_ID => x"0362D093",
	    ICAP_WIDTH => "X32" ) 		-- Specifies the input and output data width. 
	port map ( 
	    I => I, 				-- 32-bit input: Configuration data input bus 
	    CLK => CLK, 			-- 1-bit input: Clock Input 
	    CSIB => CSIB, 			-- 1-bit input: Active-Low ICAP Enable 
	    RDWRB => RDWRB,		 	-- 1-bit input: Read/Write Select input 
	    O => O );				-- 32-bit output: Configuration data output bus 

    BUFGMUX_inst : BUFGMUX
	port map (
	    I0 => icap_clk,
	    I1 => sys_clk,
	    O => CLK,
	    S => clk_sel );

    CSIB <= icap(33);
    RDWRB <= icap(32);
    I <= rev_f(icap(31 downto 0));

    --------------------------------------------------------------------
    -- FRAME_ECC Instance
    --------------------------------------------------------------------

    FRAME_ECC_inst : FRAME_ECCE2 
	generic map ( 
	    FRAME_RBT_IN_FILENAME => "frame.rbt",
	    FARSRC => "EFAR" )
	port map ( 
	    FAR => FAR,				-- 26-bit output: Frame Address Register Value output. 
	    SYNDROME => SYNDROME,		-- 13-bit output: Output location of erroneous bit. 
	    SYNWORD => SYNWORD,			-- 7-bit output: Word output in the frame where an ECC error has been detected.
	    SYNBIT => SYNBIT,			-- 5-bit output: Output bit address of error. 
	    --
	    CRCERROR => CRCERROR,		-- 1-bit output: Output indicating a CRC error. 
	    ECCERROR => ECCERROR,		-- 1-bit output: Output indicating an ECC error. 
	    ECCERRORSINGLE => ECCERRORSINGLE,	-- 1-bit output: Output Indicating single-bit Frame ECC error detected. 
	    SYNDROMEVALID => SYNDROMEVALID );	-- 1-bit output: Frame ECC output indicating the SYNDROME output is valid. 

    --------------------------------------------------------------------
    -- ICAP Procedure
    --------------------------------------------------------------------

    icap_proc : process(icap_clk)
	variable cnt_v : natural range 0 to 1023 := 0;
    begin
	if rising_edge(icap_clk) then
	    icap <= "11" & x"FFFFFFFF";
	    icap_en <= '1';
	    isep_en <= '0';

	    case cnt_v is
		when OFF_WRITE-1|OFF_WDONE|OFF_RDONE =>
		    isep_en <= '1';
		    icap_en <= '0';


		when OFF_WRITE to OFF_WDATA-1 =>
		    icap <= SEQ_WRITE(cnt_v - OFF_WRITE);
		
		when OFF_WDATA to OFF_FAULT-1 =>
		    icap <= "00" & x"00000000";

		when OFF_FAULT =>
		    icap <= "00" & x"00001000";

		when OFF_FAULT+1 to OFF_WDSYN-1 =>
		    icap <= "00" & x"00000000";

		when OFF_WDSYN to OFF_WDONE-1 =>
		    icap <= SEQ_DESYN(cnt_v - OFF_WDSYN);


		when OFF_RBACK to OFF_RDATA-1 =>
		    icap <= SEQ_RBACK(cnt_v - OFF_RBACK);
		
		when OFF_RDATA to OFF_RDSYN-1 =>
		    icap <= "01" & x"20000000";

		when OFF_RDSYN to OFF_RDONE-1 =>
		    icap <= SEQ_DESYN(cnt_v - OFF_RDSYN);


		when others =>
		    icap_en <= '0';
	    end case;	

	    if cnt_v < 1023 then
		cnt_v := cnt_v + 1;
	    end if;
	end if;
    end process;


    --------------------------------------------------------------------
    -- Output Procedure
    --------------------------------------------------------------------

    cout_proc : process(cout_clk)
	variable cnt_v : natural range 0 to 39 := 0;
	variable idx_v : natural range 0 to 127;
	variable sep_v : natural range 0 to 15;
	variable wdl_v : line;
    begin
	if rising_edge(cout_clk) then
	    cout_en <= '1';

	    if icap_en = '1' then
		case cnt_v is
		    when 0 to 7|9 to 16|18 to 25|27 to 34 =>
			idx_v := (31 - cnt_v + cnt_v/9)*4;
			cout <= htoa_f(result(idx_v+3 downto idx_v));

		    when 8|17|26 => cout <= asc('.');
		    when 35      => cout <= x"0A";
		    when 36      => cout <= x"0D";
		    when others => 
			cout <= x"00";
			cout_en <= '0';
		end case;

	    elsif isep_en = '1' then
		case cnt_v is
		    when 5 => 
			cout <= htoa_c(sep_v);
			sep_v := sep_v + 1;

		    when 0|1|4|6 => cout <= asc(' ');
		    when 2|3|7|8 => cout <= asc('-');
		    when 35      => cout <= x"0A";
		    when 36      => cout <= x"0D";
		    when others => 
			cout <= x"00";
			cout_en <= '0';
		end case;

	    else
		cout_en <= '0';
	    end if;

	    if cnt_v = 39 then
		result <= rev_f(I) & rev_f(O) & 
		    CSIB & RDWRB & "00" & "00" & FAR & 
		    "000" & SYNDROME & SYNWORD & SYNBIT & 
		    CRCERROR & ECCERRORSINGLE & ECCERROR &
		    SYNDROMEVALID;

		icap_clk <= '1';
		cnt_v := 0;

	    elsif cnt_v = 19 then
		icap_clk <= '0';
		cnt_v := cnt_v + 1;

	    else
		cnt_v := cnt_v + 1;
	    end if;

	    if cout_en = '1' then
		if cout = x"0D" then
		    WRITELINE(fout, wdl_v);
		elsif cout /= x"0A" then
		    WRITE(wdl_v, character'val(to_integer(unsigned(cout))));
		end if;
	    end if;
	end if;
    end process;

    --------------------------------------------------------------------
    -- UART Procedure
    --------------------------------------------------------------------

    uart_proc : process(sys_clk)
	variable cnt_v : natural range 0 to 12*3-1 := 0;
	variable seq_v : natural range 0 to 11;
    begin
	if rising_edge(sys_clk) then
	    seq_v := cnt_v / 3;
	
	    if cout_en = '1' then
		case seq_v is
		    when 0      => uart_tx <= '0';
		    when 1 to 8 => uart_tx <= cout(seq_v - 1);
		    when others => uart_tx <= '1';
		end case;
	    else
		uart_tx <= '1';
	    end if;

	    if seq_v < 6 then
	    	cout_clk <= '1';
	    else
	    	cout_clk <= '0';
	    end if;

	    if cnt_v = 12*3-1 then
		cnt_v := 0;
	    else
		cnt_v := cnt_v + 1;
	    end if;
	end if;
    end process;

end RTL;
