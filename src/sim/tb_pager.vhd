-------------------------------------------------------------------------------
-- tb_pager: pager.vhd, the port #7FFD and the banks of the 4 windows: #30 after SET (ROM 1,
-- banks 5, 2, 0, locked: OUT ignored), a 128K value (#10) and OUTs to #7FFD (C000 and the ROM
-- follow), the ports that are not #7FFD (A15 = 1, A1 = 1, M1), the lock of bit 5.
--   cd src/sim/work && ghdl -a --std=93c ../../rtl/memory/pager.vhd ../tb_pager.vhd
--   ghdl -e --std=93c tb_pager && ghdl -r --std=93c tb_pager
-- Prints "<check> ok" or "<check> FAILED" for each check.
-------------------------------------------------------------------------------
library ieee; use ieee.std_logic_1164.all;
entity tb_pager is end;
architecture sim of tb_pager is
	signal clk, set, iorq_n, wr_n, m1_n : std_logic := '1';
	signal set_val : std_logic_vector(5 downto 0) := "110000";
	signal a : std_logic_vector(15 downto 0) := x"0000";
	signal d : std_logic_vector(7 downto 0) := x"00";
	signal bank_a : std_logic_vector(15 downto 14) := "00";
	signal bank : std_logic_vector(3 downto 0);
	signal done : boolean := false;
begin
	clk <= not clk after 5 ns when not done;
	dut : entity work.pager port map (CLK => clk, SET => set, SET_VAL => set_val, IORQ_N => iorq_n, WR_N => wr_n,
		M1_N => m1_n, A => a, D => d, BANK_A => bank_a, BANK => bank, P7FFD => open);
	process
		-- the banks of 0000, 4000, 8000, C000
		procedure banks(b0, b1, b2, b3 : std_logic_vector(3 downto 0); msg : string) is
			variable ok : boolean := true;
		begin
			bank_a <= "00"; wait for 1 ns; ok := ok and bank = b0;
			bank_a <= "01"; wait for 1 ns; ok := ok and bank = b1;
			bank_a <= "10"; wait for 1 ns; ok := ok and bank = b2;
			bank_a <= "11"; wait for 1 ns; ok := ok and bank = b3;
			assert ok report msg & " FAILED" severity error;
			if ok then report msg & " ok"; end if;
		end procedure;
		-- an OUT (C),r: IORQ and WR for 3 clocks
		procedure io_wr(port_a : std_logic_vector(15 downto 0); v : std_logic_vector(7 downto 0); m1 : std_logic := '1') is
		begin
			wait until falling_edge(clk);
			a <= port_a; d <= v; m1_n <= m1; iorq_n <= '0'; wr_n <= '0';
			wait until falling_edge(clk); wait until falling_edge(clk); wait until falling_edge(clk);
			iorq_n <= '1'; wr_n <= '1'; m1_n <= '1';
		end procedure;
		procedure do_set(v : std_logic_vector(5 downto 0)) is
		begin
			wait until falling_edge(clk);
			set_val <= v; set <= '1';
			wait until falling_edge(clk);
			set <= '0';
		end procedure;
	begin
		set <= '0';
		do_set("110000");
		banks("1001", "0101", "0010", "0000", "#30: ROM 1, 5, 2, 0");
		io_wr(x"7FFD", x"07");
		banks("1001", "0101", "0010", "0000", "#30: locked");
		do_set("010000");
		banks("1001", "0101", "0010", "0000", "#10");
		io_wr(x"7FFD", x"03");
		banks("1000", "0101", "0010", "0011", "OUT #03: ROM 0, bank 3");
		io_wr(x"7FFD", x"16");
		banks("1001", "0101", "0010", "0110", "OUT #16: ROM 1, bank 6");
		io_wr(x"FFFD", x"01");
		banks("1001", "0101", "0010", "0110", "#FFFD (A15) not #7FFD");
		io_wr(x"7FFF", x"01");
		banks("1001", "0101", "0010", "0110", "#7FFF (A1) not #7FFD");
		io_wr(x"7FFD", x"01", '0');
		banks("1001", "0101", "0010", "0110", "M1 (INTA) not a write");
		io_wr(x"00FD", x"05");
		banks("1000", "0101", "0010", "0101", "#00FD is #7FFD: ROM 0, bank 5 at C000");
		io_wr(x"7FFD", x"27");
		banks("1000", "0101", "0010", "0111", "OUT #27: ROM 0, bank 7, lock");
		io_wr(x"7FFD", x"11");
		banks("1000", "0101", "0010", "0111", "locked: OUT #11 ignored");
		do_set("110000");
		banks("1001", "0101", "0010", "0000", "SET #30 after the lock");
		done <= true;
		wait;
	end process;
end sim;
