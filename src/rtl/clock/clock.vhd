-------------------------------------------------------------------------------
-- Clocks
-------------------------------------------------------------------------------

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.std_logic_arith.conv_integer;
use IEEE.numeric_std.all;
use IEEE.std_logic_unsigned.all;

library unisim;
use unisim.vcomponents.all;

entity clock is
port (
	CLK			: in std_logic;     -- 50
	CLK_SDR		: buffer std_logic; -- 56
	CLK_SDR_OUT : buffer std_logic; -- 56 @ 180
	CLK_VGA		: buffer std_logic; -- 25
	ARESET 		: out std_logic
);
end clock;

architecture rtl of clock is

signal locked : std_logic := '0';
signal clk_56, clk_56_180, clk_25 : std_logic;
signal clkin1, clkfbout, clkfbout_buf, clkout0, clkout1, clkout2 : std_logic;

begin 

U1: IBUFG port map (O => clkin1, I => CLK);

U2: PLL_BASE
generic map (
	BANDWIDTH 				=> "OPTIMIZED",
   CLK_FEEDBACK			=> "CLKFBOUT",
   COMPENSATION			=> "SYSTEM_SYNCHRONOUS",
	DIVCLK_DIVIDE			=> 2,
	CLKFBOUT_MULT 			=> 27,
	CLKFBOUT_PHASE			=> 0.000,
	CLKOUT0_DIVIDE			=> 12,
	CLKOUT0_PHASE			=> 0.000,
   CLKOUT0_DUTY_CYCLE 	=> 0.500,
   CLKOUT1_DIVIDE			=> 12,
   CLKOUT1_PHASE			=> 180.000,
   CLKOUT1_DUTY_CYCLE 	=> 0.500,
   CLKOUT2_DIVIDE			=> 27,
   CLKOUT2_PHASE			=> 0.000,
	CLKOUT2_DUTY_CYCLE 	=> 0.500,
   CLKOUT3_DIVIDE			=> 27, 
   CLKOUT3_PHASE			=> 0.000,
   CLKOUT3_DUTY_CYCLE 	=> 0.500,
   CLKOUT4_DIVIDE			=> 27,
   CLKOUT4_PHASE 			=> 0.000,
   CLKOUT4_DUTY_CYCLE 	=> 0.500,
   CLKIN_PERIOD			=> 20.000,
   REF_JITTER				=> 0.010
)
port map (
   CLKFBOUT					=> clkfbout,
   CLKOUT0					=> clkout0, -- 56
   CLKOUT1          	 	=> clkout1, -- 56
   CLKOUT2           	=> clkout2, -- 25.2
   CLKOUT3           	=> open,
   CLKOUT4           	=> open,
   CLKOUT5           	=> open,
   LOCKED            	=> locked,
	RST 						=> '0',
   CLKFBIN           	=> clkfbout_buf,
   CLKIN             	=> clkin1
);
	
U3 : BUFG port map (O => clkfbout_buf, I => clkfbout);
U4 : BUFG port map (O => clk_56, I => clkout0);
U5 : BUFG port map (O => clk_56_180, I => clkout1);
U6 : BUFG port map (O => clk_25, I => clkout2);

CLK_SDR 		<= clk_56;
CLK_SDR_OUT <= clk_56_180;
CLK_VGA     <= clk_25;
ARESET 		<= not locked;

end rtl;