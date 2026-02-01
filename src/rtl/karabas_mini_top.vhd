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
-- FPGA Spec256 core for Karabas-Go Mini
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

entity karabas_mini is
port (
    CLK_50MHZ        : in     std_logic;

    UART_RX          : inout  std_logic;
    UART_TX          : inout  std_logic;
    UART_CTS         : inout  std_logic;
    ESP_RESET_N      : inout  std_logic;
    ESP_BOOT_N       : inout  std_logic;

    MA               : out    std_logic_vector (20 downto 0);
    MD               : inout  std_logic_vector (15 downto 0);
    MWR_N            : out    std_logic_vector (1 downto 0);
    MRD_N            : out    std_logic_vector (1 downto 0);

    SDR_BA           : out    std_logic_vector (1 downto 0);
    SDR_A            : out    std_logic_vector (12 downto 0);
    SDR_CLK          : out    std_logic;
    SDR_DQM          : out    std_logic_vector (1 downto 0);
    SDR_WE_N         : out    std_logic;
    SDR_CAS_N        : out    std_logic;
    SDR_RAS_N        : out    std_logic;
    SDR_DQ           : inout  std_logic_vector (15 downto 0);

    SD_CS_N          : out    std_logic := '1';
    SD_DI            : out    std_logic := '1';
    SD_DO            : in     std_logic;
    SD_CLK           : out    std_logic := '1';
    SD_DET_N         : in     std_logic;

    VGA_R            : in     std_logic_vector (7 downto 0);
    VGA_G            : in     std_logic_vector (7 downto 0);
    VGA_B            : in     std_logic_vector (7 downto 0);
    VGA_HS           : in     std_logic;
    VGA_VS           : in     std_logic;

    TMDS_P           : out    std_logic_vector(3 downto 0);
    TMDS_N           : out    std_logic_vector(3 downto 0);

    FT_SPI_CS_N      : out    std_logic;
    FT_SPI_SCK       : out    std_logic;
    FT_SPI_MISO      : inout  std_logic;
    FT_SPI_MOSI      : inout  std_logic;
    FT_INT_N         : inout  std_logic;
    FT_CLK           : inout  std_logic;
    FT_AUDIO         : in     std_logic;
    FT_DE            : in     std_logic;
    FT_DISP          : in     std_logic;
    FT_RESET         : out    std_logic;
    FT_CLK_OUT       : out    std_logic;

    WA               : out    std_logic_vector (2 downto 0);
    WCS_N            : out    std_logic_vector(1 downto 0);
    WRD_N            : out    std_logic;
    WWR_N            : out    std_logic;
    WRESET_N         : out    std_logic;
    WD               : inout  std_logic_vector (15 downto 0);

    TAPE_IN          : in     std_logic;
    TAPE_OUT         : out    std_logic;
    AUDIO_L          : out    std_logic;
    AUDIO_R          : out    std_logic;

    ADC_CLK          : out    std_logic;
    ADC_BCK          : out    std_logic;
    ADC_LRCK         : out    std_logic;
    ADC_DOUT         : in     std_logic;

    MCU_CS_N         : in     std_logic;
    MCU_SCK          : in     std_logic;
    MCU_MOSI         : in     std_logic;
    MCU_MISO         : out    std_logic;
    MCU_IO           : in     std_logic_vector(3 downto 0);

    MIDI_TX          : out    std_logic;
    MIDI_CLK         : out    std_logic;
    MIDI_RESET_N     : out    std_logic;

    FLASH_CS_N       : out    std_logic;
    FLASH_DO         : in     std_logic;
    FLASH_DI         : out    std_logic;
    FLASH_SCK        : out    std_logic;
    FLASH_WP_N       : out    std_logic;
    FLASH_HOLD_N     : out    std_logic
);
end karabas_mini;

architecture Behavioral of karabas_mini is

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

-- Audio PWM
U3: entity work.dac
port map(
    I_CLK             => clk_bus,
    I_RESET           => areset,
    I_DATA            => not(audio_mix_l(15)) & audio_mix_l(14 downto 0),
    O_DAC             => AUDIO_L
);

U4: entity work.dac
port map(
    I_CLK             => clk_bus,
    I_RESET           => areset,
    I_DATA            => not(audio_mix_r(15)) & audio_mix_r(14 downto 0),
    O_DAC             => AUDIO_R
);

-- unused signals
ESP_RESET_N           <= 'Z';
ESP_BOOT_N            <= 'Z';

FLASH_CS_N            <= '1';
FLASH_DI              <= '1';
FLASH_SCK             <= '1';
FLASH_WP_N            <= '1';
FLASH_HOLD_N          <= '1';

FT_SPI_CS_N           <= '1';
FT_SPI_SCK            <= '1';
FT_SPI_MOSI           <= '1';
FT_RESET              <= not reset;
FT_CLK_OUT            <= '0';

TAPE_OUT              <= '0';
ADC_CLK               <= '0';
ADC_BCK               <= '0';
ADC_LRCK              <= '0';

WA                    <= "000";
WCS_N                 <= "11";
WRD_N                 <= '1';
WWR_N                 <= '1';
WRESET_N              <= '1';

SD_CS_N               <= '1';
SD_CLK                <= '1';

MIDI_TX               <= '1';
MIDI_CLK              <= '0';
MIDI_RESET_N          <= '1';

u_sdr_clk: ODDR2 -- negative DDR clock
generic map(
    DDR_ALIGNMENT     => "NONE",
    INIT              => '0',
    SRTYPE            => "SYNC"
)
port map(
    Q                 => SDR_CLK, 
    C0                => clk_sdr, 
    C1                => not(clk_sdr), 
    CE                => '1', 
    D0                => '0', 
    D1                => '1', 
    R                 => '0', 
    S                 => '0'
);

end Behavioral;

