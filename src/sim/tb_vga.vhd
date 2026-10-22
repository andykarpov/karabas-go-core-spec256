-------------------------------------------------------------------------------
-- tb_vga: the 0xFF passthrough of vga_spec256.
--
-- Two vga_spec256 on the same random screen (INK 7, PAPER 1, no BRIGHT / FLASH),
-- one in the ordinary mode, one in GFX 256 mode with natural planes (the planes
-- are the bitmap: a set bit is colour 0xFF, a clear bit colour 0). In GFX mode an
-- ink pixel (0xFF) must show the ordinary pixel, on the same clock, and a paper
-- pixel (colour 0) palette entry 0, black; the border and blank are the same.
-- A delay of the gfx pixel that is off by a clock fails at the pixel edges.
-- Prints "tb_vga: <n> errors".
-------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;

entity tb_vga is
	generic (G_FRAMES : integer := 2);
end tb_vga;

architecture sim of tb_vga is
	type mem_t is array (0 to 8191) of std_logic_vector(7 downto 0);

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
				m(i) := "00001111";  -- PAPER 1, INK 7
			end if;
		end loop;
		return m;
	end function;

	constant SCREEN : mem_t := make_screen;

	signal clk : std_logic := '0';
	signal done : boolean := false;
	signal hcnt, vcnt : std_logic_vector(9 downto 0);
	signal blank : std_logic;
	signal addr0, gaddr0, addr1, gaddr1 : std_logic_vector(12 downto 0);
	signal data0, data1 : std_logic_vector(7 downto 0);
	signal gdata0, gdata1 : std_logic_vector(63 downto 0);
	signal r0, g0, b0, r1, g1, b1 : std_logic_vector(7 downto 0);

	function planes(b : std_logic_vector(7 downto 0)) return std_logic_vector is
	begin
		return b & b & b & b & b & b & b & b;
	end function;
begin
	sync : entity work.sync
		port map (I_CLK => clk, I_EN => '1', O_HCNT => hcnt, O_VCNT => vcnt, O_INT => open,
			O_FLASH => open, O_BLANK => blank, O_HSYNC => open, O_VSYNC => open);

	std : entity work.vga_spec256
		port map (I_CLK => clk, I_MODE => '0', I_DATA => data0, I_GFX_DATA => gdata0, I_BORDER => "010",
			I_HCNT => hcnt, I_VCNT => vcnt, I_BLANK => blank, O_ADDR => addr0, O_GFX_ADDR => gaddr0,
			O_R => r0, O_G => g0, O_B => b0);

	gfx : entity work.vga_spec256
		port map (I_CLK => clk, I_MODE => '1', I_DATA => data1, I_GFX_DATA => gdata1, I_BORDER => "010",
			I_HCNT => hcnt, I_VCNT => vcnt, I_BLANK => blank, O_ADDR => addr1, O_GFX_ADDR => gaddr1,
			O_R => r1, O_G => g1, O_B => b1);

	-- the video memories: block RAM with a registered output (dpram2)
	process (clk)
	begin
		if rising_edge(clk) then
			data0 <= SCREEN(to_integer(unsigned(addr0)));
			data1 <= SCREEN(to_integer(unsigned(addr1)));
			gdata0 <= planes(SCREEN(to_integer(unsigned(gaddr0))));
			gdata1 <= planes(SCREEN(to_integer(unsigned(gaddr1))));
		end if;
	end process;

	process
	begin
		for i in 1 to G_FRAMES * 800 * 525 loop
			clk <= '1'; wait for 20 ns;
			clk <= '0'; wait for 20 ns;
		end loop;
		done <= true;
		wait;
	end process;

	process
		variable errors, ink, paper, border, last_errors : integer := 0;
		function hex24(v : std_logic_vector(23 downto 0)) return string is
			constant d : string(1 to 16) := "0123456789ABCDEF";
			variable s : string(1 to 6);
		begin
			for i in 0 to 5 loop
				s(6-i) := d(to_integer(unsigned(v(i*4+3 downto i*4))) + 1);
			end loop;
			return s;
		end function;
		variable l : line;
		variable c0, c1 : std_logic_vector(23 downto 0);
		constant WHITE : std_logic_vector(23 downto 0) := x"AAAAAA";  -- INK 7 without BRIGHT
		constant BLUE  : std_logic_vector(23 downto 0) := x"0000AA";  -- PAPER 1
	begin
		wait until falling_edge(clk);
		-- the first frame fills the pipelines
		for i in 1 to 800 * 525 loop
			wait until falling_edge(clk);
		end loop;
		while not done loop
			wait until falling_edge(clk) or done;
			exit when done;
			c0 := r0 & g0 & b0;
			c1 := r1 & g1 & b1;
			if c0 = WHITE then
				ink := ink + 1;
				if c1 /= WHITE then errors := errors + 1; end if;
			elsif c0 = BLUE then
				paper := paper + 1;
				if c1 /= x"000000" then errors := errors + 1; end if;
			else
				border := border + 1;
				if c1 /= c0 then errors := errors + 1; end if;
			end if;
			if errors /= last_errors and errors <= 40 then
				write(l, string'("error: h ") & integer'image(to_integer(unsigned(hcnt))) & " v " &
					integer'image(to_integer(unsigned(vcnt))) & " std " & hex24(c0) & " gfx " & hex24(c1));
				writeline(output, l);
			end if;
			last_errors := errors;
		end loop;
		write(l, string'("ink ") & integer'image(ink) & ", paper " & integer'image(paper) &
			", border/blank " & integer'image(border));
		writeline(output, l);
		if ink = 0 or paper = 0 then
			errors := errors + 1;
			write(l, string'("no ink or no paper pixels: the screen is not shown"));
			writeline(output, l);
		end if;
		write(l, string'("tb_vga: ") & integer'image(errors) & " errors");
		writeline(output, l);
		wait;
	end process;
end sim;
