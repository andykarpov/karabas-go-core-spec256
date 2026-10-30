-------------------------------------------------------------------[14.08.2016]
-- Sync
-------------------------------------------------------------------------------
-- Engineer: MVV <mvvproject@gmail.com>

library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_unsigned.all;
use IEEE.STD_LOGIC_ARITH.all;

entity sync is port (
	I_CLK		: in std_logic; 			-- VGA dot clock
	I_EN		: in std_logic;
	O_HCNT		: out std_logic_vector(9 downto 0);
	O_VCNT		: out std_logic_vector(9 downto 0);
	O_INT		: out std_logic;
	O_FLASH		: out std_logic;			-- частота мерцания курсора
	O_BLANK		: out std_logic;
	O_HSYNC		: out std_logic;			-- horizontal (line) sync
	O_VSYNC		: out std_logic);			-- vertical (frame) sync
end entity;

architecture rtl of sync is

-- karabas: CEA-861 720x576@50Hz (576p, VIC 17), 27 MHz: 864 x 625 = 50.00 Hz, so INT comes 50 times a second as
-- on the Spectrum (640x480@60 gave 59.5 and games ran about 19 % fast)
-- ModeLine "720x576@50Hz"  27,000 720 732 796 864 576 581 586 625 -HSync -VSync
	-- Horizontal Timing constants  
	constant h_pixels_across	: integer := 720 - 1;
	constant h_sync_on		: integer := 732 - 1;
	constant h_sync_off		: integer := 796 - 1;
	constant h_end_count		: integer := 864 - 1;
	-- Vertical Timing constants
	constant v_pixels_down		: integer := 576 - 1;
	constant v_sync_on		: integer := 581 - 1;
	constant v_sync_off		: integer := 586 - 1;
	constant v_end_count		: integer := 625 - 1;

	signal hcnt			: std_logic_vector(9 downto 0) := "0000000000"; 	-- horizontal pixel counter
	signal vcnt			: std_logic_vector(9 downto 0) := "0000000000"; 	-- vertical line counter
	signal hsync			: std_logic;
	signal vsync			: std_logic;
	signal blank			: std_logic;
	signal int			: std_logic;
	signal counter			: std_logic_vector(5 downto 0);
	
begin
		
	process (I_CLK, I_EN, hcnt, int)
	begin
		if I_CLK'event and I_CLK = '1' then
			if I_EN = '1' then
				if hcnt = h_end_count then
					hcnt <= (others => '0');
				else
					hcnt <= hcnt + 1;
				end if;
				if hcnt = h_sync_on then
					if vcnt = v_end_count then
						vcnt <= (others => '0');
					else
						vcnt <= vcnt + 1;
					end if;
				end if;
				if int = '1' then
					counter <= counter + 1;
				end if;
			end if;
		end if;
	end process;

	hsync	<= '1' when (hcnt <= h_sync_on) or (hcnt > h_sync_off) else '0';
	vsync	<= '1' when (vcnt <= v_sync_on) or (vcnt > v_sync_off) else '0';
	blank	<= '1' when (hcnt > h_pixels_across) or (vcnt > v_pixels_down) else '0';
	int	<= '1' when (hcnt = h_sync_on and vcnt = v_sync_on) else '0';

	O_HCNT	<= hcnt;
	O_VCNT	<= vcnt;
	O_INT	<= int;
	O_FLASH	<= counter(5);
	O_HSYNC <= hsync;
	O_BLANK <= blank;
	O_VSYNC	<= vsync;

end architecture;