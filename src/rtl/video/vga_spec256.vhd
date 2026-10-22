-------------------------------------------------------------------[09.07.2016]
-- VGA
-------------------------------------------------------------------------------
-- Engineer: MVV <mvvproject@gmail.com>

library IEEE; 
use IEEE.std_logic_1164.all; 
use IEEE.numeric_std.ALL;
use IEEE.std_logic_unsigned.all;
use std.textio.all;

entity vga_spec256 is
generic (
	PAL_FILE	: string := "rtl/video/sp256_palette.hex"
);
port (
	I_CLK		: in std_logic;
    I_MODE      : in std_logic := '0';
    I_DATA      : in std_logic_vector(7 downto 0);
	I_GFX_DATA	: in std_logic_vector(63 downto 0);
	I_BORDER	: in std_logic_vector(2 downto 0);	-- Биты D0..D2 порта xxFE определяют цвет бордюра
	I_HCNT		: in std_logic_vector(9 downto 0);
	I_VCNT		: in std_logic_vector(9 downto 0);
	I_BLANK		: in std_logic;
	-- the palette (written on I_PAL_CLK) and the colour rules of the game (static while it runs), see
	-- docs/SIMD.md section 7
	I_PAL_CLK	: in std_logic;
	I_PAL_WR	: in std_logic;
	I_PAL_A		: in std_logic_vector(7 downto 0);
	I_PAL_D		: in std_logic_vector(23 downto 0);
	I_COLOUR_MODE	: in std_logic_vector(1 downto 0);	-- colour 0 / 0xFF: 00 Auto (I_PAPER00INKFF), 01 attribute, 10 palette, 11 pixel
	I_PAPER00INKFF	: in std_logic;
	I_HIDE_SAME	: in std_logic;	-- HideSameInkPaper
	I_UP_MIXED	: in std_logic_vector(7 downto 0);	-- UpColorsMixed
	I_DOWN_MIXED	: in std_logic_vector(7 downto 0);	-- DownColorsMixed
    O_ADDR      : out std_logic_vector(12 downto 0);
	O_GFX_ADDR	: out std_logic_vector(12 downto 0);
	O_R		: out std_logic_vector(7 downto 0);	-- Red
	O_G		: out std_logic_vector(7 downto 0);	-- Green
	O_B		: out std_logic_vector(7 downto 0));	-- Blue
end entity;

architecture rtl of vga_spec256 is

	type pal_t is array (0 to 255) of std_logic_vector(23 downto 0);
	-- the standard palette, one hex RGB per line (the path from the directory of the build, src/)
	-- (the hex digits by hand: hread of std_logic_textio stops ghdl 4.1 at elaboration)
	impure function pal_init(name : string) return pal_t is
		file f : text open read_mode is name;
		variable l : line;
		variable c : character;
		variable d : integer;
		variable v : unsigned(23 downto 0);
		variable p : pal_t;
	begin
		for i in pal_t'range loop
			readline(f, l);
			v := (others => '0');
			for k in 1 to 6 loop
				read(l, c);
				case c is
					when '0' to '9' => d := character'pos(c) - character'pos('0');
					when 'a' to 'f' => d := character'pos(c) - character'pos('a') + 10;
					when 'A' to 'F' => d := character'pos(c) - character'pos('A') + 10;
					when others => d := 0;
				end case;
				v := v(19 downto 0) & to_unsigned(d, 4);
			end loop;
			p(i) := std_logic_vector(v);
		end loop;
		return p;
	end function;
	signal pal : pal_t := pal_init(PAL_FILE);

-- ZX-Spectum screen
	constant spec_border_left	: natural :=  32;	-- (640 - (spec_screen_h *2)) / 2 
	constant spec_screen_h		: natural := 256;	-- Spectrum Screen h = 256 pixels

	constant spec_border_top	: natural :=  24;	-- (640 - (spec_screen_v * 2)) / 2
	constant spec_screen_v		: natural := 192;	-- Spectrum Screen v = 192 pixels
	constant h_sync_on		: integer := 575;	-- (spec_screen_h * 2) + (spec_border_left * 2) - 1
	constant v_sync_on		: integer := 240;	

	signal spec_h_count_reg		: std_logic_vector(9 downto 0);
	signal spec_v_count_reg		: std_logic_vector(9 downto 0);

	signal gfx_paper		: std_logic;
	signal gfx_paper1		: std_logic;
	signal gfx_pixel		: std_logic_vector(7 downto 0);
	signal gfx_pixel_reg	: std_logic_vector(55 downto 0);
	signal gfx_rgb			: std_logic_vector(23 downto 0);
	-- the gfx pixel is 13 clocks ahead of the ordinary pixel of the same place: delayed to meet it
	-- (0xFF shows the ordinary pixel through)
	constant GFX_DELAY		: natural := 13;
	type gfx_dl_t is array (1 to GFX_DELAY) of std_logic_vector(8 downto 0);
	signal gfx_dl			: gfx_dl_t;
	signal gfx_px			: std_logic_vector(7 downto 0);
	signal gfx_px_paper	: std_logic;

	signal paper			: std_logic;
	signal paper0			: std_logic;	-- paper at the address of the column (the vertical counter steps inside column 31)
	signal paper1			: std_logic;
	signal pixel			: std_logic;	
	signal vid_reg			: std_logic_vector(7 downto 0);
	signal pixel_reg		: std_logic_vector(7 downto 0);
	signal attr_reg		: std_logic_vector(7 downto 0);
	signal addr_reg		: std_logic_vector(12 downto 0);
	signal rgb				: std_logic_vector(5 downto 0);
	signal flash			: std_logic_vector(4 downto 0) := (others => '0');
	signal int_sig			: std_logic;	

	-- the colour rules (ZX-Poly): the ink and paper of the attribute (FLASH applied), 2 bits per channel
	signal ink6, paper6		: std_logic_vector(5 downto 0);
	signal flashing		: std_logic;
	signal same			: std_logic;
	signal p00			: std_logic;
	signal mixed			: std_logic;
	signal sel_rgb			: std_logic_vector(23 downto 0);	-- the colour before the mixing
	signal std_rgb			: std_logic_vector(23 downto 0);	-- the ordinary pixel
	signal out_rgb			: std_logic_vector(23 downto 0);	-- the gfx pixel

begin

process (I_CLK, I_HCNT, I_VCNT, pixel)
begin
	if I_CLK'event and I_CLK = '1' then
		if I_HCNT = spec_border_left * 2 then
			spec_h_count_reg <= (others => '0');
		else
			spec_h_count_reg <= spec_h_count_reg + 1;
		end if;

		if I_HCNT = h_sync_on then
			if I_VCNT = spec_border_top * 2 then
				spec_v_count_reg <= (others => '0');
			else
				spec_v_count_reg <= spec_v_count_reg + 1;
			end if;
		end if;
		
		-- gfx pixel
		case spec_h_count_reg(3 downto 0) is
			when "0001" =>	gfx_pixel <= I_GFX_DATA(63) & I_GFX_DATA(55) & I_GFX_DATA(47) & I_GFX_DATA(39) & I_GFX_DATA(31) & I_GFX_DATA(23) & I_GFX_DATA(15) & I_GFX_DATA(7);
					gfx_pixel_reg <= I_GFX_DATA(62 downto 56) & I_GFX_DATA(54 downto 48) & I_GFX_DATA(46 downto 40) & I_GFX_DATA(38 downto 32) & I_GFX_DATA(30 downto 24) & I_GFX_DATA(22 downto 16) & I_GFX_DATA(14 downto 8) & I_GFX_DATA(6 downto 0);
					gfx_paper1 <= gfx_paper;
			when "0011" =>	gfx_pixel <= gfx_pixel_reg(55) & gfx_pixel_reg(48) & gfx_pixel_reg(41) & gfx_pixel_reg(34) & gfx_pixel_reg(27) & gfx_pixel_reg(20) & gfx_pixel_reg(13) & gfx_pixel_reg(6);
			when "0101" =>	gfx_pixel <= gfx_pixel_reg(54) & gfx_pixel_reg(47) & gfx_pixel_reg(40) & gfx_pixel_reg(33) & gfx_pixel_reg(26) & gfx_pixel_reg(19) & gfx_pixel_reg(12) & gfx_pixel_reg(5);
			when "0111" =>	gfx_pixel <= gfx_pixel_reg(53) & gfx_pixel_reg(46) & gfx_pixel_reg(39) & gfx_pixel_reg(32) & gfx_pixel_reg(25) & gfx_pixel_reg(18) & gfx_pixel_reg(11) & gfx_pixel_reg(4);
			when "1001" => gfx_pixel <= gfx_pixel_reg(52) & gfx_pixel_reg(45) & gfx_pixel_reg(38) & gfx_pixel_reg(31) & gfx_pixel_reg(24) & gfx_pixel_reg(17) & gfx_pixel_reg(10) & gfx_pixel_reg(3);
			when "1011" =>	gfx_pixel <= gfx_pixel_reg(51) & gfx_pixel_reg(44) & gfx_pixel_reg(37) & gfx_pixel_reg(30) & gfx_pixel_reg(23) & gfx_pixel_reg(16) & gfx_pixel_reg( 9) & gfx_pixel_reg(2);
			when "1101" =>	gfx_pixel <= gfx_pixel_reg(50) & gfx_pixel_reg(43) & gfx_pixel_reg(36) & gfx_pixel_reg(29) & gfx_pixel_reg(22) & gfx_pixel_reg(15) & gfx_pixel_reg( 8) & gfx_pixel_reg(1);
			when "1111" =>	gfx_pixel <= gfx_pixel_reg(49) & gfx_pixel_reg(42) & gfx_pixel_reg(35) & gfx_pixel_reg(28) & gfx_pixel_reg(21) & gfx_pixel_reg(14) & gfx_pixel_reg( 7) & gfx_pixel_reg(0);
			when others =>	null;
		end case;

		gfx_dl(1) <= gfx_paper1 & gfx_pixel;
		for i in 2 to GFX_DELAY loop
			gfx_dl(i) <= gfx_dl(i-1);
		end loop;
		
		-- std pixel
		case spec_h_count_reg(3 downto 1) is
			when "000" =>
				pixel <= pixel_reg(6);
			when "001" =>
				pixel <= pixel_reg(5);
			when "010" =>
				pixel <= pixel_reg(4);
			when "011" =>
				pixel <= pixel_reg(3);
			when "100" => 
				pixel <= pixel_reg(2);
				paper0 <= paper;
				addr_reg <= spec_v_count_reg(8 downto 7) & spec_v_count_reg(3 downto 1) & spec_v_count_reg(6 downto 4) & spec_h_count_reg(8 downto 4);
			when "101" =>
				pixel <= pixel_reg(1);
				vid_reg <= I_DATA;
			when "110" =>
				pixel <= pixel_reg(0);
				addr_reg <= "110" & spec_v_count_reg(8 downto 4) & spec_h_count_reg(8 downto 4);
			when "111" =>
				pixel <= vid_reg(7);
				pixel_reg <= vid_reg;
				attr_reg <= I_DATA;
				paper1 <= paper0;
			when others => null;
		end case;
		
	end if;
	
end process;

gfx_px		<= gfx_dl(GFX_DELAY)(7 downto 0);
gfx_px_paper	<= gfx_dl(GFX_DELAY)(8);

-- Spec256 palette: block RAM, the standard palette at start (sp256_palette.hex), written by the file
-- loader (the palette of the .256). Read with the gfx pixel one clock before it leaves the delay line.
process (I_PAL_CLK)
begin
	if rising_edge(I_PAL_CLK) then
		if I_PAL_WR = '1' then
			pal(to_integer(unsigned(I_PAL_A))) <= I_PAL_D;
		end if;
	end if;
end process;

process (I_CLK)
begin
	if rising_edge(I_CLK) then
		gfx_rgb <= pal(to_integer(unsigned(gfx_dl(GFX_DELAY-1)(7 downto 0))));
	end if;
end process;

process (I_CLK, int_sig)
begin
	if (I_CLK'event and I_CLK = '1') then
		if (int_sig = '1') then
			flash <= flash + 1;
		end if;
	end if;
end process;

int_sig		<= '1' when (spec_h_count_reg = h_sync_on and spec_v_count_reg = v_sync_on) else '0';

gfx_paper <= '1' when (spec_h_count_reg(9 downto 1) < spec_screen_h and spec_v_count_reg(9 downto 1) < spec_screen_v) else '0';
paper		<= '1' when (spec_h_count_reg(9 downto 1) < spec_screen_h and spec_v_count_reg(9 downto 1) < spec_screen_v) else '0';

O_ADDR <= addr_reg;
O_GFX_ADDR <= spec_v_count_reg(8 downto 7) & spec_v_count_reg(3 downto 1) & spec_v_count_reg(6 downto 4) & spec_h_count_reg(8 downto 4);

flashing <= flash(4) and attr_reg(7);
same <= '1' when attr_reg(2 downto 0) = attr_reg(5 downto 3) else '0';
ink6 <= attr_reg(1) & (attr_reg(1) and attr_reg(6)) & attr_reg(2) & (attr_reg(2) and attr_reg(6)) & attr_reg(0) & (attr_reg(0) and attr_reg(6)) when flashing = '0' else
	attr_reg(4) & (attr_reg(4) and attr_reg(6)) & attr_reg(5) & (attr_reg(5) and attr_reg(6)) & attr_reg(3) & (attr_reg(3) and attr_reg(6));
paper6 <= attr_reg(4) & (attr_reg(4) and attr_reg(6)) & attr_reg(5) & (attr_reg(5) and attr_reg(6)) & attr_reg(3) & (attr_reg(3) and attr_reg(6)) when flashing = '0' else
	attr_reg(1) & (attr_reg(1) and attr_reg(6)) & attr_reg(2) & (attr_reg(2) and attr_reg(6)) & attr_reg(0) & (attr_reg(0) and attr_reg(6));
rgb <= ink6 when pixel = '1' else paper6;

std_rgb <= rgb(5 downto 4) & rgb(5 downto 4) & rgb(5 downto 4) & rgb(5 downto 4) &
	rgb(3 downto 2) & rgb(3 downto 2) & rgb(3 downto 2) & rgb(3 downto 2) &
	rgb(1 downto 0) & rgb(1 downto 0) & rgb(1 downto 0) & rgb(1 downto 0);

-- the gfx pixel (docs/SIMD.md section 7): Pixel mode as before (0xFF shows the ordinary pixel); else
-- HideSameInkPaper, colour 0 / 0xFF as paper / ink with Paper00InkFF, the palette, and the colours
-- below DownColorsMixed or above 255 - UpColorsMixed mixed half and half with the ordinary pixel
p00 <= I_PAPER00INKFF when I_COLOUR_MODE = "00" else not I_COLOUR_MODE(1);

process (I_COLOUR_MODE, gfx_px, gfx_rgb, std_rgb, ink6, paper6, same, p00, I_HIDE_SAME)
begin
	if I_COLOUR_MODE = "11" then
		if gfx_px = x"FF" then sel_rgb <= std_rgb; else sel_rgb <= gfx_rgb; end if;
	elsif I_HIDE_SAME = '1' and same = '1' then
		sel_rgb <= ink6(5 downto 4) & ink6(5 downto 4) & ink6(5 downto 4) & ink6(5 downto 4) &
			ink6(3 downto 2) & ink6(3 downto 2) & ink6(3 downto 2) & ink6(3 downto 2) &
			ink6(1 downto 0) & ink6(1 downto 0) & ink6(1 downto 0) & ink6(1 downto 0);
	elsif p00 = '1' and gfx_px = x"00" then
		sel_rgb <= paper6(5 downto 4) & paper6(5 downto 4) & paper6(5 downto 4) & paper6(5 downto 4) &
			paper6(3 downto 2) & paper6(3 downto 2) & paper6(3 downto 2) & paper6(3 downto 2) &
			paper6(1 downto 0) & paper6(1 downto 0) & paper6(1 downto 0) & paper6(1 downto 0);
	elsif p00 = '1' and gfx_px = x"FF" then
		sel_rgb <= ink6(5 downto 4) & ink6(5 downto 4) & ink6(5 downto 4) & ink6(5 downto 4) &
			ink6(3 downto 2) & ink6(3 downto 2) & ink6(3 downto 2) & ink6(3 downto 2) &
			ink6(1 downto 0) & ink6(1 downto 0) & ink6(1 downto 0) & ink6(1 downto 0);
	else
		sel_rgb <= gfx_rgb;
	end if;
end process;

mixed <= '1' when I_COLOUR_MODE /= "11" and (unsigned(gfx_px) < unsigned(I_DOWN_MIXED) or
	unsigned(gfx_px) > 255 - unsigned(I_UP_MIXED)) else '0';

process (mixed, sel_rgb, std_rgb)
	variable r, g, b : unsigned(8 downto 0);
begin
	if mixed = '1' then
		r := ('0' & unsigned(sel_rgb(23 downto 16))) + unsigned(std_rgb(23 downto 16));
		g := ('0' & unsigned(sel_rgb(15 downto 8))) + unsigned(std_rgb(15 downto 8));
		b := ('0' & unsigned(sel_rgb(7 downto 0))) + unsigned(std_rgb(7 downto 0));
		out_rgb <= std_logic_vector(r(8 downto 1)) & std_logic_vector(g(8 downto 1)) & std_logic_vector(b(8 downto 1));
	else
		out_rgb <= sel_rgb;
	end if;
end process;

O_R <= (others => '0') when (I_BLANK = '1') else 
		 out_rgb(23 downto 16) when gfx_px_paper = '1' and I_MODE = '1' else
		 std_rgb(23 downto 16) when paper1 = '1' and I_MODE = '0' else 
		 (others => I_BORDER(1));
O_G <= (others => '0') when (I_BLANK = '1') else 
		 out_rgb(15 downto 8) when gfx_px_paper = '1' and I_MODE = '1' else
		 std_rgb(15 downto 8) when paper1 = '1' and I_MODE = '0' else 
		 (others => I_BORDER(2));
O_B <= (others => '0') when (I_BLANK = '1') else 
		 out_rgb(7 downto 0) when gfx_px_paper = '1' and I_MODE = '1' else
		 std_rgb(7 downto 0) when paper1 = '1' and I_MODE = '0' else 
		 (others => I_BORDER(0));

end architecture;

