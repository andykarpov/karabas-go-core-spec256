-------------------------------------------------------------------------------
-- tb_hid: hid_parser, the keys of a USB report to the ZX matrix (one key per
-- clock, the matrix latched after the six): Shift + keys in slots 3 and 5,
-- ';' (SS+O: the CS of SS is cleaned), Shift + ';' in slot 4, all released.
--   cd src/sim/work && ghdl -a --std=93c -fexplicit --ieee=synopsys ../../rtl/mcu/hid_parser.vhd ../tb_hid.vhd
--   ghdl -e --std=93c -fexplicit --ieee=synopsys tb_hid && ghdl -r --std=93c -fexplicit --ieee=synopsys tb_hid
-- Prints "<check> ok" or "<check> FAILED" for each check.
-------------------------------------------------------------------------------
library ieee; use ieee.std_logic_1164.all;
entity tb_hid is end;
architecture sim of tb_hid is
	signal clk, rst : std_logic := '0';
	signal st, k0, k1, k2, k3, k4, k5 : std_logic_vector(7 downto 0) := x"00";
	signal a : std_logic_vector(15 downto 8) := x"FF";
	signal kdo : std_logic_vector(4 downto 0);
	signal done : boolean := false;
	-- row (A15..A8 with one bit low) -> KB_DO
	procedure check(signal a : out std_logic_vector(15 downto 8); signal kdo : in std_logic_vector(4 downto 0);
		row : std_logic_vector(15 downto 8); expect : std_logic_vector(4 downto 0); msg : string) is
	begin
		a <= row; wait for 1 ns;
		assert kdo = expect report msg & " FAILED" severity error;
		if kdo = expect then report msg & " ok"; end if;
	end procedure;
begin
	clk <= not clk after 5 ns when not done;
	dut : entity work.hid_parser port map (CLK => clk, RESET => rst, KB_STATUS => st, KB_DAT0 => k0, KB_DAT1 => k1,
		KB_DAT2 => k2, KB_DAT3 => k3, KB_DAT4 => k4, KB_DAT5 => k5, JOY_TYPE_L => "000", JOY_TYPE_R => "000",
		JOY_L => (others => '0'), JOY_R => (others => '0'), A => a, JOY_DO => open, KB_DO => kdo);
	process begin
		rst <= '1'; wait for 20 ns; rst <= '0';
		-- L Shift + 'A' (0x04) in slot 3 + '1' (0x1E) in slot 5
		st <= x"02"; k3 <= x"04"; k5 <= x"1E"; wait for 200 ns;
		check(a, kdo, x"FE", "11110", "CS row: CS");          -- row A8: CS, Z, X, C, V
		check(a, kdo, x"FD", "11110", "A row: A");
		check(a, kdo, x"F7", "11110", "1 row: 1");
		-- ';' (0x33) in slot 0 without shift: SS+O, CS cleaned
		st <= x"00"; k3 <= x"00"; k5 <= x"00"; k0 <= x"33"; wait for 200 ns;
		check(a, kdo, x"FE", "11111", "no CS");
		check(a, kdo, x"7F", "11101", "SS");
		check(a, kdo, x"DF", "11101", "O");
		-- ';' with shift in slot 4 -> SS+Z, CS cleaned (is_ss_used := is_shift)
		st <= x"20"; k0 <= x"00"; k4 <= x"33"; wait for 200 ns;
		check(a, kdo, x"FE", "11101", "shift ; : Z, no CS");
		check(a, kdo, x"7F", "11101", "shift ; : SS");
		-- released
		st <= x"00"; k4 <= x"00"; wait for 200 ns;
		check(a, kdo, x"00", "11111", "released");
		done <= true; wait;
	end process;
end;
