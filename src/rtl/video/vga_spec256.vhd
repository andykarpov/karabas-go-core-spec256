-------------------------------------------------------------------[09.07.2016]
-- VGA
-------------------------------------------------------------------------------
-- Engineer: MVV <mvvproject@gmail.com>

library IEEE; 
use IEEE.std_logic_1164.all; 
use IEEE.numeric_std.ALL;
use IEEE.std_logic_unsigned.all;

entity vga_spec256 is
port (
	I_CLK		: in std_logic;
    I_MODE      : in std_logic := '0';
    I_DATA      : in std_logic_vector(7 downto 0);
	I_GFX_DATA	: in std_logic_vector(63 downto 0);
	I_BORDER	: in std_logic_vector(2 downto 0);	-- Биты D0..D2 порта xxFE определяют цвет бордюра
	I_HCNT		: in std_logic_vector(9 downto 0);
	I_VCNT		: in std_logic_vector(9 downto 0);
	I_BLANK		: in std_logic;
    O_ADDR      : out std_logic_vector(12 downto 0);
	O_GFX_ADDR	: out std_logic_vector(12 downto 0);
	O_R		: out std_logic_vector(7 downto 0);	-- Red
	O_G		: out std_logic_vector(7 downto 0);	-- Green
	O_B		: out std_logic_vector(7 downto 0));	-- Blue
end entity;

architecture rtl of vga_spec256 is

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

-- Spec256 palette
process (gfx_px)
begin
	case gfx_px is
		when X"00" => gfx_rgb <= X"000000";
		when X"01" => gfx_rgb <= X"00009b";
		when X"02" => gfx_rgb <= X"172fab";
		when X"03" => gfx_rgb <= X"3763bb";
		when X"04" => gfx_rgb <= X"5b93cb";
		when X"05" => gfx_rgb <= X"83bfdb";
		when X"06" => gfx_rgb <= X"b3e3eb";
		when X"07" => gfx_rgb <= X"e7ffff";
		when X"08" => gfx_rgb <= X"b70000";
		when X"09" => gfx_rgb <= X"bf1717";
		when X"0a" => gfx_rgb <= X"cb3333";
		when X"0b" => gfx_rgb <= X"d35353";
		when X"0c" => gfx_rgb <= X"df7777";
		when X"0d" => gfx_rgb <= X"e79b9b";
		when X"0e" => gfx_rgb <= X"f3c3c3";
		when X"0f" => gfx_rgb <= X"ffefef";
		                       
		when X"10" => gfx_rgb <= X"003723";
		when X"11" => gfx_rgb <= X"07533b";
		when X"12" => gfx_rgb <= X"176f53";
		when X"13" => gfx_rgb <= X"2f8b73";
		when X"14" => gfx_rgb <= X"4fa78f";
		when X"15" => gfx_rgb <= X"73c3b3";
		when X"16" => gfx_rgb <= X"9fdfd3";
		when X"17" => gfx_rgb <= X"d3fff7";
		when X"18" => gfx_rgb <= X"ff4b00";
		when X"19" => gfx_rgb <= X"ff771f";
		when X"1a" => gfx_rgb <= X"ff9f3f";
		when X"1b" => gfx_rgb <= X"ffbf63";
		when X"1c" => gfx_rgb <= X"ffdb83";
		when X"1d" => gfx_rgb <= X"ffeba7";
		when X"1e" => gfx_rgb <= X"fff7c7";
		when X"1f" => gfx_rgb <= X"ffffeb";
                                       
		when X"20" => gfx_rgb <= X"672b00";
		when X"21" => gfx_rgb <= X"7b3b0b";
		when X"22" => gfx_rgb <= X"8f4f23";
		when X"23" => gfx_rgb <= X"a7673b";
		when X"24" => gfx_rgb <= X"bb835b";
		when X"25" => gfx_rgb <= X"d39f7f";
		when X"26" => gfx_rgb <= X"e7bfa7";
		when X"27" => gfx_rgb <= X"ffe7d7";
		when X"28" => gfx_rgb <= X"7f004b";
		when X"29" => gfx_rgb <= X"8f135b";
		when X"2a" => gfx_rgb <= X"a32b73";
		when X"2b" => gfx_rgb <= X"b34b8b";
		when X"2c" => gfx_rgb <= X"c76fa3";
		when X"2d" => gfx_rgb <= X"d79bbf";
		when X"2e" => gfx_rgb <= X"ebcbdf";
		when X"2f" => gfx_rgb <= X"ffffff";
                                       
		when X"30" => gfx_rgb <= X"0b2373";
		when X"31" => gfx_rgb <= X"1b3387";
		when X"32" => gfx_rgb <= X"2f479b";
		when X"33" => gfx_rgb <= X"4b63af";
		when X"34" => gfx_rgb <= X"677fc3";
		when X"35" => gfx_rgb <= X"8b9fd7";
		when X"36" => gfx_rgb <= X"b3bfeb";
		when X"37" => gfx_rgb <= X"dfe7ff";
		when X"38" => gfx_rgb <= X"337f23";
		when X"39" => gfx_rgb <= X"438f1f";
		when X"3a" => gfx_rgb <= X"53a31f";
		when X"3b" => gfx_rgb <= X"6bb31b";
		when X"3c" => gfx_rgb <= X"87c717";
		when X"3d" => gfx_rgb <= X"abd70f";
		when X"3e" => gfx_rgb <= X"cfeb07";
		when X"3f" => gfx_rgb <= X"ffff00";
                                       
		when X"40" => gfx_rgb <= X"c30000";
		when X"41" => gfx_rgb <= X"af1700";
		when X"42" => gfx_rgb <= X"bb3300";
		when X"43" => gfx_rgb <= X"c75300";
		when X"44" => gfx_rgb <= X"d77b00";
		when X"45" => gfx_rgb <= X"e3a300";
		when X"46" => gfx_rgb <= X"efcf00";
		when X"47" => gfx_rgb <= X"ffff00";
		when X"48" => gfx_rgb <= X"4b4b33";
		when X"49" => gfx_rgb <= X"636347";
		when X"4a" => gfx_rgb <= X"7b7b5b";
		when X"4b" => gfx_rgb <= X"979773";
		when X"4c" => gfx_rgb <= X"afaf8b";
		when X"4d" => gfx_rgb <= X"cbcba3";
		when X"4e" => gfx_rgb <= X"e3e3bf";
		when X"4f" => gfx_rgb <= X"ffffdb";
		                       
		when X"50" => gfx_rgb <= X"000000";
		when X"51" => gfx_rgb <= X"434343";
		when X"52" => gfx_rgb <= X"636363";
		when X"53" => gfx_rgb <= X"7f7f7f";
		when X"54" => gfx_rgb <= X"9f9f9f";
		when X"55" => gfx_rgb <= X"bbbbbb";
		when X"56" => gfx_rgb <= X"dbdbdb";
		when X"57" => gfx_rgb <= X"fbfbfb";
		when X"58" => gfx_rgb <= X"a36f57";
		when X"59" => gfx_rgb <= X"af7f63";
		when X"5a" => gfx_rgb <= X"bb8f6f";
		when X"5b" => gfx_rgb <= X"c7a37b";
		when X"5c" => gfx_rgb <= X"d7b78b";
		when X"5d" => gfx_rgb <= X"e3c79b";
		when X"5e" => gfx_rgb <= X"efdbab";
		when X"5f" => gfx_rgb <= X"ffefbb";
                                       
		when X"60" => gfx_rgb <= X"00abcb";
		when X"61" => gfx_rgb <= X"17b3cf";
		when X"62" => gfx_rgb <= X"33bbd7";
		when X"63" => gfx_rgb <= X"4fc7df";
		when X"64" => gfx_rgb <= X"6bcfe3";
		when X"65" => gfx_rgb <= X"8bdbeb";
		when X"66" => gfx_rgb <= X"afe7f3";
		when X"67" => gfx_rgb <= X"d3f3fb";
		when X"68" => gfx_rgb <= X"00d300";
		when X"69" => gfx_rgb <= X"17d717";
		when X"6a" => gfx_rgb <= X"2fdf2f";
		when X"6b" => gfx_rgb <= X"4be34b";
		when X"6c" => gfx_rgb <= X"67eb67";
		when X"6d" => gfx_rgb <= X"83ef83";
		when X"6e" => gfx_rgb <= X"a3f7a3";
		when X"6f" => gfx_rgb <= X"c3ffc3";
                                       
		when X"70" => gfx_rgb <= X"4f4f67";
		when X"71" => gfx_rgb <= X"5f5f7b";
		when X"72" => gfx_rgb <= X"73738f";
		when X"73" => gfx_rgb <= X"8b8ba7";
		when X"74" => gfx_rgb <= X"9f9fbb";
		when X"75" => gfx_rgb <= X"b7b7d3";
		when X"76" => gfx_rgb <= X"cbcbe7";
		when X"77" => gfx_rgb <= X"e7e7ff";
		when X"78" => gfx_rgb <= X"8b8300";
		when X"79" => gfx_rgb <= X"9b930f";
		when X"7a" => gfx_rgb <= X"aba323";
		when X"7b" => gfx_rgb <= X"bbb33b";
		when X"7c" => gfx_rgb <= X"cbc353";
		when X"7d" => gfx_rgb <= X"dbd773";
		when X"7e" => gfx_rgb <= X"ebe793";
		when X"7f" => gfx_rgb <= X"fffbbb";
		                       
		when X"80" => gfx_rgb <= X"375757";
		when X"81" => gfx_rgb <= X"3b6f6f";
		when X"82" => gfx_rgb <= X"3b8787";
		when X"83" => gfx_rgb <= X"3b9f9f";
		when X"84" => gfx_rgb <= X"33b7b7";
		when X"85" => gfx_rgb <= X"27cfcf";
		when X"86" => gfx_rgb <= X"17e7e7";
		when X"87" => gfx_rgb <= X"07ffff";
		when X"88" => gfx_rgb <= X"000000";
		when X"89" => gfx_rgb <= X"00001b";
		when X"8a" => gfx_rgb <= X"000037";
		when X"8b" => gfx_rgb <= X"00004f";
		when X"8c" => gfx_rgb <= X"00006b";
		when X"8d" => gfx_rgb <= X"000087";
		when X"8e" => gfx_rgb <= X"0000a3";
		when X"8f" => gfx_rgb <= X"0000bf";
		                       
		when X"90" => gfx_rgb <= X"000000";
		when X"91" => gfx_rgb <= X"1b0000";
		when X"92" => gfx_rgb <= X"370000";
		when X"93" => gfx_rgb <= X"4f0000";
		when X"94" => gfx_rgb <= X"6b0000";
		when X"95" => gfx_rgb <= X"870000";
		when X"96" => gfx_rgb <= X"a30000";
		when X"97" => gfx_rgb <= X"bf0000";
		when X"98" => gfx_rgb <= X"000000";
		when X"99" => gfx_rgb <= X"1b001b";
		when X"9a" => gfx_rgb <= X"370037";
		when X"9b" => gfx_rgb <= X"4f004f";
		when X"9c" => gfx_rgb <= X"6b006b";
		when X"9d" => gfx_rgb <= X"870087";
		when X"9e" => gfx_rgb <= X"a300a3";
		when X"9f" => gfx_rgb <= X"bf00bf";
                                       
		when X"a0" => gfx_rgb <= X"000000";
		when X"a1" => gfx_rgb <= X"001b00";
		when X"a2" => gfx_rgb <= X"003700";
		when X"a3" => gfx_rgb <= X"004f00";
		when X"a4" => gfx_rgb <= X"006b00";
		when X"a5" => gfx_rgb <= X"008700";
		when X"a6" => gfx_rgb <= X"00a300";
		when X"a7" => gfx_rgb <= X"00bf00";
		when X"a8" => gfx_rgb <= X"000000";
		when X"a9" => gfx_rgb <= X"001b1b";
		when X"aa" => gfx_rgb <= X"003737";
		when X"ab" => gfx_rgb <= X"004f4f";
		when X"ac" => gfx_rgb <= X"006b6b";
		when X"ad" => gfx_rgb <= X"008787";
		when X"ae" => gfx_rgb <= X"00a3a3";
		when X"af" => gfx_rgb <= X"00bfbf";
                                       
		when X"b0" => gfx_rgb <= X"000000";
		when X"b1" => gfx_rgb <= X"1b1b00";
		when X"b2" => gfx_rgb <= X"373700";
		when X"b3" => gfx_rgb <= X"4f4f00";
		when X"b4" => gfx_rgb <= X"6b6b00";
		when X"b5" => gfx_rgb <= X"878700";
		when X"b6" => gfx_rgb <= X"a3a300";
		when X"b7" => gfx_rgb <= X"bfbf00";
		when X"b8" => gfx_rgb <= X"000000";
		when X"b9" => gfx_rgb <= X"1b1b1b";
		when X"ba" => gfx_rgb <= X"373737";
		when X"bb" => gfx_rgb <= X"4f4f4f";
		when X"bc" => gfx_rgb <= X"6b6b6b";
		when X"bd" => gfx_rgb <= X"878787";
		when X"be" => gfx_rgb <= X"a3a3a3";
		when X"bf" => gfx_rgb <= X"bfbfbf";
                                       
		when X"c0" => gfx_rgb <= X"000000";
		when X"c1" => gfx_rgb <= X"000000";
		when X"c2" => gfx_rgb <= X"000000";
		when X"c3" => gfx_rgb <= X"000000";
		when X"c4" => gfx_rgb <= X"000000";
		when X"c5" => gfx_rgb <= X"000000";
		when X"c6" => gfx_rgb <= X"000000";
		when X"c7" => gfx_rgb <= X"000000";
		when X"c8" => gfx_rgb <= X"00003f";
		when X"c9" => gfx_rgb <= X"000057";
		when X"ca" => gfx_rgb <= X"000073";
		when X"cb" => gfx_rgb <= X"00008f";
		when X"cc" => gfx_rgb <= X"0000ab";
		when X"cd" => gfx_rgb <= X"0000c7";
		when X"ce" => gfx_rgb <= X"0000e3";
		when X"cf" => gfx_rgb <= X"0000ff";
		                       
		when X"d0" => gfx_rgb <= X"3f0000";
		when X"d1" => gfx_rgb <= X"570000";
		when X"d2" => gfx_rgb <= X"730000";
		when X"d3" => gfx_rgb <= X"8f0000";
		when X"d4" => gfx_rgb <= X"ab0000";
		when X"d5" => gfx_rgb <= X"c70000";
		when X"d6" => gfx_rgb <= X"e30000";
		when X"d7" => gfx_rgb <= X"ff0000";
		when X"d8" => gfx_rgb <= X"3f003f";
		when X"d9" => gfx_rgb <= X"570057";
		when X"da" => gfx_rgb <= X"730073";
		when X"db" => gfx_rgb <= X"8f008f";
		when X"dc" => gfx_rgb <= X"ab00ab";
		when X"dd" => gfx_rgb <= X"c700c7";
		when X"de" => gfx_rgb <= X"e300e3";
		when X"df" => gfx_rgb <= X"ff00ff";
                                       
		when X"e0" => gfx_rgb <= X"003f00";
		when X"e1" => gfx_rgb <= X"005700";
		when X"e2" => gfx_rgb <= X"007300";
		when X"e3" => gfx_rgb <= X"008f00";
		when X"e4" => gfx_rgb <= X"00ab00";
		when X"e5" => gfx_rgb <= X"00c700";
		when X"e6" => gfx_rgb <= X"00e300";
		when X"e7" => gfx_rgb <= X"00ff00";
		when X"e8" => gfx_rgb <= X"000000";
		when X"e9" => gfx_rgb <= X"002323";
		when X"ea" => gfx_rgb <= X"004747";
		when X"eb" => gfx_rgb <= X"006b6b";
		when X"ec" => gfx_rgb <= X"008f8f";
		when X"ed" => gfx_rgb <= X"00b3b3";
		when X"ee" => gfx_rgb <= X"00dbdb";
		when X"ef" => gfx_rgb <= X"00ffff";
                                       
		when X"f0" => gfx_rgb <= X"3f3f00";
		when X"f1" => gfx_rgb <= X"575700";
		when X"f2" => gfx_rgb <= X"737300";
		when X"f3" => gfx_rgb <= X"8f8f00";
		when X"f4" => gfx_rgb <= X"abab00";
		when X"f5" => gfx_rgb <= X"c7c700";
		when X"f6" => gfx_rgb <= X"e3e300";
		when X"f7" => gfx_rgb <= X"ffff00";
		when X"f8" => gfx_rgb <= X"3f3f3f";
		when X"f9" => gfx_rgb <= X"575757";
		when X"fa" => gfx_rgb <= X"737373";
		when X"fb" => gfx_rgb <= X"8f8f8f";
		when X"fc" => gfx_rgb <= X"ababab";
		when X"fd" => gfx_rgb <= X"c7c7c7";
		when X"fe" => gfx_rgb <= X"e3e3e3";
		when X"ff" => gfx_rgb <= X"ffffff";
		
		when others => null;
	end case;	
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

rgb <= attr_reg(4) & (attr_reg(4) and attr_reg(6)) & 
		 attr_reg(5) & (attr_reg(5) and attr_reg(6)) & 
		 attr_reg(3) & (attr_reg(3) and attr_reg(6)) when (pixel xor (flash(4) and attr_reg(7))) = '0' else
		 attr_reg(1) & (attr_reg(1) and attr_reg(6)) & 
		 attr_reg(2) & (attr_reg(2) and attr_reg(6)) & 
		 attr_reg(0) & (attr_reg(0) and attr_reg(6));

O_R <= (others => '0') when (I_BLANK = '1') else 
		 rgb(5 downto 4) & rgb(5 downto 4) & rgb(5 downto 4) & rgb(5 downto 4) when gfx_px_paper = '1' and I_MODE = '1' and gfx_px = x"FF" else
		 gfx_rgb(23 downto 16) when gfx_px_paper = '1' and I_MODE = '1' else
		 rgb(5 downto 4) & rgb(5 downto 4) & rgb(5 downto 4) & rgb(5 downto 4) when paper1 = '1' and I_MODE = '0' else 
		 (others => I_BORDER(1));

O_G <= (others => '0') when (I_BLANK = '1') else 
		 rgb(3 downto 2) & rgb(3 downto 2) & rgb(3 downto 2) & rgb(3 downto 2) when gfx_px_paper = '1' and I_MODE = '1' and gfx_px = x"FF" else
		 gfx_rgb(15 downto 8) when gfx_px_paper = '1' and I_MODE = '1' else 
		 rgb(3 downto 2) & rgb(3 downto 2) & rgb(3 downto 2) & rgb(3 downto 2) when paper1 = '1' and I_MODE = '0' else 		 
		 (others => I_BORDER(2));
O_B <= (others => '0') when (I_BLANK = '1') else 
		 rgb(1 downto 0) & rgb(1 downto 0) & rgb(1 downto 0) & rgb(1 downto 0) when gfx_px_paper = '1' and I_MODE = '1' and gfx_px = x"FF" else
		 gfx_rgb(7 downto 0) when gfx_px_paper = '1' and I_MODE = '1' else 
		 rgb(1 downto 0) & rgb(1 downto 0) & rgb(1 downto 0) & rgb(1 downto 0) when paper1 = '1' and I_MODE = '0' else 
		 (others => I_BORDER(0));

end architecture;

