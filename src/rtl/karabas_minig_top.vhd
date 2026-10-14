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
-- FPGA Spec256 core for Karabas-Go Mini rev.G
--
-- @author Andy Karpov <https://github.com/andykarpov>
-- @author MVV <https://github.com/mvvproject>
-- EU, 2026
--
------------------------------------------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.std_logic_unsigned.all;

library UNISIM;
use UNISIM.VComponents.all;

entity karabas_minig is
   port ( 
    CLK_50MHZ            : in       std_logic;

    TAPE_IN              : in       std_logic;
    TAPE_OUT             : out      std_logic;

    DAC_BCK              : out      std_logic;
    DAC_WS               : out      std_logic;
    DAC_DAT              : out      std_logic;

    ADC_CLK              : out      std_logic;
    ADC_BCK              : out      std_logic;
    ADC_LRCK             : out      std_logic;
    ADC_DOUT             : in       std_logic;        

    UART_RX              : inout    std_logic;
    UART_TX              : inout    std_logic;
    UART_CTS             : inout    std_logic;

    ESP32_SPI_CS_N       : out      std_logic;
    ESP32_PCM_BCK        : in       std_logic;
    ESP32_PCM_RLCK       : in       std_logic;
    ESP32_PCM_DAT        : in       std_logic;

    WA                   : out      std_logic_vector (2 downto 0);
    WCS_N                : out      std_logic_vector (1 downto 0);
    WRD_N                : out      std_logic;
    WWR_N                : out      std_logic;
    WRESET_N             : out      std_logic;
    WD                   : inout    std_logic_vector (15 downto 0);

    MA                   : out      std_logic_vector (20 downto 0);
    MD                   : inout    std_logic_vector (15 downto 0);
    MWR_N                : out      std_logic_vector (1 downto 0);
    MRD_N                : out      std_logic_vector (1 downto 0);

    SDR_BA               : out      std_logic_vector (1 downto 0);
    SDR_A                : out      std_logic_vector (12 downto 0);
    SDR_CLK              : out      std_logic;
    SDR_DQM              : out      std_logic_vector (1 downto 0);
    SDR_WE_N             : out      std_logic;
    SDR_CAS_N            : out      std_logic;
    SDR_RAS_N            : out      std_logic;
    SDR_DQ               : inout    std_logic_vector (15 downto 0);

    SD_CS_N              : out      std_logic;
    SD_DI                : inout    std_logic;
    SD_DO                : inout    std_logic;
    SD_CLK               : out      std_logic;
    SD_DET_N             : in       std_logic;

    FT_SPI_CS_N          : out      std_logic;
    FT_SPI_SCK           : out      std_logic;
    FT_SPI_MISO          : inout    std_logic;
    FT_SPI_MOSI          : inout    std_logic;
    FT_INT_N             : inout    std_logic;
    FT_CLK               : inout    std_logic;
    FT_CLK_OUT           : inout    std_logic;
    FT_DE                : in       std_logic;

    VGA_R                : in       std_logic_vector (7 downto 0);
    VGA_G                : in       std_logic_vector (7 downto 0);
    VGA_B                : in       std_logic_vector (7 downto 0);
    VGA_HS               : in       std_logic;
    VGA_VS               : in       std_logic;

    TMDS_P               : out      std_logic_vector(3 downto 0);
    TMDS_N               : out      std_logic_vector(3 downto 0);        

    MCU_CS_N             : in       std_logic;
    MCU_SCK              : in       std_logic;
    MCU_MOSI             : in       std_logic;
    MCU_MISO             : out      std_logic;
    MCU_IO               : inout    std_logic_vector(5 downto 0); -- [0] burst cs_n, [1] burst ready, [2] sd2 cs_n, [3] ft cs_n
          
    MIDI_TX              : out      std_logic;

    FLASH_CS_N           : out      std_logic;
    FLASH_DO             : in       std_logic;
    FLASH_DI             : out      std_logic;
    FLASH_SCK            : out      std_logic;
    FLASH_WP_N           : out      std_logic;
    FLASH_HOLD_N         : out      std_logic        
);
end entity;

architecture rtl of karabas_minig is

-- signals
signal clk_bus, clk_vga, clk_sdr : std_logic;
signal areset, reset : std_logic;

signal vid_rgb : std_logic_vector(23 downto 0);
signal vid_hs, vid_vs, vid_blank: std_logic;

signal audio_mix_l, audio_mix_r : std_logic_vector(15 downto 0);
signal adc_l, adc_r : std_logic_vector(23 downto 0);

signal hdmi_rgb : std_logic_vector(23 downto 0);
signal hdmi_hsync, hdmi_vsync, hdmi_blank : std_logic;
signal dvi_only : std_logic;


-- burst transfers from the mcu (karabas-go-firmware docs/burst_protocol.md)
signal mcu_burst_ready : std_logic;

begin

MCU_IO(1) <= mcu_burst_ready;
MCU_IO(0) <= 'Z';
MCU_IO(5 downto 2) <= (others => 'Z');

U1: entity work.spec256
generic map(
    -- Rev.G has MCU_SCK on a global clock pin: bursts at up to 32 MHz
    BURST_MAX_MHZ     => 32
)
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
    MCU_BURST_CS_N    => MCU_IO(0), -- firmware IO0 (GPIO14), G6
    MCU_BURST_READY   => mcu_burst_ready,

    -- rgb
    VGA_RGB           => vid_rgb,
    VGA_HS            => vid_hs,
    VGA_VS            => vid_vs,
    VGA_BLANK         => vid_blank,
    DVI_ONLY          => dvi_only,

    -- audio
    BEEPER            => open, 
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

-- HDMI encoder
U2: entity work.zhdmi_top
generic map(
    SAMPLERATE        => 44100
)
port map(
    clk               => clk_vga,
    reset             => areset,
    vga_rgb           => vid_rgb,
    vga_hs            => vid_hs,
    vga_vs            => vid_vs,
    vga_de            => not vid_blank,
    audio_en          => not dvi_only,
    audio_l           => audio_mix_l,
    audio_r           => audio_mix_r,
    tmds_p            => TMDS_P,
    tmds_n            => TMDS_N
);

-- DAC
U3: entity work.PCM5102
generic map(
    DAC_CLK_DIV_BITS => 4
)
port map(
    clk              => CLK_BUS,
    reset            => areset,
    left             => audio_mix_l,
    right            => audio_mix_r,
    bck              => DAC_BCK,
    lrck             => DAC_WS,
    din              => DAC_DAT
);

-- unused signals
FT_SPI_CS_N         <= '1';
FT_SPI_SCK          <= '1';
FT_SPI_MOSI         <= '1';
ESP32_SPI_CS_N      <= '1';
FLASH_CS_N          <= '1';
FLASH_DI            <= '1';
FLASH_SCK           <= '1';
FLASH_WP_N          <= '1';
FLASH_HOLD_N        <= '1';
TAPE_OUT            <= '0';
ADC_CLK             <= '0';
ADC_BCK             <= '0';
ADC_LRCK            <= '0';
WA                  <= "000";
WCS_N               <= "11";
WRD_N               <= '1';
WWR_N               <= '1';
WRESET_N            <= '1';
--MA                  <= (others => '0');
--MD                  <= (others => 'Z');
--MWR_N               <= "11";
--MRD_N               <= "11";
SD_CS_N             <= '1';
SD_CLK              <= '1';
MIDI_TX             <= '1';

u_sdr_clk: ODDR2 -- negative DDR clock
generic map(DDR_ALIGNMENT => "NONE", INIT => '0', SRTYPE => "SYNC")
port map(Q => SDR_CLK, C0 => clk_sdr, C1 => not(clk_sdr), CE => '1', D0 => '0', D1 => '1', R => '0', S => '0');

end architecture;

