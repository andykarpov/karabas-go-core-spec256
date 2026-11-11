-------------------------------------------------------------------------------
-- tb_bg_rules: bg_rules.vhd, the background a game shows.
--   1. The rules of a .CFG as the loader writes them from the header (rule n: background, address,
--      value): the first rule that holds, else the background stays; the bits of the snapshot.
--   2. A block of the rules (Spec256 DOS): a rule of two conditions, a mask, <, a rule that keeps
--      the background, none, the default when no rule holds, none at the start.
--   cd src/sim/work && ghdl -a --std=93c ../../rtl/video/bg_rules.vhd ../tb_bg_rules.vhd
--   ghdl -e --std=93c tb_bg_rules && ghdl -r --std=93c tb_bg_rules
-- Prints "<check> ok" or "<check> FAILED" for each check.
-------------------------------------------------------------------------------
library ieee; use ieee.std_logic_1164.all; use ieee.numeric_std.all;
entity tb_bg_rules is end;
architecture sim of tb_bg_rules is
	signal clk : std_logic := '0';
	signal init, load, we, wr : std_logic := '0';
	signal a, d, wr_d, bg, flags : std_logic_vector(7 downto 0) := x"00";
	signal wr_a : std_logic_vector(15 downto 0) := x"0000";
	signal none : std_logic;
	signal done : boolean := false;
begin
	clk <= not clk after 5 ns when not done;
	dut : entity work.bg_rules port map (I_CLK => clk, I_INIT => init, I_LOAD => load, I_CFG_WE => we,
		I_CFG_A => a, I_CFG_D => d, I_WR => wr, I_WR_A => wr_a, I_WR_D => wr_d, O_FLAGS => flags,
		O_BG => bg, O_NONE => none);
	process
		procedure cfg(addr : integer; v : integer) is
		begin
			a <= std_logic_vector(to_unsigned(addr, 8)); d <= std_logic_vector(to_unsigned(v, 8)); we <= '1';
			wait until rising_edge(clk); we <= '0';
		end procedure;
		-- a condition: address, mask, value
		procedure cond(n : integer; addr : integer; m, v : integer) is
		begin
			cfg(4 + 4 * n, addr mod 256); cfg(5 + 4 * n, addr / 256); cfg(6 + 4 * n, m); cfg(7 + 4 * n, v);
		end procedure;
		procedure rule(n : integer; b : integer; need : integer) is
		begin
			cfg(72 + 4 * n, b); cfg(73 + 4 * n, need mod 256); cfg(74 + 4 * n, need / 256);
		end procedure;
		-- a write of the CPU (several clocks, as a memory cycle)
		procedure poke(addr : integer; v : integer) is
		begin
			wr_a <= std_logic_vector(to_unsigned(addr, 16)); wr_d <= std_logic_vector(to_unsigned(v, 8));
			wr <= '1'; for i in 1 to 4 loop wait until rising_edge(clk); end loop;
			wr <= '0'; for i in 1 to 4 loop wait until rising_edge(clk); end loop;
		end procedure;
		procedure expect(b : integer; n : std_logic; msg : string) is
		begin
			if none = n and (n = '1' or bg = std_logic_vector(to_unsigned(b, 8))) then
				report msg & " ok";
			else
				report msg & " FAILED: background " & integer'image(to_integer(unsigned(bg))) &
					", none " & std_logic'image(none) severity error;
			end if;
		end procedure;
		procedure start_load is
		begin
			load <= '1'; init <= '1'; wait until rising_edge(clk); init <= '0';
		end procedure;
		procedure end_load is
		begin
			wait until rising_edge(clk); load <= '0'; wait until rising_edge(clk); wait until rising_edge(clk);
		end procedure;
	begin
		wait until rising_edge(clk);

		-- 1. the rules of a .CFG: rule 0 background 2 at 5800 = 07, rule 1 background 1 at 6000 = 03
		start_load;
		cfg(72, 2); cfg(4, 16#00#); cfg(5, 16#58#); cfg(7, 16#07#);
		cfg(76, 1); cfg(8, 16#00#); cfg(9, 16#60#); cfg(11, 16#03#);
		cfg(153, 0); cfg(2, 0); cfg(3, 0);
		wait until rising_edge(clk); wait until rising_edge(clk);
		expect(0, '0', "cfg: the background while the file loads");
		end_load;
		expect(0, '0', "cfg: no rule holds, the background stays");
		poke(16#6000#, 3);
		expect(1, '0', "cfg: rule 1");
		poke(16#5800#, 7);
		expect(2, '0', "cfg: rule 0 before rule 1");
		poke(16#5800#, 6);
		expect(1, '0', "cfg: rule 0 no more, rule 1");
		poke(16#6000#, 4);
		expect(1, '0', "cfg: no rule, the background stays");
		poke(16#5801#, 7);
		expect(1, '0', "cfg: another address");
		-- the bits of the snapshot: rule 0 holds at the start
		start_load;
		cfg(72, 2); cfg(4, 16#00#); cfg(5, 16#58#); cfg(7, 16#07#);
		cfg(153, 0); cfg(2, 1); cfg(3, 0);
		end_load;
		expect(2, '0', "cfg: the snapshot, rule 0");
		poke(16#5800#, 0);
		expect(2, '0', "cfg: rule 0 no more, the background stays");

		-- 2. a block of the rules: default 1; rule 0 none if 4000 = 00 and 4001 & F0 = 30 (condition 9); rule 1 keep if
		-- 5AE0 & 07 = 07; rule 2 background 3 if 4000 = 00; rule 3 background 2 if CBF4 < 08
		start_load;
		cfg(0, 1); cfg(1, 1);
		cond(0, 16#4000#, 16#FF#, 16#00#);
		cond(9, 16#4001#, 16#F0#, 16#30#);
		cond(2, 16#5AE0#, 16#07#, 16#07#);
		cond(3, 16#CBF4#, 16#FF#, 16#08#);
		cfg(68, 16#08#); cfg(69, 0);
		rule(0, 16#FE#, 16#0201#);
		rule(1, 16#FD#, 16#0004#);
		rule(2, 3, 16#0001#);
		rule(3, 2, 16#0008#);
		cfg(153, 16#FE#); cfg(2, 16#00#); cfg(3, 0);
		wait until rising_edge(clk); wait until rising_edge(clk);
		expect(0, '1', "block: none while the file loads");
		end_load;
		if flags = x"01" then report "block: flags ok"; else report "block: flags FAILED" severity error; end if;
		expect(1, '0', "block: the default");
		poke(16#CBF4#, 8);
		expect(1, '0', "block: 08 is not < 08");
		poke(16#CBF4#, 7);
		expect(2, '0', "block: < 08");
		poke(16#4000#, 0);
		expect(3, '0', "block: rule 2 before rule 3");
		poke(16#4001#, 16#3C#);
		expect(0, '1', "block: two conditions and a mask: none");
		poke(16#4001#, 16#4C#);
		expect(3, '0', "block: one of the two conditions");
		poke(16#5AE0#, 16#0F#);
		expect(3, '0', "block: keep (masked 07)");
		poke(16#4000#, 1);
		expect(3, '0', "block: keep before rule 3");
		poke(16#5AE0#, 16#00#);
		expect(2, '0', "block: rule 3 again");
		poke(16#CBF4#, 16#FF#);
		expect(1, '0', "block: no rule, the default");

		report "done";
		done <= true;
		wait;
	end process;
end architecture;
