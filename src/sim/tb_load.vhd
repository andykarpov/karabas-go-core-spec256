-------------------------------------------------------------------------------
-- tb_load: the 48K ROM and a .256 file through kg_mcu into the SRAM, in bursts.
--
-- spec256 (kg_pll, kg_mcu, the loaders, sram.v, T80se_S256) with a model of the
-- 16-bit SRAM. The testbench plays the RP2040 (karabas-go-firmware
-- docs/protocol.md, docs/burst_protocol.md): classic frames at 16 MHz for the
-- commands, the data in bursts of 512 bytes at BURST_SCK_HALF_PS (32 MHz:
-- a byte every 250 ns, 14 clocks of 56.25 MHz), as the firmware loads a core:
--   INIT_START, ROMLOADER 1, the ROM (burst type 07), ROMLOADER 0, INIT_DONE,
--   then the FL item: IOCTL_SLOT, IOCTL_SIZE, IOCTL_STATE 1, the file (burst
--   type 53), IOCTL_STATE 0.
-- Checked:
-- - with the file loaded (the CPU still in reset): every byte of the ROM, of
--   the SNA RAM and of the 8 planes in the SRAM, in the layout of sram.v
--   (word {a, 000}: bits 7..0 the main byte; words 001..100: planes 0-1 ...
--   6-7);
-- - after IOCTL_STATE 0: the CPU starts with the registers of the file at the
--   RETN at 0x0072: its first reads in the RAM are the stack (SP, SP+1) and
--   then the opcode at the PC of the snapshot.
-- Prints "tb_load: <n> errors". Run with run_load_sim.sh (ISim).
-------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;
use ieee.std_logic_textio.all;

entity tb_load is
	generic (
		G_HEX             : string  := "";       -- ROM (16384 bytes) then the .256, a byte per line, hex
		G_SP              : integer := 0;        -- SP and PC of the snapshot (PC on its stack)
		G_PC              : integer := 0;
		BURST_SCK_HALF_PS : integer := 15625     -- 32 MHz
	);
end tb_load;

architecture sim of tb_load is
	constant ROM_SIZE  : integer := 16384;
	constant FILE_SIZE : integer := 442396;
	constant SCK_HALF  : time := 31.25 ns;
	constant BURST_HALF : time := BURST_SCK_HALF_PS * 1 ps;

	type bytes_t is array (0 to ROM_SIZE + FILE_SIZE - 1) of std_logic_vector(7 downto 0);
	type sram_t is array (0 to 2**19 - 1) of std_logic_vector(15 downto 0);

	signal clk50   : std_logic := '0';
	signal done    : boolean := false;
	signal sck, mosi, ss_n, bcs_n : std_logic := '0';
	signal miso, ready : std_logic;
	signal mcu_io  : std_logic_vector(3 downto 0);
	signal ma      : std_logic_vector(20 downto 0);
	signal md      : std_logic_vector(15 downto 0);
	signal mrd_n, mwr_n : std_logic_vector(1 downto 0);
	signal dram_dq : std_logic_vector(15 downto 0);

	signal checking_start : boolean := false;
	signal ram_reads : integer := 0;
	type addr_log_t is array (0 to 2) of integer;
	signal first_reads : addr_log_t := (others => -1);
	signal sram_errors : integer := 0;
begin
	clk50 <= not clk50 after 10 ns when not done;
	mcu_io <= '1' & '1' & '1' & bcs_n;   -- [0] burst cs_n, sd2 / ft chip selects off

	dut : entity work.spec256
		generic map (BURST_MAX_MHZ => 32)
		port map (
			CLK_50MHZ => clk50, CLK_BUS => open, CLK_VGA => open, CLK_SDR_OUT => open,
			ARESET => open, RESET => open,
			MCU_CS_N => ss_n, MCU_SCK => sck, MCU_MOSI => mosi, MCU_MISO => miso, MCU_IO => mcu_io,
			MCU_BURST_READY => ready,
			VGA_RGB => open, VGA_HS => open, VGA_VS => open, VGA_BLANK => open, DVI_ONLY => open,
			BEEPER => open, AUDIO_L => open, AUDIO_R => open,
			DRAM_NRAS => open, DRAM_NCAS => open, DRAM_NWE => open, DRAM_DQM => open, DRAM_BA => open,
			DRAM_A => open, DRAM_DQ => dram_dq,
			MA => ma, MD => md, MRD_N => mrd_n, MWR_N => mwr_n);

	-- the SRAM: 16 bits, byte writes on MWR_N, reads while MRD_N is low (10 ns)
	sram : process
		variable mem : sram_t := (others => (others => '0'));
		variable a : integer;
		variable l : line;
		variable bytes : bytes_t;
		variable v : std_logic_vector(7 downto 0);
		variable errors : integer := 0;
		variable rom, sna : integer;
		file f : text;

		procedure check(addr, word, lane : integer; expect : std_logic_vector(7 downto 0); what : string) is
			variable got : std_logic_vector(7 downto 0);
			variable ln : line;
		begin
			got := mem(addr * 8 + word)(lane * 8 + 7 downto lane * 8);
			if got /= expect then
				errors := errors + 1;
				if errors <= 20 then
					write(ln, what & " at " & integer'image(addr) & ": " & integer'image(to_integer(unsigned(got))) &
						" /= " & integer'image(to_integer(unsigned(expect))));
					writeline(output, ln);
				end if;
			end if;
		end procedure;
	begin
		md <= (others => 'Z');
		loop
			wait on ma, md, mrd_n, mwr_n, checking_start;
			a := to_integer(unsigned(ma(18 downto 0)));
			if mwr_n(0) = '0' then mem(a)(7 downto 0) := md(7 downto 0); end if;
			if mwr_n(1) = '0' then mem(a)(15 downto 8) := md(15 downto 8); end if;
			if mrd_n /= "11" and mwr_n = "11" then
				md <= mem(a) after 10 ns;
			else
				md <= (others => 'Z');
			end if;
			-- every byte of the ROM and the file, as sram.v lays them out
			if checking_start then
				file_open(f, G_HEX, read_mode);
				for i in bytes'range loop
					readline(f, l);
					hread(l, v);
					bytes(i) := v;
				end loop;
				file_close(f);
				for i in 0 to ROM_SIZE - 1 loop
					check(i, 0, 0, bytes(i), "ROM");
				end loop;
				for i in 0 to 49151 loop
					check(16384 + i, 0, 0, bytes(ROM_SIZE + i), "SNA");
					for p in 0 to 7 loop
						check(16384 + i, 1 + p / 2, p mod 2, bytes(ROM_SIZE + 49152 + i * 8 + p), "plane " & integer'image(p));
					end loop;
				end loop;
				sram_errors <= errors;
				exit;
			end if;
		end loop;
		-- after the check: the model goes on, without the check
		loop
			wait on ma, md, mrd_n, mwr_n;
			a := to_integer(unsigned(ma(18 downto 0)));
			if mwr_n(0) = '0' then mem(a)(7 downto 0) := md(7 downto 0); end if;
			if mwr_n(1) = '0' then mem(a)(15 downto 8) := md(15 downto 8); end if;
			if mrd_n /= "11" and mwr_n = "11" then
				md <= mem(a) after 10 ns;
			else
				md <= (others => 'Z');
			end if;
		end loop;
	end process;

	-- the first reads of the RAM by the CPU after the file is loaded (word 000 of each address)
	process (mrd_n)
		variable a : integer;
	begin
		if falling_edge(mrd_n(0)) and checking_start and ma(2 downto 0) = "000" then
			a := to_integer(unsigned(ma(18 downto 3)));
			if a >= 16384 and ram_reads < 3 then
				first_reads(ram_reads) <= a;
				ram_reads <= ram_reads + 1;
			end if;
		end if;
	end process;

	stimulus : process
		variable bytes : bytes_t;
		variable l : line;
		variable v : std_logic_vector(7 downto 0);
		variable dummy : std_logic_vector(7 downto 0);
		variable errors : integer := 0;
		file f : text;

		procedure spi_byte(tx : std_logic_vector(7 downto 0); half : time) is
		begin
			for i in 7 downto 0 loop
				mosi <= tx(i);
				wait for half;
				sck <= '1';
				wait for half;
				sck <= '0';
			end loop;
		end procedure;

		procedure frame(c, a, d : std_logic_vector(7 downto 0)) is
		begin
			ss_n <= '0';
			wait for 100 ns;
			spi_byte(c, SCK_HALF);
			spi_byte(a, SCK_HALF);
			spi_byte(d, SCK_HALF);
			wait for 50 ns;
			ss_n <= '1';
			wait for 500 ns;
		end procedure;

		-- bursts of 512 bytes of bytes(first .. first + n - 1) to the addresses 0 .. n - 1
		procedure bursts(btype : std_logic_vector(7 downto 0); first, n : integer) is
			variable a : unsigned(31 downto 0);
			variable len : integer;
			variable k : integer := 0;
		begin
			while k < n loop
				if ready /= '1' then wait until ready = '1'; end if;
				a := to_unsigned(k, 32);
				len := 512;
				if n - k < len then len := n - k; end if;
				bcs_n <= '0';
				wait for 100 ns;
				spi_byte(btype, BURST_HALF);
				spi_byte(std_logic_vector(a(31 downto 24)), BURST_HALF);
				spi_byte(std_logic_vector(a(23 downto 16)), BURST_HALF);
				spi_byte(std_logic_vector(a(15 downto 8)), BURST_HALF);
				spi_byte(std_logic_vector(a(7 downto 0)), BURST_HALF);
				for i in 0 to len - 1 loop
					spi_byte(bytes(first + k + i), BURST_HALF);
				end loop;
				bcs_n <= '1';
				wait for 1 us;
				k := k + len;
			end loop;
		end procedure;

		variable size : unsigned(31 downto 0) := to_unsigned(FILE_SIZE, 32);
	begin
		ss_n <= '1';
		bcs_n <= '1';
		file_open(f, G_HEX, read_mode);
		for i in bytes'range loop
			readline(f, l);
			hread(l, v);
			bytes(i) := v;
		end loop;
		file_close(f);
		wait for 20 us;   -- the PLL locks

		frame(x"FD", x"00", x"00");                       -- INIT_START
		frame(x"08", x"00", x"01");                       -- ROMLOADER on
		bursts(x"07", 0, ROM_SIZE);
		frame(x"08", x"00", x"00");                       -- ROMLOADER off
		frame(x"FE", x"00", x"00");                       -- INIT_DONE: the ROM runs
		wait for 100 us;

		frame(x"50", x"00", x"00");                       -- IOCTL_SLOT: a new file
		for i in 0 to 3 loop                              -- IOCTL_SIZE
			frame(x"51", std_logic_vector(to_unsigned(i, 8)), std_logic_vector(size(i*8+7 downto i*8)));
		end loop;
		frame(x"55", x"00", x"01");                       -- IOCTL_STATE 1
		bursts(x"53", ROM_SIZE, FILE_SIZE);
		wait for 10 us;
		checking_start <= true;                           -- the SRAM is checked while the CPU is in reset
		wait for 1 us;
		frame(x"55", x"00", x"00");                       -- IOCTL_STATE 0: the CPU starts
		wait for 200 us;

		errors := sram_errors;
		write(l, string'("first RAM reads:"));
		for i in 0 to 2 loop
			write(l, string'(" ") & integer'image(first_reads(i)));
		end loop;
		writeline(output, l);
		if first_reads(0) /= G_SP or first_reads(1) /= G_SP + 1 or first_reads(2) /= G_PC then
			errors := errors + 1;
			write(l, string'("expected ") & integer'image(G_SP) & " " & integer'image(G_SP + 1) & " " & integer'image(G_PC));
			writeline(output, l);
		end if;
		write(l, string'("tb_load: ") & integer'image(errors) & " errors");
		writeline(output, l);
		done <= true;
		wait;
	end process;
end sim;
