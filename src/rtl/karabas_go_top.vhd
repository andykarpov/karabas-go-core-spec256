-------------------------------------------------------------------------------------------------------------------
-- 
-- 
-- #       #######                                                 #                                               
-- #                                                               #                                               
-- #                                                               #                                               
-- ############### ############### ############### ############### ############### ############### ############### 
-- #             #               # #                             # #             #               # #               
-- #             # ############### #               ############### #             # ############### ############### 
-- #             # #             # #               #             # #             # #             #               # 
-- #             # ############### #               ############### ############### ############### ############### 
--                                                                                                                 
--         ####### ####### ####### #######                                         ############### ############### 
--                                                                                 #               #             # 
--                                                                                 #   ########### #             # 
--                                                                                 #             # #             # 
-- https://github.com/andykarpov/karabas-go                                        ############### ############### 
--
-- FPGA Spec256 core for Karabas-Go
--
-- @author Andy Karpov <https://github.com/andykarpov>
-- @author MVV <https://github.com/mvvproject>
-- EU, 2026

------------------------------------------------------------------------------------------------------------------

library IEEE; 
use IEEE.std_logic_1164.all; 
use IEEE.std_logic_unsigned.all;
use IEEE.numeric_std.all; 

library unisim;
use unisim.vcomponents.all;

entity karabas_go is
port (
	CLK_50MHZ 			: in  STD_LOGIC;

	TAPE_IN 				: in  STD_LOGIC;
	TAPE_OUT 			: out  STD_LOGIC;
	BEEPER 				: out  STD_LOGIC;

	DAC_LRCK 			: out  STD_LOGIC;
	DAC_DAT 				: out  STD_LOGIC;
	DAC_BCK 				: out  STD_LOGIC;
	DAC_MUTE 			: out  STD_LOGIC;

	ESP_RESET_N 		: inout  STD_LOGIC;
	ESP_BOOT_N 			: inout  STD_LOGIC;
	UART_RX 				: inout  STD_LOGIC;
	UART_TX 				: inout  STD_LOGIC;
	UART_CTS 			: inout  STD_LOGIC;

	WA 					: out  STD_LOGIC_VECTOR (2 downto 0);
	WCS_N 				: out  STD_LOGIC_VECTOR(1 downto 0);
	WRD_N 				: out  STD_LOGIC;
	WWR_N 				: out  STD_LOGIC;
	WRESET_N 			: out  STD_LOGIC;
	WD 					: inout  STD_LOGIC_VECTOR (15 downto 0);

	MA 					: out  STD_LOGIC_VECTOR (20 downto 0);
	MD 					: inout  STD_LOGIC_VECTOR (15 downto 0);
	MWR_N 				: out  STD_LOGIC_VECTOR (1 downto 0);
	MRD_N 				: out  STD_LOGIC_VECTOR (1 downto 0);

	SDR_BA 				: out  STD_LOGIC_VECTOR (1 downto 0);
	SDR_A 				: out  STD_LOGIC_VECTOR (12 downto 0);
	SDR_CLK 				: out  STD_LOGIC;
	SDR_DQM 				: out  STD_LOGIC_VECTOR (1 downto 0);
	SDR_WE_N 			: out  STD_LOGIC;
	SDR_CAS_N 			: out  STD_LOGIC;
	SDR_RAS_N 			: out  STD_LOGIC;
	SDR_DQ 				: inout  STD_LOGIC_VECTOR (15 downto 0);

	SD_CS_N 				: out  STD_LOGIC := '1';
	SD_DI 				: out  STD_LOGIC := '1';
	SD_DO 				: in  STD_LOGIC;
	SD_CLK 				: out  STD_LOGIC := '1';
	SD_DET_N 			: in  STD_LOGIC;

	FDC_INDEX 			: in  STD_LOGIC;
	FDC_DRIVE 			: out  STD_LOGIC_VECTOR (1 downto 0);
	FDC_MOTOR 			: out  STD_LOGIC;
	FDC_DIR 				: out  STD_LOGIC;
	FDC_STEP 			: out  STD_LOGIC;
	FDC_WDATA 			: out  STD_LOGIC;
	FDC_WGATE 			: out  STD_LOGIC;
	FDC_TR00 			: in  STD_LOGIC;
	FDC_WPRT 			: in  STD_LOGIC;
	FDC_RDATA 			: in  STD_LOGIC;
	FDC_SIDE_N 			: out  STD_LOGIC;

	FT_SPI_CS_N 		: out  STD_LOGIC;
	FT_SPI_SCK 			: out  STD_LOGIC;
	FT_SPI_MISO 		: inout  STD_LOGIC;
	FT_SPI_MOSI 		: inout  STD_LOGIC;
	FT_INT_N 			: inout  STD_LOGIC;
	FT_CLK 				: inout  STD_LOGIC;
	FT_OE_N 				: out  STD_LOGIC;

	VGA_R 				: out  STD_LOGIC_VECTOR (7 downto 0);
	VGA_G 				: out  STD_LOGIC_VECTOR (7 downto 0);
	VGA_B 				: out  STD_LOGIC_VECTOR (7 downto 0);
	VGA_HS 				: out  STD_LOGIC;
	VGA_VS 				: out  STD_LOGIC;
	V_CLK 				: out  STD_LOGIC;

	MCU_CS_N 			: in  STD_LOGIC;
	MCU_SCK 				: in  STD_LOGIC;
	MCU_MOSI 			: in  STD_LOGIC;
	MCU_MISO 			: out  STD_LOGIC;
	MCU_IO 			: inout  std_logic_vector(3 downto 0);

	MIDI_TX 				: out std_logic;
	MIDI_CLK 			: out std_logic;
	MIDI_RESET_N 		: out std_logic;

	FLASH_CS_N 			: out std_logic;
	FLASH_DO 			: in std_logic;
	FLASH_DI 			: out std_logic;
	FLASH_SCK 			: out std_logic;
	FLASH_WP_N 			: out std_logic;
	FLASH_HOLD_N 		: out std_logic
);
end karabas_go;

architecture Behavioral of karabas_go is

-- signals
signal clk_bus, clk_vga, clk_sdr : std_logic;
signal areset, reset : std_logic;

signal vid_rgb : std_logic_vector(23 downto 0);
signal vid_hs, vid_vs, vid_blank: std_logic;

signal audio_mix_l, audio_mix_r : std_logic_vector(15 downto 0);
signal adc_l, adc_r : std_logic_vector(23 downto 0);

begin

U1: entity work.spec256
port map(
    -- clock
    CLK_50MHZ         => CLK_50MHZ,
    CLK_BUS           => clk_bus,
    CLK_SDR_OUT       => clk_sdr,
    CLK_VGA           => clk_vga,

    -- resets
    RESET             => reset,
    ARESET            => areset,

    -- mcu
    MCU_CS_N          => MCU_CS_N,
    MCU_SCK           => MCU_SCK,
    MCU_MOSI          => MCU_MOSI,
    MCU_MISO          => MCU_MISO,
    MCU_IO            => MCU_IO(3 downto 0),

    -- rgb
    VGA_RGB           => vid_rgb,
    VGA_HS            => vid_hs,
    VGA_VS            => vid_vs,
    VGA_BLANK         => open,
    DVI_ONLY          => open,

    -- audio
    BEEPER            => BEEPER, 
    AUDIO_L           => audio_mix_l,
    AUDIO_R           => audio_mix_r,

	 -- sdram
    DRAM_NRAS         => SDR_RAS_N,
    DRAM_NCAS         => SDR_CAS_N,
    DRAM_NWE          => SDR_WE_N,
    DRAM_DQM          => SDR_DQM,
    DRAM_BA           => SDR_BA,
    DRAM_A            => SDR_A,
    DRAM_DQ           => SDR_DQ,
	 
	 -- sram
	 MA					 => MA,
	 MD					 => MD,
	 MRD_N				 => MRD_N,
	 MWR_N				 => MWR_N	 
);

-- Audio I2S DAC
U3: entity work.pcm5102
port map (
	clk 				=> clk_bus,
	reset 			=> reset,
	
	left 				=> audio_mix_l,
	right 			=> audio_mix_r,
	
	lrck 				=> DAC_LRCK,
	bck 				=> DAC_BCK,
	din 				=> DAC_DAT
);

DAC_MUTE 			<= '1';

VCLK_buf: ODDR2 port map(Q => V_CLK, C0 => clk_vga, C1 => not clk_vga, D0 => '1', D1 => '0');
VGA_R 				<= vid_rgb(23 downto 16);
VGA_G 				<= vid_rgb(15 downto 8);
VGA_B 				<= vid_rgb(7 downto 0);
VGA_HS 				<= vid_hs;
VGA_VS 				<= vid_vs;

ESP_RESET_N 		<= 'Z';
ESP_BOOT_N 			<= 'Z';

FT_SPI_CS_N			<= '1';
FT_SPI_SCK 			<= '0';
FT_OE_N 				<= '1';

MIDI_CLK				<= '0';
MIDI_RESET_N		<= '1';
MIDI_TX				<= '0';
TAPE_OUT				<= '0';

FLASH_CS_N 			<= '1';
FLASH_DI 			<= '1';
FLASH_SCK 			<= '1';
FLASH_WP_N 			<= '1';
FLASH_HOLD_N 		<= '1';

FDC_DRIVE			<= "11";
FDC_SIDE_N			<= '1';
FDC_WDATA			<= '1';
FDC_MOTOR			<= '1';
FDC_WGATE			<= '1';
FDC_STEP				<= '1';
FDC_DIR				<= '1';

WCS_N					<= "11";
WRESET_N				<= '1';
WA						<= "000";
WRD_N					<= '1';
WWR_N					<= '1';

u_sdr_clk: ODDR2 -- negative DDR clock
generic map(
	DDR_ALIGNMENT 	=> "NONE",
	INIT				=> '0',
	SRTYPE			=> "SYNC"
)
port map(
	Q 					=> SDR_CLK, 
	C0 				=> clk_sdr, 
	C1 				=> not(clk_sdr), 
	CE 				=> '1', 
	D0 				=> '0', 
	D1 				=> '1', 
	R 					=> '0', 
	S 					=> '0'
);

end Behavioral;

