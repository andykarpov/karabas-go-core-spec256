-------------------------------------------------------------------[30.01.2026]
-- Spec256
-- DEVBOARD Karabas Go
-------------------------------------------------------------------------------
-- Original source by: MVV <mvvproject@gmail.com>
-- Port to Karabas Go by: Andy Karpov <andy.karpov@gmail.com>
--
-- https://github.com/mvvproject/ReVerSE-U16
-- https://github.com/andykarpov/karabas-go-core-spec256
--
-- Copyright (c) 2016 Vladislav Matlash
-- Copyright (c) 2026 Andy Kaprov
--
-- All rights reserved
--
-- Redistribution and use in source and synthezised forms, with or without
-- modification, are permitted provided that the following conditions are met:
--
-- * Redistributions of source code must retain the above copyright notice,
--   this list of conditions and the following disclaimer.
--
-- * Redistributions in synthesized form must reproduce the above copyright
--   notice, this list of conditions and the following disclaimer in the
--   documentation and/or other materials provided with the distribution.
--
-- * Neither the name of the author nor the names of other contributors may
--   be used to endorse or promote products derived from this software without
--   specific prior written agreement from the author.
--
-- * License is granted for non-commercial use only.  A fee may not be charged
--   for redistributions as source code or in synthesized/hardware form without 
--   specific prior written agreement from the author.
--
-- THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
-- AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO,
-- THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR
-- PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE AUTHOR OR CONTRIBUTORS BE
-- LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
-- CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
-- SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
-- INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
-- CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
-- ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
-- POSSIBILITY OF SUCH DAMAGE.

library IEEE; 
use IEEE.std_logic_1164.all; 
use IEEE.std_logic_unsigned.all;
use IEEE.numeric_std.all; 

entity spec256 is
generic (
    -- operands of the instruction stream (LD A,n ...) of the lanes: from the main memory (NextTang)
    -- or from the lane planes (GZX), see docs/SIMD.md 1.2
    GFX_INST_FROM_MAIN : boolean := true;
    -- the highest burst sck of the mcu link in the CAPS answer, MHz (0: the normal link clock), see kg_mcu
    BURST_MAX_MHZ      : integer := 0
);
port (
    -- Clock
    CLK_50MHZ   : in std_logic;    -- 50MHz
    CLK_BUS     : buffer std_logic;
    CLK_VGA     : buffer std_logic;
    CLK_SDR_OUT : out std_logic;

    -- resets
    ARESET      : buffer std_logic;
    RESET       : buffer std_logic;

    -- mcu
    MCU_CS_N    : in  std_logic;
    MCU_SCK     : in  std_logic;
    MCU_MOSI    : in  std_logic;
    MCU_MISO    : out std_logic;
    MCU_IO      : in  std_logic_vector(3 downto 0);  -- [0] burst cs_n, [2] sd2 cs_n, [3] ft cs_n
    MCU_BURST_READY : out std_logic;

    -- VGA
    VGA_RGB     : out std_logic_vector(23 downto 0);
    VGA_HS      : out std_logic;
    VGA_VS      : out std_logic;
    VGA_BLANK   : out std_logic;
    DVI_ONLY    : out std_logic;

    -- Audio
    BEEPER      : out STD_LOGIC;
    AUDIO_L     : out std_logic_vector(15 downto 0);
    AUDIO_R     : out std_logic_vector(15 downto 0);

    --- SDRAM
    DRAM_NRAS   : out std_logic;
    DRAM_NCAS   : out std_logic;
    DRAM_NWE    : out std_logic;
    DRAM_DQM    : out std_logic_vector(1 downto 0);
    DRAM_BA     : out std_logic_vector(1 downto 0);
    DRAM_A      : out std_logic_vector(12 downto 0);
    DRAM_DQ     : inout std_logic_vector(15 downto 0);
     
    -- SRAM
    MA          : out std_logic_vector(20 downto 0);
    MD          : inout std_logic_vector(15 downto 0);
    MRD_N       : out std_logic_vector(1 downto 0);
    MWR_N       : out std_logic_vector(1 downto 0)
);
end spec256;

architecture rtl of spec256 is

-- CPU
signal cpu_reset_n   : std_logic;
signal cpu_addr      : std_logic_vector(15 downto 0);
signal cpu_mreq_n    : std_logic;
signal cpu_iorq_n    : std_logic;
signal cpu_wr_n      : std_logic;
signal cpu_rd_n      : std_logic;
signal cpu_int_n     : std_logic := '1';
signal cpu_m1_n      : std_logic;
signal cpu_nmi_n     : std_logic;
signal cpu_ena       : std_logic;
signal cpu_clken     : std_logic;
signal regs_wr_d     : std_logic := '0';
signal cpu_do        : std_logic_vector(7 downto 0);
signal cpu_di        : std_logic_vector(7 downto 0);
signal cpu_gfx_do    : std_logic_vector(63 downto 0);
signal cpu_gfx_di    : std_logic_vector(63 downto 0);
signal cpu_inst      : std_logic;  -- the address is the instruction stream
signal cpu_ga        : std_logic_vector(127 downto 0);  -- the addresses of the lanes (T80_S256 GA)
signal cpu_ga_en     : std_logic;
signal lane_a        : std_logic_vector(127 downto 0);
signal lane_en       : std_logic;

-- Memory
signal vram_wr       : std_logic;
signal vram_gfx_wr   : std_logic;
signal vram_addr     : std_logic_vector(12 downto 0);
signal vram_gfx_addr : std_logic_vector(12 downto 0);
signal vram_di       : std_logic_vector(7 downto 0);
signal vram_gfx_di   : std_logic_vector(63 downto 0);

-- Ports
signal port_xxfe_reg : std_logic_vector(7 downto 0);

-- Keyboard
signal kb_do         : std_logic_vector(4 downto 0);
signal joy_do        : std_logic_vector(7 downto 0);

-- Sound: AY-3-8910 at 1.7734 MHz (as the 128K), the mixer, the level meters of the mcu
constant CLK_BUS_HZ  : integer := 56250000;
constant AY_HZ       : integer := 1773400;
signal ay_acc        : integer range 0 to CLK_BUS_HZ - 1 := 0;
signal ay_ce         : std_logic := '0';
signal ay_reset      : std_logic;
signal ay_bdir       : std_logic;
signal ay_bc         : std_logic;
signal ay_do         : std_logic_vector(7 downto 0);
signal ay_a          : std_logic_vector(7 downto 0);
signal ay_b          : std_logic_vector(7 downto 0);
signal ay_c          : std_logic_vector(7 downto 0);
signal kb_ay_mode    : std_logic_vector(1 downto 0);
signal mix_l         : unsigned(10 downto 0) := (others => '0');
signal mix_r         : unsigned(10 downto 0) := (others => '0');
signal audio_mix_l   : std_logic_vector(15 downto 0);
signal audio_mix_r   : std_logic_vector(15 downto 0);
signal matrix_cmd    : std_logic_vector(23 downto 0);
signal matrix_cmd_wr : std_logic;

-- MCU
signal hid_kb_status : std_logic_vector(7 downto 0);
signal hid_kb_dat0   : std_logic_vector(7 downto 0);
signal hid_kb_dat1   : std_logic_vector(7 downto 0);
signal hid_kb_dat2   : std_logic_vector(7 downto 0);
signal hid_kb_dat3   : std_logic_vector(7 downto 0);
signal hid_kb_dat4   : std_logic_vector(7 downto 0);
signal hid_kb_dat5   : std_logic_vector(7 downto 0);
signal joy_l         : std_logic_vector(12 downto 0);
signal joy_r         : std_logic_vector(12 downto 0);
signal kb_joy_type_l : std_logic_vector(2 downto 0) := "000";
signal kb_joy_type_r : std_logic_vector(2 downto 0) := "000";
signal romloader_act : std_logic := '0';
signal romloader_do  : std_logic_vector(7 downto 0);
signal romloader_a   : std_logic_vector(31 downto 0);
signal romloader_wr  : std_logic := '0';
signal fileloader_act: std_logic := '0';
signal fileloader_sna: std_logic := '0';
signal fileloader_gfx: std_logic := '0';
signal fileloader_do : std_logic_vector(7 downto 0);
signal fileloader_a  : std_logic_vector(31 downto 0);
signal fileloader_wr : std_logic := '0';
signal fileloader_a8 : std_logic_vector(15 downto 0);
signal fileloader_wr8: std_logic := '0';
signal fileloader_do8: std_logic_vector(7 downto 0);
signal fileloader_a64: std_logic_vector(15 downto 0);
signal fileloader_wr64: std_logic := '0';
signal fileloader_do64: std_logic_vector(63 downto 0);
signal fileloader_buf: std_logic_vector(63 downto 0);
signal prev_fileloader_act : std_logic := '0';
signal regs          : std_logic_vector(223 downto 0);
signal regs_wr       : std_logic := '0';
-- the extension of the .256 (docs/SIMD.md section 7): the header, the palette, the ROM planes
constant EXT_BASE    : integer := 442396;
signal ext_magic     : std_logic := '0';                        -- the header so far is "K256"
signal ext_hdr       : std_logic_vector(23 downto 0) := (others => '0');  -- flags, UpColorsMixed, DownColorsMixed
signal fileloader_rom: std_logic := '0';                        -- writing the ROM planes
signal rom_gfx       : std_logic := '0';                        -- the game has ROM planes (.GFB)
signal rom_gfx0      : std_logic := '0';                        -- and planes of the ROM 0 (.GFA, flag 4)
signal rom_gfx_cur   : std_logic;                               -- planes for the ROM paged in
-- the 128K (flag 5): the block after the backgrounds, 8 bytes (#7FFD, reserved), then the banks 1, 3,
-- 4, 6, 7, each 16384 bytes of RAM and 131072 of planes
signal x128          : std_logic := '0';
signal x_hdr         : std_logic_vector(3 downto 0) := (others => '0');  -- bytes of the header, bit 3: done
signal x_idx         : integer range 0 to 7 := 0;               -- the bank in the block, 5: all written
signal x_pl          : std_logic := '0';                        -- the planes of the bank
signal x_off         : std_logic_vector(16 downto 0) := (others => '0');
signal p7ffd_load    : std_logic_vector(5 downto 0) := "110000";
-- the banks of the SRAM (pager.vhd): of the address, or of the loader for the ROM planes and the 128K block
signal pg_set        : std_logic;
signal pg_set_val    : std_logic_vector(5 downto 0);
signal pg_bank       : std_logic_vector(3 downto 0);
signal p7ffd         : std_logic_vector(5 downto 0);
signal ld_bank       : std_logic_vector(3 downto 0) := (others => '0');
signal ld_ov         : std_logic := '0';
signal sdram_bank    : std_logic_vector(3 downto 0);
signal pal_wr        : std_logic := '0';
signal pal_a         : std_logic_vector(7 downto 0) := (others => '0');
signal pal_d         : std_logic_vector(23 downto 0);
signal pal_rg        : std_logic_vector(15 downto 0);
signal pal_byte      : integer range 0 to 2 := 0;
signal pal_next      : std_logic_vector(7 downto 0) := (others => '0');
-- the colour rules of the game: the defaults of ZX-Poly without a background until the file says
signal s_paper00inkff: std_logic := '1';
signal s_hide_same   : std_logic := '1';
signal s_up_mixed    : std_logic_vector(7 downto 0) := x"40";
signal s_down_mixed  : std_logic_vector(7 downto 0) := x"00";
signal kb_colour_mode: std_logic_vector(1 downto 0);
-- the backgrounds (SDRAM, docs/SIMD.md section 7)
signal s_bk_over_ff  : std_logic := '0';
signal bg_count      : std_logic_vector(7 downto 0) := (others => '0');
signal bg_on         : std_logic := '0';
signal bg_cur        : std_logic_vector(7 downto 0) := (others => '0');
signal bg_first      : std_logic_vector(7 downto 0) := (others => '0');
signal bg_mask       : std_logic_vector(15 downto 0) := (others => '0');
signal bg_base       : std_logic_vector(31 downto 0) := (others => '0');  -- offset of the backgrounds in the extension
signal bg_wr         : std_logic := '0';
signal bg_wr_a       : std_logic_vector(23 downto 0) := (others => '0');
signal bg_wr_d       : std_logic_vector(7 downto 0) := (others => '0');
signal bg_wr_n       : std_logic_vector(7 downto 0) := (others => '0');
signal bg_wr_off     : std_logic_vector(15 downto 0) := (others => '0');
type rule8_t is array (0 to 15) of std_logic_vector(7 downto 0);
type rule16_t is array (0 to 15) of std_logic_vector(15 downto 0);
signal rule_bg       : rule8_t := (others => x"FF");
signal rule_val      : rule8_t := (others => x"00");
signal rule_addr     : rule16_t := (others => x"0000");
signal rule_m        : std_logic_vector(15 downto 0) := (others => '0');
signal vga_bg_req    : std_logic;
signal vga_bg_y      : std_logic_vector(7 downto 0);
signal bg_req_s      : std_logic_vector(2 downto 0) := "000";
signal bg_line_req   : std_logic := '0';
signal bg_line_y     : std_logic_vector(7 downto 0) := (others => '0');
signal bg_line_addr  : std_logic_vector(23 downto 0);
signal tbl_pages     : std_logic_vector(23 downto 0) := (others => '0');  -- pages of the tables of reversed bytes
signal sdram_ready   : std_logic;
signal lb_we         : std_logic;
signal lb_a          : std_logic_vector(7 downto 0);
signal lb_d          : std_logic_vector(15 downto 0);
signal softsw_command: std_logic_vector(15 downto 0);
signal osd_command   : std_logic_vector(15 downto 0);
signal osd_command_s1, osd_command_s2, osd_command_vga : std_logic_vector(15 downto 0) := (others => '0');
signal softsw_regs   : std_logic_vector(12*8-1 downto 0);
signal vga_rgb_core  : std_logic_vector(23 downto 0);
signal kb_nmi        : std_logic := '0';
signal kb_reset      : std_logic := '0';
signal kb_pause      : std_logic := '0';
signal kb_video_mode : std_logic := '0';
signal mcu_busy      : std_logic := '1';
signal mcu_n_reset   : std_logic;

-- Video
signal vga_addr      : std_logic_vector(12 downto 0);
signal vga_gfx_addr  : std_logic_vector(12 downto 0);
signal vga_data      : std_logic_vector(7 downto 0);
signal vga_gfx_data  : std_logic_vector(63 downto 0);
signal vga_wr        : std_logic;
signal vga_r         : std_logic_vector(7 downto 0);
signal vga_g         : std_logic_vector(7 downto 0);
signal vga_b         : std_logic_vector(7 downto 0);
signal sync_hcnt     : std_logic_vector(9 downto 0);
signal sync_vcnt     : std_logic_vector(9 downto 0);
signal sync_hsync    : std_logic;
signal sync_vsync    : std_logic;
signal sync_blank    : std_logic;
signal sync_int      : std_logic;

-- CLOCK
signal pll_clk       : std_logic_vector(5 downto 0);
signal pll_locked    : std_logic;
signal clk_tmds      : std_logic;
signal clk_sdram     : std_logic;
signal clk_sdram_out : std_logic;

-- System
signal selector      : std_logic_vector(2 downto 0);
signal inta_n        : std_logic;
signal int_sync      : std_logic_vector(2 downto 0) := "000";
signal int_cnt       : unsigned(4 downto 0) := (others => '0');

-- SDRAM
signal sdram_addr    : std_logic_vector(21 downto 0);
signal sdram_di      : std_logic_vector(71 downto 0);
signal sdram_do      : std_logic_vector(71 downto 0);
signal sdram_rd      : std_logic;
signal sdram_wr      : std_logic;
signal sdram_wr_mask : std_logic_vector(8 downto 0) := "000000000";
signal sdram_rdy     : std_logic := '0';

begin

-- PLL: 50 MHz -> 56.25 MHz (the CPU, SRAM, MCU link), the same at 180 degrees, 27 MHz (video, 576p50);
-- VCO 675 MHz, phase 0: the clocks are related (karabas-go-modules kg_pll: IBUFG, PLL_BASE, BUFG)
U1: entity work.kg_pll
generic map (
    DIVCLK_DIVIDE       => 2,
    CLKFBOUT_MULT       => 27,
    CLKOUT0_DIVIDE      => 12,    -- 56.25
    CLKOUT1_DIVIDE      => 12,    -- 56.25 @ 180
    CLKOUT1_PHASE       => 180.0,
    CLKOUT2_DIVIDE      => 25,    -- 27.00
    CLKOUT3_DIVIDE      => 27,    -- not used
    CLKOUT4_DIVIDE      => 27,
    CLKOUT5_DIVIDE      => 27,
    BUFG_MASK           => 7      -- 6'b000111: BUFGs on the three clocks
)
port map (
    clk_in              => CLK_50MHZ,
    rst                 => '0',
    clk_out             => pll_clk,
    locked              => pll_locked
);
clk_sdram     <= pll_clk(0);
clk_sdram_out <= pll_clk(1);
clk_vga       <= pll_clk(2);
areset        <= not pll_locked;

-- CPU: the main Z80 and the 8 graphical lanes of Spec256 (docs/SIMD.md)
U2: entity work.T80se_S256
generic map (
    LANES               => 8
)
port map (
    RESET_n             => cpu_reset_n,
    CLK_n               => clk_sdram,
    CLKEN               => cpu_clken,
    WAIT_n              => '1',
    INT_n               => cpu_int_n,
    NMI_n               => cpu_nmi_n,
    BUSRQ_n             => '1',
    M1_n                => cpu_m1_n,
    MREQ_n              => cpu_mreq_n,
    IORQ_n              => cpu_iorq_n,
    RD_n                => cpu_rd_n,
    WR_n                => cpu_wr_n,
    RFSH_n              => open,
    HALT_n              => open,
    BUSAK_n             => open,
    A                   => cpu_addr,
    DI                  => cpu_di,
    DO                  => cpu_do,
    DIR                 => regs(211 downto 0),
    DIRSet              => regs_wr,
    REG                 => open,
    MC_O                => open,
    TS_O                => open,
    IR_O                => open,
    PC_O                => open,
    INST                => cpu_inst,
    GDI                 => cpu_gfx_di,
    GDO                 => cpu_gfx_do,
    GREG                => open,
    GA                  => cpu_ga,
    GA_EN               => cpu_ga_en
);

-- Video
U3: entity work.vga_spec256
port map (
    I_CLK               => clk_vga,
    I_MODE              => kb_video_mode,
    I_DATA              => vga_data,
    I_GFX_DATA          => vga_gfx_data,
    I_BORDER            => port_xxfe_reg(2 downto 0),    -- Биты D0..D2 порта xxFE определяют цвет бордюра
    I_HCNT              => sync_hcnt,
    I_VCNT              => sync_vcnt,
    I_BLANK             => sync_blank,
    I_PAL_CLK           => clk_sdram,
    I_PAL_WR            => pal_wr,
    I_PAL_A             => pal_a,
    I_PAL_D             => pal_d,
    I_COLOUR_MODE       => kb_colour_mode,
    I_PAPER00INKFF      => s_paper00inkff,
    I_HIDE_SAME         => s_hide_same,
    I_UP_MIXED          => s_up_mixed,
    I_DOWN_MIXED        => s_down_mixed,
    I_BG_ON             => bg_on,
    I_BK_OVER_FF        => s_bk_over_ff,
    I_LB_CLK            => clk_sdram,
    I_LB_WE             => lb_we,
    I_LB_A              => lb_a,
    I_LB_D              => lb_d,
    O_BG_REQ            => vga_bg_req,
    O_BG_Y              => vga_bg_y,
    O_ADDR              => vga_addr,
    O_GFX_ADDR          => vga_gfx_addr,
    O_R                 => vga_r,
    O_G                 => vga_g,
    O_B                 => vga_b);
    
-- Sync
U4: entity work.sync
port map (
    I_CLK               => clk_vga,
    I_EN                => '1',
    O_HCNT              => sync_hcnt,
    O_VCNT              => sync_vcnt,
    O_INT               => sync_int,
    O_FLASH             => open,
    O_BLANK             => sync_blank,
    O_HSYNC             => sync_hsync,
    O_VSYNC             => sync_vsync);

-- ram     
-- SDRAM: the backgrounds of the game, written by the file loader, read a line ahead for the video
U15: entity work.sdram_bg
port map (
    clk                 => clk_sdram,
    reset               => areset,
    wr                  => bg_wr,
    wr_addr             => bg_wr_a,
    wr_data             => bg_wr_d,
    line_req            => bg_line_req,
    line_addr           => bg_line_addr,
    line_sel            => bg_line_y(0),
    lb_we               => lb_we,
    lb_addr             => lb_a,
    lb_data             => lb_d,
    ready               => sdram_ready,
    sdr_a               => DRAM_A,
    sdr_ba              => DRAM_BA,
    sdr_dq              => DRAM_DQ,
    sdr_dqm             => DRAM_DQM,
    sdr_ras_n           => DRAM_NRAS,
    sdr_cas_n           => DRAM_NCAS,
    sdr_we_n            => DRAM_NWE
);

bg_line_addr <= bg_cur & bg_line_y & x"00";

-- the line asked for by the video (a toggle on clk_vga, the line number stable with it): two flip-flops
-- on clk_bus, a request on the change; none while a file loads (the SDRAM is written then)
process (clk_sdram)
begin
    if rising_edge(clk_sdram) then
        bg_req_s <= bg_req_s(1 downto 0) & vga_bg_req;
        bg_line_req <= '0';
        if bg_req_s(2) /= bg_req_s(1) then
            bg_line_y <= vga_bg_y;
            bg_line_req <= bg_on and not fileloader_act;
        end if;
    end if;
end process;

-- the background shown: the first rule whose byte matches (watched on the writes of the CPU and of the
-- loader), else the one before
process (clk_sdram)
begin
    if rising_edge(clk_sdram) then
        for i in 0 to 15 loop
            if fileloader_act = '0' and cpu_mreq_n = '0' and cpu_wr_n = '0' and cpu_addr = rule_addr(i) then
                if cpu_do = rule_val(i) then rule_m(i) <= '1'; else rule_m(i) <= '0'; end if;
            end if;
        end loop;
        for i in 15 downto 0 loop
            if rule_m(i) = '1' and rule_bg(i) /= x"FF" then
                bg_cur <= rule_bg(i);
            end if;
        end loop;
        if fileloader_act = '1' then
            bg_cur <= bg_first;
            rule_m <= bg_mask;
        end if;
    end if;
end process;
     
-- #7FFD and the banks: #30 on a reset (ROM 1, banks 5, 2, 0, locked: a 48K game as on the 48K); while a
-- file loads, p7ffd_load: #30 for the RAM of 4000-FFFF (banks 5, 2, 0), then the value of a 128K snapshot,
-- kept when the CPU starts (the ROM planes and the banks of the 128K block are written with ld_bank)
U16: entity work.pager
port map (
    CLK                 => clk_sdram,
    SET                 => pg_set,
    SET_VAL             => pg_set_val,
    IORQ_N              => cpu_iorq_n,
    WR_N                => cpu_wr_n,
    M1_N                => cpu_m1_n,
    A                   => cpu_addr,
    D                   => cpu_do,
    BANK_A              => sdram_addr(15 downto 14),
    BANK                => pg_bank,
    P7FFD               => p7ffd
);
pg_set     <= reset or romloader_act or fileloader_act;
pg_set_val <= p7ffd_load when fileloader_act = '1' else "110000";

-- the ROM loader: the ROM 0 at 0, the ROM 1 at #4000 (core json)
sdram_bank <= "100" & romloader_a(14) when romloader_act = '1' else
              ld_bank when fileloader_act = '1' and ld_ov = '1' else
              pg_bank;

U5: entity work.sram
port map (
    clk                 => clk_sdram,
    reset               => areset,
    wr                  => sdram_wr,
	 wr_mask					=> sdram_wr_mask,
    rd                  => sdram_rd,
    lane_a              => lane_a,
    lane_en             => lane_en,
    lane_pages          => tbl_pages,
    a                   => sdram_addr(15 downto 0),
    bank                => sdram_bank,
    di                  => sdram_di,
    do                  => sdram_do,
    cpu_ena             => cpu_ena,
	 do_rdy					=> sdram_rdy,
    
    sram_a              => MA,
    sram_d              => MD,
    sram_rd_n           => MRD_N,
    sram_wr_n           => MWR_N
);

-- VRAM 8K x 8bit
U6: entity work.kg_sdpram
generic map (
    DW                  => 8,
    AW                  => 13
)
port map (
    clka                => clk_sdram,
    wea                 => vram_wr,
    addra               => vram_addr,
    dina                => vram_di,
    clkb                => clk_vga,
    enb                 => '1',
    addrb               => vga_addr,
    doutb               => vga_data
);

-- VRAM 8K x 64bit
U7: entity work.kg_sdpram
generic map (
    DW                  => 64,
    AW                  => 13
)
port map (
    clka                => clk_sdram,
    wea                 => vram_gfx_wr,
    addra               => vram_gfx_addr,
    dina                => vram_gfx_di,
    clkb                => clk_vga,
    enb                 => '1',
    addrb               => vga_gfx_addr,
    doutb               => vga_gfx_data
);

-- MCU link (karabas-go-modules kg_mcu): keyboard, joysticks, OSD, soft switches, the rom loader and the
-- file loader of the FL item (.256, the ioctl commands, a write for each byte, bursts)
U9: entity work.kg_mcu
generic map (
    BURST_MAX_MHZ       => BURST_MAX_MHZ,
    CS_FILTER           => 3,
    ENABLE_RTC          => 0,
    ENABLE_UART         => 0,
    ENABLE_MATRIX       => 1,
    ENABLE_DEBUG        => 0,
    ENABLE_IMG          => 0,
    ENABLE_FILE         => 1,
    FILE_CMDS           => 0,
    FILE_WR_EACH        => 1,
    FILE_TO_ROM         => 0,
    ENABLE_FT           => 0,
    ENABLE_SD2          => 0
)
port map (
    CLK                 => clk_sdram,
    N_RESET             => mcu_n_reset,

    MCU_MOSI            => MCU_MOSI,
    MCU_MISO            => MCU_MISO,
    MCU_SCK             => MCU_SCK,
    MCU_SS              => MCU_CS_N,
    MCU_SPI_FT_SS       => MCU_IO(3),
    MCU_SPI_SD2_SS      => MCU_IO(2),
    MCU_BURST_CS_N      => MCU_IO(0),
    MCU_BURST_READY     => MCU_BURST_READY,

    KB_STATUS           => hid_kb_status,
    KB_DAT0             => hid_kb_dat0,
    KB_DAT1             => hid_kb_dat1,
    KB_DAT2             => hid_kb_dat2,
    KB_DAT3             => hid_kb_dat3,
    KB_DAT4             => hid_kb_dat4,
    KB_DAT5             => hid_kb_dat5,

    JOY_L               => joy_l,
    JOY_R               => joy_r,

    RTC_A               => x"00",
    RTC_DI              => x"00",
    RTC_CS              => '0',
    RTC_WR_N            => '1',

    UART_TX_DATA        => x"00",
    UART_TX_WR          => '0',
    UART_TX_MODE        => '0',
    UART_DLM            => x"00",
    UART_DLL            => x"00",
    UART_DLM_WR         => '0',
    UART_DLL_WR         => '0',

    SOFTSW_COMMAND      => softsw_command,
    OSD_COMMAND         => osd_command,

    ROMLOADER_ACTIVE    => romloader_act,
    ROMLOAD_ADDR        => romloader_a,
    ROMLOAD_DATA        => romloader_do,
    ROMLOAD_WR          => romloader_wr,

    FILELOAD_ACTIVE     => fileloader_act,
    FILELOAD_ADDR       => fileloader_a,
    FILELOAD_DATA       => fileloader_do,
    FILELOAD_WR         => fileloader_wr,

    FT_MISO             => '1',
    SD2_MISO            => '1',

    MATRIX_CMD          => matrix_cmd,
    MATRIX_CMD_WR       => matrix_cmd_wr,
    DEBUG_ADDR          => x"0000",
    DEBUG_DATA          => x"0000",
    IMG_Q_WR            => '0',
    IMG_Q_DI            => x"000000",
    ESP_UART_RX_DATA    => x"00",
    ESP_UART_RX_WR      => '0',

    DVI_ONLY            => DVI_ONLY,
    BUSY                => mcu_busy
);
mcu_n_reset <= not areset;

-- USB HID parser / transformer to 8x5 matrix + joy mapper on keyboard
U10: entity work.hid_parser
port map (
    CLK                 => clk_bus,
    RESET               => areset,    

    -- hid keyboard input
    KB_STATUS           => hid_kb_status,
    KB_DAT0             => hid_kb_dat0,
    KB_DAT1             => hid_kb_dat1,
    KB_DAT2             => hid_kb_dat2,
    KB_DAT3             => hid_kb_dat3,
    KB_DAT4             => hid_kb_dat4,
    KB_DAT5             => hid_kb_dat5,    

    -- joy inputs
    JOY_TYPE_L          => kb_joy_type_l(2 downto 0),
    JOY_TYPE_R          => kb_joy_type_r(2 downto 0),
    JOY_L               => joy_l,
    JOY_R               => joy_r,
    
    -- cpu a
    A                   => cpu_addr(15 downto 8),    
    
    -- outputs
    JOY_DO              => joy_do,
    KB_DO               => kb_do
);

-- Soft switches of the OSD (karabas-go-modules kg_soft_switches): register n is the osd item n of the
-- core json (core.json, core_mini.json and core_minig.json have the same items)
U11: entity work.kg_soft_switches
generic map (
    N                   => 12
)
port map (
    clk                 => clk_sdram,
    command             => softsw_command,
    regs                => softsw_regs,
    upd                 => open
);
kb_joy_type_l <= softsw_regs(4*8+2 downto 4*8);    -- Joystick L
kb_joy_type_r <= softsw_regs(5*8+2 downto 5*8);    -- Joystick R
kb_video_mode <= softsw_regs(6*8);                 -- GFX 256
kb_colour_mode<= softsw_regs(7*8+1 downto 7*8);    -- Colour 0/FF: Auto, Attr, Palette, Pixel
kb_ay_mode    <= softsw_regs(8*8+1 downto 8*8);    -- AY mode: ABC, ACB, Mono
kb_pause      <= softsw_regs(9*8);                 -- Pause
kb_nmi        <= softsw_regs(10*8);                -- NMI
kb_reset      <= softsw_regs(11*8);                -- Reset

-- OSD (karabas-go-modules kg_osd_overlay) on the VGA clock. OSD_COMMAND comes from the clock of the mcu
-- link: taken when two samples in a row are the same, so a word caught while it changes is not a command.
process (clk_vga)
begin
    if rising_edge(clk_vga) then
        osd_command_s1 <= osd_command;
        osd_command_s2 <= osd_command_s1;
        if osd_command_s1 = osd_command_s2 then
            osd_command_vga <= osd_command_s2;
        end if;
    end if;
end process;

vga_rgb_core <= vga_r & vga_g & vga_b;

U12: entity work.kg_osd_overlay
generic map (
    H_OFFSET            => 78,    -- the window (512 x 416) in the middle of 720x576
    V_OFFSET            => 60
)
port map (
    clk                 => clk_vga,
    rgb_i               => vga_rgb_core,
    rgb_o               => VGA_RGB,
    hsync_i             => sync_hsync,
    vsync_i             => sync_vsync,
    osd_command         => osd_command_vga
);

-------------------------------------------------------------------------------
-- Формирование глобальных сигналов
-- INT: from the rising sync_int (VGA clock, through two flip-flops) for 32 T-states, as the ULA of the
-- 48K holds it, or until the CPU acknowledges it. It was a flip-flop clocked by sync_int and reset by
-- inta_n, held until the acknowledge: an INT in DI fired after the next EI, anywhere in the frame.
process (clk_sdram)
begin
    if rising_edge(clk_sdram) then
        int_sync <= int_sync(1 downto 0) & sync_int;
        if int_sync(2 downto 1) = "01" then
            cpu_int_n <= '0';
            int_cnt <= (others => '0');
        elsif inta_n = '0' or int_cnt = 31 then
            cpu_int_n <= '1';
        elsif cpu_ena = '1' and cpu_int_n = '0' then
            int_cnt <= int_cnt + 1;
        end if;
    end if;
end process;

-- no CPU clock in the clock after the snapshot registers are loaded (DIRSet): every register of the CPU
-- then changes at most every 2 clocks, the multicycle constraint TS_CPU of the ucf
process (clk_sdram)
begin
    if rising_edge(clk_sdram) then
        regs_wr_d <= regs_wr;
    end if;
end process;
cpu_clken      <= cpu_ena and not regs_wr_d;

reset          <= areset or kb_reset;                        -- горячий сброс
cpu_reset_n    <= not(reset) and not(mcu_busy) and not(romloader_act) and not(fileloader_act); -- CPU сброс
inta_n         <= cpu_iorq_n or cpu_m1_n;              -- inta_n
cpu_nmi_n      <= not kb_nmi;                          -- NMI

vram_wr         <= fileloader_wr8 when fileloader_act = '1' and fileloader_sna = '1' and fileloader_a8(15 downto 13) = "010" else
                        '1' when (cpu_mreq_n = '0' and cpu_wr_n = '0' and pg_bank = "0101" and cpu_addr(13) = '0') else 
                        '0';

vram_gfx_wr     <= fileloader_wr64 when fileloader_act = '1' and fileloader_gfx = '1' and fileloader_a64(15 downto 13) = "010" else
                        '1' when (cpu_mreq_n = '0' and cpu_wr_n = '0' and pg_bank = "0101" and cpu_addr(13) = '0') else 
                        '0';

vram_di         <= fileloader_do8 when fileloader_act = '1' else
                        cpu_do(7 downto 0);

vram_gfx_di     <= fileloader_do64 when fileloader_act = '1' else
                        cpu_gfx_do(63 downto 0);

vram_addr       <= fileloader_a8(12 downto 0) when fileloader_act = '1' and fileloader_sna = '1' else
                        cpu_addr(12 downto 0);

vram_gfx_addr   <= fileloader_a64(12 downto 0) when fileloader_act = '1' and fileloader_gfx = '1' else
                        cpu_addr(12 downto 0);

sdram_wr        <= romloader_wr when romloader_act = '1' else
                   fileloader_wr8 when fileloader_act = '1' and fileloader_sna = '1' else
                   fileloader_wr64 when fileloader_act = '1' and (fileloader_gfx = '1' or fileloader_rom = '1') else
                   '1' when (cpu_mreq_n = '0' and cpu_wr_n = '0' and cpu_addr(15 downto 14) /= "00") else 
                   '0';

sdram_wr_mask   <= "000000001" when romloader_act = '1' else
                   "000000001" when fileloader_act = '1' and fileloader_sna = '1' else
                   "111111110" when fileloader_act = '1' and (fileloader_gfx = '1' or fileloader_rom = '1') else
                   "111111111";

-- the lanes read at their own address through HL, DE, BC (T80_S256 GA): in the RAM only, a lane address in
-- the ROM stays at the address of the main CPU (the ROM has planes in the SRAM only with a .GFB)
g_lane_a: for p in 0 to 7 generate
    lane_a(p*16+15 downto p*16) <= cpu_ga(p*16+15 downto p*16) when cpu_ga(p*16+15 downto p*16+14) /= "00" else cpu_addr;
end generate;
lane_en         <= cpu_ga_en when cpu_addr(15 downto 14) /= "00" else '0';

sdram_rd        <= '0' when romloader_act='1' or fileloader_act='1' else
                   '1' when cpu_mreq_n = '0' and cpu_rd_n = '0' else 
                   '0';

sdram_di(7 downto 0) <= romloader_do when romloader_act = '1' else
                        fileloader_do8 when fileloader_act = '1' and fileloader_sna = '1' else
                        cpu_do;

sdram_di(71 downto 8) <= x"0000000000000000" when romloader_act = '1' else
                         fileloader_do64 when fileloader_act = '1' and (fileloader_gfx = '1' or fileloader_rom = '1') else
                         cpu_gfx_do;

sdram_addr        <= "000000" & romloader_a(15 downto 0) when romloader_act = '1' else
                     "000000" & fileloader_a8 when fileloader_act = '1' and fileloader_sna = '1' else
                     "000000" & fileloader_a64 when fileloader_act = '1' and (fileloader_gfx = '1' or fileloader_rom = '1') else
                     "000000" & cpu_addr;

-------------------------------------------------------------------------------
-- AY-3-8910 (ym2149 of MikeJ / Sorgelig, MODE 1: the AY volume table) on the ports of the 128K:
-- #FFFD (A15, A14, not A1) the register number, read the register; #BFFD (A15, not A14, not A1)
-- write the register. The clock: a strobe of 1.7734 MHz from a fractional counter, SEL 0 (no
-- division by 2).
process (clk_sdram)
begin
    if rising_edge(clk_sdram) then
        if ay_acc + AY_HZ >= CLK_BUS_HZ then
            ay_acc <= ay_acc + AY_HZ - CLK_BUS_HZ;
            ay_ce <= '1';
        else
            ay_acc <= ay_acc + AY_HZ;
            ay_ce <= '0';
        end if;
    end if;
end process;

-- reset with the CPU: a new game (the file loader) silences the AY of the old one
ay_reset <= reset or romloader_act or fileloader_act;

ay_bdir <= '1' when cpu_iorq_n = '0' and cpu_m1_n = '1' and cpu_wr_n = '0' and cpu_addr(15) = '1' and cpu_addr(1) = '0' else '0';
ay_bc   <= '1' when cpu_iorq_n = '0' and cpu_m1_n = '1' and cpu_addr(15 downto 14) = "11" and cpu_addr(1) = '0' else '0';

U13: entity work.ym2149
port map (
    CLK                 => clk_sdram,
    CE                  => ay_ce,
    RESET               => ay_reset,
    BDIR                => ay_bdir,
    BC                  => ay_bc,
    DI                  => cpu_do,
    DO                  => ay_do,
    CHANNEL_A           => ay_a,
    CHANNEL_B           => ay_b,
    CHANNEL_C           => ay_c,
    SEL                 => '0',
    MODE                => '1',
    ACTIVE              => open,
    IOA_in              => x"FF",
    IOA_out             => open,
    IOB_in              => x"FF",
    IOB_out             => open
);

-- Mixer: the AY (ABC: A and half of B left, C and half of B right; ACB: B and C swapped; mono:
-- A + B + C both, each 0..765), the beeper (EAR, bit 4 of #FE: 384) and the MIC bit (bit 3: 96);
-- 0..1245, shifted to 0..19920 of the signed 16 bits of the HDMI, the DAC and the level meters
process (clk_sdram)
    variable a, b, c, l, r : unsigned(10 downto 0);
    variable beep : unsigned(10 downto 0);
begin
    if rising_edge(clk_sdram) then
        a := "000" & unsigned(ay_a);
        b := "000" & unsigned(ay_b);
        c := "000" & unsigned(ay_c);
        case kb_ay_mode is
            when "00"   => l := a + a + b; r := c + c + b;   -- ABC
            when "01"   => l := a + a + c; r := b + b + c;   -- ACB
            when others => l := a + b + c; r := a + b + c;   -- mono
        end case;
        beep := (others => '0');
        if port_xxfe_reg(4) = '1' then beep := beep + 384; end if;
        if port_xxfe_reg(3) = '1' then beep := beep + 96; end if;
        mix_l <= l + beep;
        mix_r <= r + beep;
    end if;
end process;

audio_mix_l    <= '0' & std_logic_vector(mix_l) & "0000";
audio_mix_r    <= '0' & std_logic_vector(mix_r) & "0000";
AUDIO_L        <= audio_mix_l;
AUDIO_R        <= audio_mix_r;

-- the level meters of the mcu (karabas-go-modules audio_peaks): 2^20 clocks = 18.6 ms
U14: entity work.audio_peaks
generic map (
    PERIOD_BITS         => 20
)
port map (
    clk                 => clk_sdram,
    audio_l             => audio_mix_l,
    audio_r             => audio_mix_r,
    cmd_wr              => matrix_cmd_wr,
    cmd                 => matrix_cmd
);

BEEPER         <= port_xxfe_reg(4);

CLK_BUS        <= clk_sdram;
CLK_SDR_OUT    <= clk_sdram_out;

VGA_HS         <= sync_hsync;
VGA_VS         <= sync_vsync;
VGA_BLANK      <= sync_blank;

-------------------------------------------------------------------------------
-- File loader (load game data into 8 cpus, load regs from snapshot)
-- After the 442396 bytes the extension (docs/SIMD.md section 7, games/spec256.py): the header ("K256",
-- version, flags, UpColorsMixed, DownColorsMixed...), the palette, the rules of the backgrounds, the
-- ROM planes when flag 0 is set. A file without it keeps the defaults; the palette stays as it was.
process (clk_sdram)
    variable t : std_logic_vector(31 downto 0);   -- the offset in the extension
    variable u : std_logic_vector(31 downto 0);   -- the offset in the ROM planes
begin
    if rising_edge(clk_sdram) then
         fileloader_wr64 <= '0';
         fileloader_wr8 <= '0';
         pal_wr <= '0';
         bg_wr <= '0';
         
         prev_fileloader_act <= fileloader_act;
         if (fileloader_act = '1' and prev_fileloader_act = '0') then -- start of file loader
            regs_wr <= '0';
            fileloader_sna <= '1';
            fileloader_gfx <= '0';
            fileloader_rom <= '0';
				fileloader_a8 <= x"3FFF";
				fileloader_a64 <= x"3FFF"; -- base address to load snap
            ext_magic <= '0';
            rom_gfx <= '0';
            rom_gfx0 <= '0';
            x128 <= '0';
            x_hdr <= (others => '0');
            x_idx <= 0;
            x_pl <= '0';
            x_off <= (others => '0');
            p7ffd_load <= "110000";
            ld_ov <= '0';
            pal_byte <= 0;
            pal_next <= (others => '0');
            s_paper00inkff <= '1';
            s_hide_same <= '1';
            s_up_mixed <= x"40";
            s_down_mixed <= x"00";
            s_bk_over_ff <= '0';
            bg_on <= '0';
            bg_count <= (others => '0');
            bg_first <= (others => '0');
            bg_mask <= (others => '0');
            tbl_pages <= (others => '0');
            bg_wr_n <= (others => '0');
            bg_wr_off <= (others => '0');
            rule_bg <= (others => x"FF");
         end if;
         if (fileloader_act = '0' and prev_fileloader_act = '1') then -- end of file loader
            regs_wr <= '0';
            fileloader_sna <= '0';
            fileloader_gfx <= '0';
            fileloader_rom <= '0';
         end if;
         
        if fileloader_wr = '1' then
            t := fileloader_a - EXT_BASE;
            u := t - 848;

            -- snapshot for cpu
            if fileloader_a < 49152 then -- 49152 
               fileloader_sna <= '1';
               fileloader_gfx <= '0';
               fileloader_a8 <= fileloader_a8 + 1; -- 0x4000 offset
               fileloader_do8 <= fileloader_do;
               fileloader_wr8 <= '1';

            -- snapshot for gpu
            elsif fileloader_a < 442368 then -- 49152 + 49152*8
                fileloader_sna <= '0';
                fileloader_gfx <= '1';
                
					 if (fileloader_a(2 downto 0) = "000") then -- init buf
							fileloader_buf <= fileloader_do & x"00000000000000";
                elsif (fileloader_a(2 downto 0) = "111") then -- write buf
                    fileloader_do64 <= fileloader_do & fileloader_buf(63 downto 8);
						  fileloader_a64 <= fileloader_a64 + 1;
                    fileloader_wr64 <= '1';
					 else -- shift buf
						  fileloader_buf <= fileloader_do & fileloader_buf(63 downto 8);
                end if;

            -- registers dump
            elsif fileloader_a < EXT_BASE then
                fileloader_sna <= '0';
                fileloader_gfx <= '0';
                regs(223 downto 0) <= fileloader_do & regs(223 downto 8);
                if (fileloader_a = EXT_BASE-1) then -- write regs at the end
                    regs_wr <= '1';
                end if;

            -- the header: "K256", version 1, flags, UpColorsMixed, DownColorsMixed; taken at its end
            elsif t < 16 then
                case to_integer(unsigned(t(3 downto 0))) is
                    when 0 => if fileloader_do = x"4B" then ext_magic <= '1'; end if;   -- K
                    when 1 => if fileloader_do /= x"32" then ext_magic <= '0'; end if;  -- 2
                    when 2 => if fileloader_do /= x"35" then ext_magic <= '0'; end if;  -- 5
                    when 3 => if fileloader_do /= x"36" then ext_magic <= '0'; end if;  -- 6
                    when 4 => if fileloader_do /= x"01" and fileloader_do /= x"02" then ext_magic <= '0'; end if;  -- version
                    when 5 => ext_hdr(7 downto 0) <= fileloader_do;
                    when 6 => ext_hdr(15 downto 8) <= fileloader_do;
                    when 7 => ext_hdr(23 downto 16) <= fileloader_do;
                    when 8 => bg_count <= fileloader_do;
                    when 10 => bg_first <= fileloader_do;
                    when 11 => bg_mask(7 downto 0) <= fileloader_do;
                    when 12 => bg_mask(15 downto 8) <= fileloader_do;
                    when 13 => tbl_pages(7 downto 0) <= fileloader_do;
                    when 14 => tbl_pages(15 downto 8) <= fileloader_do;
                    when 15 =>
                        tbl_pages(23 downto 16) <= fileloader_do;
                        if ext_magic = '1' then
                            rom_gfx <= ext_hdr(0);
                            rom_gfx0 <= ext_hdr(0) and ext_hdr(4);
                            x128 <= ext_hdr(5);
                            s_paper00inkff <= ext_hdr(1);
                            s_hide_same <= ext_hdr(2);
                            s_up_mixed <= ext_hdr(15 downto 8);
                            s_down_mixed <= ext_hdr(23 downto 16);
                            s_bk_over_ff <= ext_hdr(3);
                            bg_on <= '0';
                            if bg_count /= x"00" then bg_on <= sdram_ready; end if;
                            if ext_hdr(0) = '1' and ext_hdr(4) = '1' then
                                bg_base <= std_logic_vector(to_unsigned(848 + 2 * 131072, 32));
                            elsif ext_hdr(0) = '1' then
                                bg_base <= std_logic_vector(to_unsigned(848 + 131072, 32));
                            else
                                bg_base <= std_logic_vector(to_unsigned(848, 32));
                            end if;
                        end if;
                    when others => null;
                end case;

            -- the palette: R, G, B of each colour
            elsif t < 784 then
                if ext_magic = '1' then
                    case pal_byte is
                        when 0 => pal_rg(15 downto 8) <= fileloader_do; pal_byte <= 1;
                        when 1 => pal_rg(7 downto 0) <= fileloader_do; pal_byte <= 2;
                        when 2 =>
                            pal_d <= pal_rg & fileloader_do;
                            pal_a <= pal_next;
                            pal_next <= pal_next + 1;
                            pal_wr <= '1';
                            pal_byte <= 0;
                    end case;
                end if;

            -- the rules of the backgrounds: background, address (low, high), value
            elsif t < 848 then
                if ext_magic = '1' then
                    case t(1 downto 0) is   -- 784 is a multiple of 4
                        when "00" => rule_bg(to_integer(unsigned(t(5 downto 2)) - 4) mod 16) <= fileloader_do;
                        when "01" => rule_addr(to_integer(unsigned(t(5 downto 2)) - 4) mod 16)(7 downto 0) <= fileloader_do;
                        when "10" => rule_addr(to_integer(unsigned(t(5 downto 2)) - 4) mod 16)(15 downto 8) <= fileloader_do;
                        when others => rule_val(to_integer(unsigned(t(5 downto 2)) - 4) mod 16) <= fileloader_do;
                    end case;
                end if;

            -- the backgrounds: 49152 bytes each, into the SDRAM at n * 65536 + y * 256 + x
            elsif t >= bg_base and ext_magic = '1' and bg_wr_n < bg_count then
                fileloader_rom <= '0';
                bg_wr <= '1';
                bg_wr_a <= bg_wr_n & bg_wr_off;
                bg_wr_d <= fileloader_do;
                if bg_wr_off = 49151 then
                    bg_wr_off <= (others => '0');
                    bg_wr_n <= bg_wr_n + 1;
                else
                    bg_wr_off <= bg_wr_off + 1;
                end if;

            -- the ROM planes: 8 bytes per address 0000-3FFF, as the planes of the RAM; the ROM 1 (.GFB, bank 9),
            -- then the ROM 0 (.GFA, bank 8) with flag 4
            elsif t >= 848 and (u < 131072 or (u < 262144 and rom_gfx0 = '1')) and rom_gfx = '1' then
                fileloader_gfx <= '0';
                fileloader_rom <= '1';
                ld_ov <= '1';
                ld_bank <= "100" & not u(17);
                if (u(2 downto 0) = "000") then
                    fileloader_buf <= fileloader_do & x"00000000000000";
                elsif (u(2 downto 0) = "111") then
                    fileloader_do64 <= fileloader_do & fileloader_buf(63 downto 8);
                    fileloader_a64 <= "00" & u(16 downto 3);
                    fileloader_wr64 <= '1';
                else
                    fileloader_buf <= fileloader_do & fileloader_buf(63 downto 8);
                end if;

            -- the 128K block, after the backgrounds: the header, then the RAM and the planes of each bank,
            -- written at C000-FFFF of the bank (not the screen of the VRAM)
            elsif t >= bg_base and ext_magic = '1' and x128 = '1' and x_idx < 5 then
                fileloader_rom <= '0';
                ld_ov <= '1';
                case x_idx is
                    when 0 => ld_bank <= "0001";
                    when 1 => ld_bank <= "0011";
                    when 2 => ld_bank <= "0100";
                    when 3 => ld_bank <= "0110";
                    when others => ld_bank <= "0111";
                end case;
                if x_hdr(3) = '0' then
                    if x_hdr(2 downto 0) = "000" then p7ffd_load <= fileloader_do(5 downto 0); end if;
                    x_hdr <= x_hdr + 1;
                elsif x_pl = '0' then
                    fileloader_sna <= '1';
                    fileloader_gfx <= '0';
                    fileloader_a8 <= "11" & x_off(13 downto 0);
                    fileloader_do8 <= fileloader_do;
                    fileloader_wr8 <= '1';
                    if x_off(13 downto 0) = "11111111111111" then
                        x_pl <= '1';
                        x_off <= (others => '0');
                    else
                        x_off <= x_off + 1;
                    end if;
                else
                    fileloader_sna <= '0';
                    fileloader_gfx <= '1';
                    if (x_off(2 downto 0) = "000") then
                        fileloader_buf <= fileloader_do & x"00000000000000";
                    elsif (x_off(2 downto 0) = "111") then
                        fileloader_do64 <= fileloader_do & fileloader_buf(63 downto 8);
                        fileloader_a64 <= "11" & x_off(16 downto 3);
                        fileloader_wr64 <= '1';
                    else
                        fileloader_buf <= fileloader_do & fileloader_buf(63 downto 8);
                    end if;
                    if x_off = "11111111111111111" then
                        x_pl <= '0';
                        x_off <= (others => '0');
                        x_idx <= x_idx + 1;
                    else
                        x_off <= x_off + 1;
                    end if;
                end if;

            else
                fileloader_rom <= '0';
            end if;
        end if;
    end if;
end process;


-------------------------------------------------------------------------------
-- Регистры
process (clk_sdram, cpu_addr, port_xxfe_reg, cpu_wr_n, cpu_do)
begin
    if clk_sdram'event and clk_sdram = '1' then
        if regs_wr = '1' then
            port_xxfe_reg <= regs(223 downto 216); -- border from snapshot (.256)
        elsif cpu_iorq_n = '0' and cpu_wr_n = '0' and cpu_addr(7 downto 0) = X"FE" then 
            port_xxfe_reg <= cpu_do(7 downto 0);
        end if;
    end if;
end process;

-------------------------------------------------------------------------------
-- Шина данных CPU
-- Линии (cpu_gfx_di, байт линии n в битах 8n+7..8n): из ROM - сам ROM, из RAM - своя плоскость,
-- поток команд (cpu_inst) - байт основной памяти при GFX_INST_FROM_MAIN, из порта - то же, что CPU.
rom_gfx_cur <= rom_gfx when p7ffd(4) = '1' else rom_gfx0;

process (selector, sdram_do, kb_do, joy_do, ay_do, cpu_inst, rom_gfx_cur)
    variable d : std_logic_vector(7 downto 0);
begin
    case selector is
        when "000" => d := sdram_do(7 downto 0);
        when "001" => d := sdram_do(7 downto 0);
        when "010" => d := "111" & kb_do;
        when "011" => d := joy_do;
        when "100" => d := ay_do;
        when "101" => d := x"00";
        when others => d := (others => '1');
    end case;
    cpu_di <= d;
    -- the ROM planes of the game where they are not all 0 (a .GFB colours a part of the ROM, the font;
    -- the rest of the file is 0: the ROM itself)
    if (selector = "001" or (selector = "000" and rom_gfx_cur = '1' and sdram_do(71 downto 8) /= x"0000000000000000")) and
       not (GFX_INST_FROM_MAIN and cpu_inst = '1') then
        cpu_gfx_di <= sdram_do(71 downto 8);
    else
        cpu_gfx_di <= d & d & d & d & d & d & d & d;
    end if;
end process;

selector <=
    "000" when cpu_mreq_n = '0' and cpu_rd_n = '0' and cpu_addr(15 downto 14) = "00" else   -- SDRAM ROM
    "001" when cpu_mreq_n = '0' and cpu_rd_n = '0' and cpu_addr(15 downto 14) /= "00"else   -- SDRAM RAM
    "010" when cpu_iorq_n = '0' and cpu_rd_n = '0' and cpu_addr(7 downto 0) = X"FE" else    -- Клавиатура, порт xxFE
    "011" when cpu_iorq_n = '0' and cpu_rd_n = '0' and cpu_addr(7 downto 0) = X"1F" else    -- Joystick, порт xx1F
    "100" when cpu_iorq_n = '0' and cpu_rd_n = '0' and cpu_m1_n = '1' and cpu_addr(15 downto 14) = "11" and cpu_addr(1) = '0' else -- AY, порт #FFFD
    -- порт #FF (плавающая шина): 0, а не #FF; Renegade ждёт на нём не-#FF и без этого тормозит
    "101" when cpu_iorq_n = '0' and cpu_rd_n = '0' and cpu_m1_n = '1' and cpu_addr(7 downto 0) = X"FF" else
    (others => '1');
    
end rtl;
