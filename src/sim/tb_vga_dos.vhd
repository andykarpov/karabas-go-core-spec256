-------------------------------------------------------------------------------
-- tb_vga_dos: the rendering of Spec256 DOS in vga_spec256 (I_DOS).
--
-- An instance with I_DOS (and the background, Paper00InkFF, HideSame, BkOverFF and the mixing on,
-- which DOS leaves out) on a screen whose attributes change from cell to cell, colour (x, y) =
-- (7x + 13y) mod 256, against an instance in Palette mode without mixing, HideSame or BkOverFF
-- whose colours C0-FF are already 11 ink colour(2:0) of their cell: the same picture, the
-- background at colour 0 in both. BkOverFF (EmuZWin): an instance in Palette mode with BkOverFF on
-- colours where every third pixel is 0xFF, against one without BkOverFF whose 0xFF are 0 where the
-- ink of the cell is not white: the background through 0xFF but not on a white ink. The first G_ROWS
-- rows of cells (the whole screen with 24; the inks 0-7 are in every row).
--   cd src/sim && ghdl -a --std=93c -fexplicit --ieee=synopsys --workdir=work ../rtl/video/sync.vhd \
--     ../rtl/video/vga_spec256.vhd tb_vga_dos.vhd
--   ghdl -e --std=93c -fexplicit --ieee=synopsys --workdir=work tb_vga_dos
--   ghdl -r --std=93c -fexplicit --ieee=synopsys --workdir=work tb_vga_dos --ieee-asserts=disable
-- Prints "tb_vga_dos: <n> errors" (about 40 seconds).
-------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;

entity tb_vga_dos is
	generic (G_ROWS : integer := 4);
end tb_vga_dos;

architecture sim of tb_vga_dos is
	type mem_t is array (0 to 8191) of std_logic_vector(7 downto 0);
	type planes_t is array (0 to 8191) of std_logic_vector(63 downto 0);

	-- the attribute of a cell: ink (col + row) mod 8, paper (3 col + row) mod 8 (some the same), BRIGHT
	-- on odd rows
	function attr(col, row : integer) return std_logic_vector is
	begin
		return '0' & std_logic_vector(to_unsigned(row mod 2, 1)) &
			std_logic_vector(to_unsigned((3 * col + row) mod 8, 3)) & std_logic_vector(to_unsigned((col + row) mod 8, 3));
	end function;

	function make_screen return mem_t is
		variable m : mem_t;
		variable x : unsigned(31 downto 0) := x"12345678";
	begin
		for i in 0 to 8191 loop
			x := x xor shift_left(x, 13);
			x := x xor shift_right(x, 17);
			x := x xor shift_left(x, 5);
			if i < 6144 then
				m(i) := std_logic_vector(x(7 downto 0));
			else
				m(i) := attr((i - 6144) mod 32, (i - 6144) / 32);
			end if;
		end loop;
		return m;
	end function;
	constant SCREEN : mem_t := make_screen;

	function colour(x, y : integer) return integer is
	begin
		return (7 * x + 13 * y) mod 256;
	end function;

	-- the planes of every screen address: byte p = plane p, bit 7 the left pixel; ref: C0-FF as
	-- 11 ink colour(2:0) of the cell
	-- kind 0: DOS, 1: its reference, 2: BkOverFF, 3: its reference
	function table(kind : integer) return planes_t is
		variable t : planes_t;
		variable a : std_logic_vector(12 downto 0);
		variable ya, at : std_logic_vector(7 downto 0);
		variable y, col, c : integer;
	begin
		for i in 0 to 6143 loop
			a := std_logic_vector(to_unsigned(i, 13));
			ya := a(12 downto 11) & a(7 downto 5) & a(10 downto 8);
			y := to_integer(unsigned(ya));
			col := to_integer(unsigned(a(4 downto 0)));
			at := attr(col, y / 8);
			for j in 0 to 7 loop
				c := colour(col * 8 + j, y);
				if kind = 1 and c >= 192 then
					c := 192 + to_integer(unsigned(at(2 downto 0))) * 8 + c mod 8;
				end if;
				if kind >= 2 and (col * 8 + j + y) mod 3 = 0 then
					c := 255;
				end if;
				if kind = 3 and c = 255 and at(2 downto 0) /= "111" then
					c := 0;
				end if;
				for p in 0 to 7 loop
					if (c / 2**p) mod 2 = 1 then t(i)(p*8 + 7 - j) := '1'; else t(i)(p*8 + 7 - j) := '0'; end if;
				end loop;
			end loop;
		end loop;
		for i in 6144 to 8191 loop
			t(i) := (others => '0');
		end loop;
		return t;
	end function;
	constant DOS_T : planes_t := table(0);
	constant REF_T : planes_t := table(1);
	constant BK_T : planes_t := table(2);
	constant BKREF_T : planes_t := table(3);
	constant PAL : string := "../rtl/video/sp256_palette.hex";

	signal clk : std_logic := '0';
	signal hcnt, vcnt : std_logic_vector(9 downto 0);
	signal blank : std_logic;
	signal addr0, gaddr0, addr1, gaddr1 : std_logic_vector(12 downto 0);
	signal data0, data1 : std_logic_vector(7 downto 0);
	signal gdata0, gdata1 : std_logic_vector(63 downto 0);
	signal r0, g0, b0, r1, g1, b1 : std_logic_vector(7 downto 0);
	signal addr2, gaddr2, addr3, gaddr3 : std_logic_vector(12 downto 0);
	signal data2, data3 : std_logic_vector(7 downto 0);
	signal gdata2, gdata3 : std_logic_vector(63 downto 0);
	signal r2, g2, b2, r3, g3, b3 : std_logic_vector(7 downto 0);
	signal bg_req, prev_req : std_logic := '0';
	signal bg_y : std_logic_vector(7 downto 0);
	signal lb_we : std_logic := '0';
	signal lb_a : std_logic_vector(7 downto 0);
	signal lb_d : std_logic_vector(15 downto 0);
	signal done : boolean := false;
begin
	sync : entity work.sync
		port map (I_CLK => clk, I_EN => '1', O_HCNT => hcnt, O_VCNT => vcnt, O_INT => open,
			O_FLASH => open, O_BLANK => blank, O_HSYNC => open, O_VSYNC => open);

	dos_i : entity work.vga_spec256
		generic map (PAL_FILE => PAL)
		port map (I_CLK => clk, I_MODE => '1', I_DATA => data0, I_GFX_DATA => gdata0, I_BORDER => "010",
			I_HCNT => hcnt, I_VCNT => vcnt, I_BLANK => blank,
			I_PAL_CLK => clk, I_PAL_WR => '0', I_PAL_A => x"00", I_PAL_D => x"000000",
			I_COLOUR_MODE => "00", I_PAPER00INKFF => '1', I_HIDE_SAME => '1', I_UP_MIXED => x"40", I_DOWN_MIXED => x"10",
			I_BG_ON => '1', I_BK_OVER_FF => '1', I_DOS => '1', I_LB_CLK => clk, I_LB_WE => lb_we, I_LB_A => lb_a, I_LB_D => lb_d,
			O_BG_REQ => bg_req, O_BG_Y => bg_y,
			O_ADDR => addr0, O_GFX_ADDR => gaddr0, O_R => r0, O_G => g0, O_B => b0);

	ref_i : entity work.vga_spec256
		generic map (PAL_FILE => PAL)
		port map (I_CLK => clk, I_MODE => '1', I_DATA => data1, I_GFX_DATA => gdata1, I_BORDER => "010",
			I_HCNT => hcnt, I_VCNT => vcnt, I_BLANK => blank,
			I_PAL_CLK => clk, I_PAL_WR => '0', I_PAL_A => x"00", I_PAL_D => x"000000",
			I_COLOUR_MODE => "10", I_PAPER00INKFF => '1', I_HIDE_SAME => '0', I_UP_MIXED => x"00", I_DOWN_MIXED => x"00",
			I_BG_ON => '1', I_BK_OVER_FF => '0', I_LB_CLK => clk, I_LB_WE => lb_we, I_LB_A => lb_a, I_LB_D => lb_d,
			O_BG_REQ => open, O_BG_Y => open,
			O_ADDR => addr1, O_GFX_ADDR => gaddr1, O_R => r1, O_G => g1, O_B => b1);

	bk_i : entity work.vga_spec256
		generic map (PAL_FILE => PAL)
		port map (I_CLK => clk, I_MODE => '1', I_DATA => data2, I_GFX_DATA => gdata2, I_BORDER => "010",
			I_HCNT => hcnt, I_VCNT => vcnt, I_BLANK => blank,
			I_PAL_CLK => clk, I_PAL_WR => '0', I_PAL_A => x"00", I_PAL_D => x"000000",
			I_COLOUR_MODE => "10", I_PAPER00INKFF => '1', I_HIDE_SAME => '0', I_UP_MIXED => x"00", I_DOWN_MIXED => x"00",
			I_BG_ON => '1', I_BK_OVER_FF => '1', I_LB_CLK => clk, I_LB_WE => lb_we, I_LB_A => lb_a, I_LB_D => lb_d,
			O_BG_REQ => open, O_BG_Y => open,
			O_ADDR => addr2, O_GFX_ADDR => gaddr2, O_R => r2, O_G => g2, O_B => b2);

	bkref_i : entity work.vga_spec256
		generic map (PAL_FILE => PAL)
		port map (I_CLK => clk, I_MODE => '1', I_DATA => data3, I_GFX_DATA => gdata3, I_BORDER => "010",
			I_HCNT => hcnt, I_VCNT => vcnt, I_BLANK => blank,
			I_PAL_CLK => clk, I_PAL_WR => '0', I_PAL_A => x"00", I_PAL_D => x"000000",
			I_COLOUR_MODE => "10", I_PAPER00INKFF => '1', I_HIDE_SAME => '0', I_UP_MIXED => x"00", I_DOWN_MIXED => x"00",
			I_BG_ON => '1', I_BK_OVER_FF => '0', I_LB_CLK => clk, I_LB_WE => lb_we, I_LB_A => lb_a, I_LB_D => lb_d,
			O_BG_REQ => open, O_BG_Y => open,
			O_ADDR => addr3, O_GFX_ADDR => gaddr3, O_R => r3, O_G => g3, O_B => b3);

	-- the line buffer of all: colour (x + 3y) mod 254 + 1 on the asked line, 128 words over 128 clocks
	process
		variable y : integer;
	begin
		wait until rising_edge(clk);
		if bg_req /= prev_req then
			prev_req <= bg_req;
			y := to_integer(unsigned(bg_y));
			for w in 0 to 127 loop
				lb_we <= '1';
				lb_a <= bg_y(0) & std_logic_vector(to_unsigned(w, 7));
				lb_d <= std_logic_vector(to_unsigned((2*w + 1 + 3 * y) mod 254 + 1, 8)) &
					std_logic_vector(to_unsigned((2*w + 3 * y) mod 254 + 1, 8));
				wait until rising_edge(clk);
			end loop;
			lb_we <= '0';
		end if;
	end process;

	-- the video memories: block RAM with a registered output
	process (clk)
	begin
		if rising_edge(clk) then
			data0 <= SCREEN(to_integer(unsigned(addr0)));
			data1 <= SCREEN(to_integer(unsigned(addr1)));
			gdata0 <= DOS_T(to_integer(unsigned(gaddr0)));
			gdata1 <= REF_T(to_integer(unsigned(gaddr1)));
			data2 <= SCREEN(to_integer(unsigned(addr2)));
			data3 <= SCREEN(to_integer(unsigned(addr3)));
			gdata2 <= BK_T(to_integer(unsigned(gaddr2)));
			gdata3 <= BKREF_T(to_integer(unsigned(gaddr3)));
		end if;
	end process;

	-- the screen starts at line 97, a row of cells is 16 lines
	process
	begin
		for i in 1 to (97 + 16 * G_ROWS + 2) * 864 loop
			clk <= '1'; wait for 18.5 ns;
			clk <= '0'; wait for 18.5 ns;
		end loop;
		done <= true;
		wait;
	end process;

	process
		variable errors, last_errors, n : integer := 0;
		variable c0, c1, c2, c3 : std_logic_vector(23 downto 0);
		variable l : line;
		function hex24(v : std_logic_vector(23 downto 0)) return string is
			constant d : string(1 to 16) := "0123456789ABCDEF";
			variable s : string(1 to 6);
		begin
			for i in 0 to 5 loop
				s(6-i) := d(to_integer(unsigned(v(i*4+3 downto i*4))) + 1);
			end loop;
			return s;
		end function;
	begin
		-- two lines for the pipelines (the first line of the background is asked for at the start)
		for i in 1 to 2 * 864 loop
			wait until falling_edge(clk);
		end loop;
		while not done loop
			wait until falling_edge(clk) or done;
			exit when done;
			c0 := r0 & g0 & b0;
			c1 := r1 & g1 & b1;
			if c0 /= x"000000" and c0 /= x"FF0000" then n := n + 1; end if;  -- not blank, not the border
			c2 := r2 & g2 & b2;
			c3 := r3 & g3 & b3;
			if c0 /= c1 or c2 /= c3 then errors := errors + 1; end if;
			if errors /= last_errors and errors <= 20 then
				write(l, string'("error: h ") & integer'image(to_integer(unsigned(hcnt))) & " v " &
					integer'image(to_integer(unsigned(vcnt))) & " dos " & hex24(c0) & " ref " & hex24(c1) &
					" bkoverff " & hex24(c2) & " ref " & hex24(c3));
				writeline(output, l);
			end if;
			last_errors := errors;
		end loop;
		if n < 512 * 16 * G_ROWS / 2 then
			errors := errors + 1;
			write(l, string'("the screen is not shown"));
			writeline(output, l);
		end if;
		write(l, string'("tb_vga_dos: ") & integer'image(errors) & " errors");
		writeline(output, l);
		wait;
	end process;
end sim;
