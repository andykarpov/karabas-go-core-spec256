-------------------------------------------------------------------------------
-- tb_s256: T80se_S256 (the T80 with the Spec256 lanes) against T80se.
--
-- Both CPUs run the same game: the 48K ROM and a .256 file (SNA RAM, the 8
-- planes, the registers, as games/spec256.py writes it), started as the core
-- starts it (DIRSet with PC = 0x0072, a RETN in the ROM). CLKEN is always 1,
-- a clock is a T-state; INT every 69888 clocks.
--
-- Checked on every clock:
-- - the main CPU of T80se_S256 against T80se: every bus output and REG;
-- - G_NATURAL: the planes are copies of the SNA RAM instead of the GFX, so
--   every lane must be the main CPU: GREG of each lane = REG, GDO = DO.
-- - G_TABLE (gen_table.py): at the end lane p has A = 1 << (7 - p), the entry
--   of its own byte in a table of reversed bytes (the lane addresses, GA).
-- The lanes read the memory at their own address (GA) when GA_EN is set.
-- G_TRACE: a line per instruction (the M1 of each opcode byte) with REG
-- and GREG, for the comparison with the GZX reference (sim/gzx).
--
-- Prints "tb_s256: <n> errors".
-------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;

entity tb_s256 is
	generic (
		G_FILE256    : string  := "";
		G_ROM        : string  := "";
		G_NATURAL    : boolean := true;   -- planes = SNA RAM
		G_IMM_MASTER : boolean := true;   -- operands of the instruction stream from the main memory
		G_CYCLES     : integer := 1000000;
		G_TABLE      : boolean := false;  -- the lane address test of gen_table.py
		G_LOG_GA     : boolean := false;
		G_TABLE_PAGE : integer := 16#80#;  -- the page of the table of reversed bytes (the .256 header)  -- print the reads where a lane has an address of its own
		G_TRACE      : string  := "";
		G_MAX_REPORT : integer := 20
	);
end tb_s256;

architecture sim of tb_s256 is
	constant LANES : integer := 8;
	constant FRAME : integer := 69888;

	signal clk     : std_logic := '0';
	signal reset_n : std_logic := '0';
	signal dirset  : std_logic := '0';
	signal dir     : std_logic_vector(211 downto 0) := (others => '0');
	signal int_n   : std_logic := '1';
	signal done    : boolean := false;
	signal cycle   : integer := 0;

	-- T80se (reference)
	signal r_m1_n, r_mreq_n, r_iorq_n, r_rd_n, r_wr_n, r_rfsh_n, r_halt_n : std_logic;
	signal r_a   : std_logic_vector(15 downto 0);
	signal r_di, r_do : std_logic_vector(7 downto 0) := (others => '1');
	signal r_reg : std_logic_vector(211 downto 0);

	-- T80se_S256
	signal d_m1_n, d_mreq_n, d_iorq_n, d_rd_n, d_wr_n, d_rfsh_n, d_halt_n : std_logic;
	signal d_a   : std_logic_vector(15 downto 0);
	signal d_di, d_do : std_logic_vector(7 downto 0) := (others => '1');
	signal d_reg : std_logic_vector(211 downto 0);
	signal d_mc, d_ts : std_logic_vector(2 downto 0);
	signal d_inst : std_logic;
	signal d_gdi  : std_logic_vector(LANES*8-1 downto 0) := (others => '1');
	signal d_gdo  : std_logic_vector(LANES*8-1 downto 0);
	signal d_greg : std_logic_vector(LANES*212-1 downto 0);
	signal d_ga   : std_logic_vector(LANES*16-1 downto 0);
	signal d_ga_en : std_logic;

	function hex(v : std_logic_vector) return string is
		constant n : integer := (v'length + 3) / 4;
		variable x : std_logic_vector(n*4-1 downto 0) := (others => '0');
		variable s : string(1 to n);
		variable d : integer;
	begin
		x(v'length-1 downto 0) := v;
		for i in 0 to n-1 loop
			if is_x(x(i*4+3 downto i*4)) then
				s(n-i) := 'X';
			else
				d := to_integer(unsigned(x(i*4+3 downto i*4)));
				if d < 10 then s(n-i) := character'val(48 + d); else s(n-i) := character'val(55 + d); end if;
			end if;
		end loop;
		return s;
	end function;
begin

	ref : entity work.T80se
		port map (
			RESET_n => reset_n, CLK_n => clk, CLKEN => '1', WAIT_n => '1', INT_n => int_n, NMI_n => '1', BUSRQ_n => '1',
			M1_n => r_m1_n, MREQ_n => r_mreq_n, IORQ_n => r_iorq_n, RD_n => r_rd_n, WR_n => r_wr_n,
			RFSH_n => r_rfsh_n, HALT_n => r_halt_n, BUSAK_n => open, A => r_a, DI => r_di, DO => r_do,
			DIRset => dirset, DIR => dir, REG => r_reg, MC_O => open, TS_O => open, IR_O => open, PC_O => open);

	dut : entity work.T80se_S256
		generic map (LANES => LANES)
		port map (
			RESET_n => reset_n, CLK_n => clk, CLKEN => '1', WAIT_n => '1', INT_n => int_n, NMI_n => '1', BUSRQ_n => '1',
			M1_n => d_m1_n, MREQ_n => d_mreq_n, IORQ_n => d_iorq_n, RD_n => d_rd_n, WR_n => d_wr_n,
			RFSH_n => d_rfsh_n, HALT_n => d_halt_n, BUSAK_n => open, A => d_a, DI => d_di, DO => d_do,
			DIRset => dirset, DIR => dir, REG => d_reg, MC_O => d_mc, TS_O => d_ts, IR_O => open, PC_O => open,
			INST => d_inst, GDI => d_gdi, GDO => d_gdo, GREG => d_greg, GA => d_ga, GA_EN => d_ga_en);

	-- clock and interrupts; the clock stops after G_CYCLES
	process
	begin
		while cycle < G_CYCLES loop
			clk <= '1'; wait for 5 ns;
			clk <= '0'; wait for 5 ns;
			cycle <= cycle + 1;
			if (cycle mod FRAME) < 32 and cycle > 100 then int_n <= '0'; else int_n <= '1'; end if;
		end loop;
		done <= true;
		wait;
	end process;

	-- memories: loaded at the start, read on the falling edge, written while WR_n is low
	process
		type mem_t is array (0 to 65535) of std_logic_vector(7 downto 0);
		type planes_t is array (0 to LANES-1) of mem_t;
		type charfile is file of character;
		file f : charfile;
		variable c : character;
		variable ref_mem, dut_mem : mem_t;
		variable planes : planes_t;
		variable regs : std_logic_vector(223 downto 0) := (others => '0');
		variable n, a, la : integer;
		variable natural : boolean;
		variable uni_ok : boolean := false;
		variable io : std_logic_vector(7 downto 0);

		function io_read(addr : std_logic_vector(15 downto 0)) return std_logic_vector is
		begin
			if addr(7 downto 0) = x"1F" then
				return x"00";  -- Kempston: nothing pressed
			end if;
			return x"FF";      -- keyboard (port xxFE): nothing pressed; others: floating bus
		end function;
	begin
		file_open(f, G_ROM, read_mode);
		for i in 0 to 16383 loop
			read(f, c);
			ref_mem(i) := std_logic_vector(to_unsigned(character'pos(c), 8));
		end loop;
		file_close(f);
		file_open(f, G_FILE256, read_mode);
		for i in 0 to 49151 loop
			read(f, c);
			ref_mem(16384 + i) := std_logic_vector(to_unsigned(character'pos(c), 8));
		end loop;
		for i in 0 to 49151 loop
			for p in 0 to LANES-1 loop
				read(f, c);
				planes(p)(16384 + i) := std_logic_vector(to_unsigned(character'pos(c), 8));
			end loop;
		end loop;
		for i in 0 to 27 loop
			read(f, c);
			regs := std_logic_vector(to_unsigned(character'pos(c), 8)) & regs(223 downto 8);
		end loop;
		file_close(f);
		dut_mem := ref_mem;
		for p in 0 to LANES-1 loop
			for i in 0 to 16383 loop
				planes(p)(i) := ref_mem(i);
			end loop;
			if G_NATURAL then
				planes(p) := ref_mem;
			end if;
		end loop;

		-- reset, then the registers of the snapshot, as the file loader of spec256.vhd does
		dir <= regs(211 downto 0);
		wait until falling_edge(clk); wait until falling_edge(clk);
		reset_n <= '1';
		dirset <= '1';
		wait until falling_edge(clk);
		dirset <= '0';

		while not done loop
			wait until falling_edge(clk) or done;
			exit when done;
			-- reference
			if r_mreq_n = '0' and r_wr_n = '0' then
				a := to_integer(unsigned(r_a));
				if a >= 16384 then ref_mem(a) := r_do; end if;
			end if;
			if r_iorq_n = '0' then
				r_di <= io_read(r_a);
			else
				r_di <= ref_mem(to_integer(unsigned(r_a)));
			end if;
			-- T80se_S256
			a := to_integer(unsigned(d_a));
			if d_mreq_n = '0' and d_wr_n = '0' and a >= 16384 then
				dut_mem(a) := d_do;
				for p in 0 to LANES-1 loop
					planes(p)(a) := d_gdo(p*8+7 downto p*8);
				end loop;
			end if;
			if d_iorq_n = '0' then
				io := io_read(d_a);
				d_di <= io;
				for p in 0 to LANES-1 loop
					d_gdi(p*8+7 downto p*8) <= io;
				end loop;
			else
				d_di <= dut_mem(a);
				for p in 0 to LANES-1 loop
					la := a;
					-- as sram.v: the lane address in the same page, the word at a not coloured, the
					-- lane addresses not all the same
					natural := true;
					for q in 0 to LANES-1 loop
						if planes(q)(a) /= dut_mem(a) then natural := false; end if;
						if d_ga(q*16+15 downto q*16) /= d_ga(15 downto 0) then uni_ok := true; end if;
					end loop;
					if not uni_ok then natural := false; end if;
					uni_ok := false;
					if d_ga_en = '1' and natural and d_ga(p*16+15 downto p*16+8) = d_a(15 downto 8) and
					   to_integer(unsigned(d_a(15 downto 8))) = G_TABLE_PAGE then
						la := to_integer(unsigned(d_ga(p*16+15 downto p*16)));
						if G_LOG_GA and la /= a and d_mreq_n = '0' and d_rd_n = '0' and p = 0 then
							report "GA pc " & integer'image(to_integer(unsigned(d_reg(79 downto 64)))) &
								" a " & integer'image(a) & " lanes " &
								integer'image(to_integer(unsigned(d_ga(15 downto 0)))) & " " &
								integer'image(to_integer(unsigned(d_ga(31 downto 16)))) & " " &
								integer'image(to_integer(unsigned(d_ga(47 downto 32)))) & " " &
								integer'image(to_integer(unsigned(d_ga(63 downto 48)))) & " " &
								integer'image(to_integer(unsigned(d_ga(79 downto 64)))) & " " &
								integer'image(to_integer(unsigned(d_ga(95 downto 80)))) & " " &
								integer'image(to_integer(unsigned(d_ga(111 downto 96)))) & " " &
								integer'image(to_integer(unsigned(d_ga(127 downto 112))));
						end if;
					end if;
					if d_inst = '1' and G_IMM_MASTER then
						d_gdi(p*8+7 downto p*8) <= dut_mem(a);
					else
						d_gdi(p*8+7 downto p*8) <= planes(p)(la);
					end if;
				end loop;
			end if;
		end loop;
		wait;
	end process;

	-- checks
	process
		variable errors : integer := 0;
		variable l : line;
		file tf : text;
		variable prev_mc, prev_ts : std_logic_vector(2 downto 0) := "000";
		variable prev_dd : boolean := false;

		procedure err(msg : string) is
			variable ln : line;
		begin
			errors := errors + 1;
			if errors <= G_MAX_REPORT then
				write(ln, string'("cycle ") & integer'image(cycle) & ": " & msg);
				writeline(output, ln);
			end if;
		end procedure;
	begin
		if G_TRACE /= "" then
			file_open(tf, G_TRACE, write_mode);
		end if;
		wait until dirset = '1';
		wait until falling_edge(clk);
		while not done loop
			wait until falling_edge(clk) or done;
			exit when done;
			if d_a /= r_a then err("A " & hex(d_a) & " /= " & hex(r_a)); end if;
			if d_m1_n /= r_m1_n or d_mreq_n /= r_mreq_n or d_iorq_n /= r_iorq_n or d_rd_n /= r_rd_n or
			   d_wr_n /= r_wr_n or d_rfsh_n /= r_rfsh_n or d_halt_n /= r_halt_n then
				err("bus control differs");
			end if;
			if r_wr_n = '0' and d_do /= r_do then err("DO " & hex(d_do) & " /= " & hex(r_do)); end if;
			if d_reg /= r_reg then err("REG " & hex(d_reg) & " /= " & hex(r_reg)); end if;
			if G_NATURAL then
				for p in 0 to LANES-1 loop
					if d_greg(p*212+211 downto p*212) /= d_reg then
						err("lane " & integer'image(p) & " GREG " & hex(d_greg(p*212+211 downto p*212)) & " /= REG " & hex(d_reg));
					end if;
					if d_wr_n = '0' and d_gdo(p*8+7 downto p*8) /= d_do then
						err("lane " & integer'image(p) & " GDO " & hex(d_gdo(p*8+7 downto p*8)) & " /= DO " & hex(d_do));
					end if;
				end loop;
			end if;
			-- G_LOG_GA: where the D of lane 0 goes apart from the main D (REG bits 111..104 = D)
			if G_LOG_GA and d_mc = "001" and d_ts = "010" and d_m1_n = '0' and
			   d_greg(111 downto 104) /= d_reg(111 downto 104) and not prev_dd then
				report "DDIFF pc " & integer'image(to_integer(unsigned(d_a))) & " D " &
					integer'image(to_integer(unsigned(d_reg(111 downto 104)))) & " lane0 D " &
					integer'image(to_integer(unsigned(d_greg(111 downto 104))));
			end if;
			if d_mc = "001" and d_ts = "010" and d_m1_n = '0' then
				prev_dd := d_greg(111 downto 104) /= d_reg(111 downto 104);
			end if;
			-- trace: entering T2 of an M1; INT marks the M1 of an interrupt acknowledge
			if G_TRACE /= "" and d_mc = "001" and d_ts = "010" and not (prev_mc = "001" and prev_ts = "010") then
				write(l, integer'image(cycle));
				if d_iorq_n = '0' then write(l, string'(" INT")); else write(l, string'(" M1")); end if;
				write(l, string'(" ") & hex(d_a) & " " & hex(d_reg));
				for p in 0 to LANES-1 loop
					write(l, string'(" ") & hex(d_greg(p*212+211 downto p*212)));
				end loop;
				writeline(tf, l);
			end if;
			prev_mc := d_mc;
			prev_ts := d_ts;
		end loop;
		if G_TRACE /= "" then
			file_close(tf);
		end if;
		if G_TABLE then
			for p in 0 to LANES-1 loop
				if d_greg(p*212+7 downto p*212) /= std_logic_vector(to_unsigned(2**(7-p), 8)) then
					err("table: lane " & integer'image(p) & " A " & hex(d_greg(p*212+7 downto p*212)) &
						" /= " & integer'image(2**(7-p)));
				end if;
			end loop;
		end if;
		write(l, string'("tb_s256: ") & integer'image(errors) & " errors");
		writeline(output, l);
		wait;
	end process;
end sim;
