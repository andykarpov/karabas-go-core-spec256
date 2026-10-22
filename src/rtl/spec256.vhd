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
    GFX_INST_FROM_MAIN : boolean := true
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
    MCU_IO      : in  std_logic_vector(3 downto 0);

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
signal cpu_int_n     : std_logic;
signal cpu_m1_n      : std_logic;
signal cpu_nmi_n     : std_logic;
signal cpu_ena       : std_logic;
signal cpu_do        : std_logic_vector(7 downto 0);
signal cpu_di        : std_logic_vector(7 downto 0);
signal cpu_gfx_do    : std_logic_vector(63 downto 0);
signal cpu_gfx_di    : std_logic_vector(63 downto 0);
signal cpu_inst      : std_logic;  -- the address is the instruction stream

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
signal softsw_command: std_logic_vector(15 downto 0);
signal osd_command   : std_logic_vector(15 downto 0);
signal kb_nmi        : std_logic := '0';
signal kb_reset      : std_logic := '0';
signal kb_pause      : std_logic := '0';
signal kb_video_mode : std_logic := '0';
signal mcu_busy      : std_logic := '1';

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
signal clk_tmds      : std_logic;
signal clk_sdram     : std_logic;
signal clk_sdram_out : std_logic;

-- System
signal selector      : std_logic_vector(2 downto 0);
signal inta_n        : std_logic;

-- SDRAM
signal sdram_addr    : std_logic_vector(21 downto 0);
signal sdram_di      : std_logic_vector(71 downto 0);
signal sdram_do      : std_logic_vector(71 downto 0);
signal sdram_rd      : std_logic;
signal sdram_wr      : std_logic;
signal sdram_wr_mask : std_logic_vector(8 downto 0) := "000000000";
signal sdram_rdy     : std_logic := '0';

begin

-- PLL
U1: entity work.clock
port map (
    clk                 => CLK_50MHZ,
    areset              => areset,
    clk_sdr             => clk_sdram,        -- 56.00 MHz
    clk_sdr_out         => clk_sdram_out,    -- 56.00 MHz @ 180
    clk_vga             => clk_vga           -- 25.20 MHz
);
    
-- CPU: the main Z80 and the 8 graphical lanes of Spec256 (docs/SIMD.md)
U2: entity work.T80se_S256
generic map (
    LANES               => 8
)
port map (
    RESET_n             => cpu_reset_n,
    CLK_n               => clk_sdram,
    CLKEN               => cpu_ena,
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
    GREG                => open
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
DRAM_NRAS <= '1';
DRAM_NCAS <= '1';
DRAM_NWE    <= '1';
DRAM_DQM <= "11";
DRAM_BA <= "11";
DRAM_A <= (others => '0');
DRAM_DQ <= (others => 'Z');
     
U5: entity work.sram
port map (
    clk                 => clk_sdram,
    reset               => areset,
    wr                  => sdram_wr,
	 wr_mask					=> sdram_wr_mask,
    rd                  => sdram_rd,
    a                   => sdram_addr(15 downto 0),
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
U6: entity work.dpram2
generic map (
    addr_width_g        => 13,
    data_width_g        => 8
)
port map (
    addr_a_i            => vram_addr,
    addr_b_i            => vga_addr,
    clk_a_i             => clk_sdram,
    clk_b_i             => clk_vga,
    data_a_i            => vram_di,
    we_i                => vram_wr,
    data_b_o            => vga_data
);

-- VRAM 8K x 64bit
U7: entity work.dpram2
generic map (
    addr_width_g        => 13,
    data_width_g        => 64
)
port map (
    addr_a_i            => vram_gfx_addr,
    addr_b_i            => vga_gfx_addr,
    clk_a_i             => clk_sdram,
    clk_b_i             => clk_vga,
    data_a_i            => vram_gfx_di,
    we_i                => vram_gfx_wr,
    data_b_o            => vga_gfx_data
);

-- MCU
U9: entity work.mcu
port map(
    CLK                 => clk_sdram,
    N_RESET             => not areset,
    
    MCU_MOSI            => MCU_MOSI,
    MCU_MISO            => MCU_MISO,
    MCU_SCK             => MCU_SCK,
    MCU_SS              => MCU_CS_N,
    
    KB_STATUS           => hid_kb_status,
    KB_DAT0             => hid_kb_dat0,
    KB_DAT1             => hid_kb_dat1,
    KB_DAT2             => hid_kb_dat2,
    KB_DAT3             => hid_kb_dat3,
    KB_DAT4             => hid_kb_dat4,
    KB_DAT5             => hid_kb_dat5,
    
    JOY_L               => joy_l,
    JOY_R               => joy_r,
    
    ROMLOAD_ACTIVE      => romloader_act,
    ROMLOAD_ADDR        => romloader_a,
    ROMLOAD_DATA        => romloader_do,
    ROMLOAD_WR          => romloader_wr,

    FILELOAD_ACTIVE     => fileloader_act,
    FILELOAD_ADDR       => fileloader_a,
    FILELOAD_DATA       => fileloader_do,
    FILELOAD_WR         => fileloader_wr,
    
    SOFTSW_COMMAND      => softsw_command,    
    OSD_COMMAND         => osd_command,

    DVI_ONLY            => DVI_ONLY,    
    BUSY                => mcu_busy
    
);

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

-- Soft switches parser from MCU
U11: entity work.soft_switches
port map (
    CLK                 => clk_sdram,    
    SOFTSW_COMMAND      => softsw_command,    
    JOY_TYPE_L          => kb_joy_type_l,
    JOY_TYPE_R          => kb_joy_type_r,
    MODE                => kb_video_mode,
    PAUSE               => kb_pause,
    NMI                 => kb_nmi,
    RESET               => kb_reset
);

-- osd overlay
U12: entity work.overlay
port map (
    CLK                 => clk_vga,
    RGB_I               => vga_r & vga_g & vga_b,
    RGB_O               => vga_rgb,
    HSYNC_I             => sync_hsync,
    VSYNC_I             => sync_vsync,    
    OSD_COMMAND         => osd_command
);

-------------------------------------------------------------------------------
-- Формирование глобальных сигналов
process (sync_int, inta_n)
begin
    if inta_n = '0' then
        cpu_int_n <= '1';
    elsif sync_int'event and sync_int = '1' then
        cpu_int_n <= '0';
    end if;
end process;

reset          <= areset or kb_reset;                        -- горячий сброс
cpu_reset_n    <= not(reset) and not(mcu_busy) and not(romloader_act) and not(fileloader_act); -- CPU сброс
inta_n         <= cpu_iorq_n or cpu_m1_n;              -- inta_n
cpu_nmi_n      <= not kb_nmi;                          -- NMI

vram_wr         <= fileloader_wr8 when fileloader_act = '1' and fileloader_sna = '1' and fileloader_a8(15 downto 13) = "010" else
                        '1' when (cpu_mreq_n = '0' and cpu_wr_n = '0' and cpu_addr(15 downto 13) = "010") else 
                        '0';

vram_gfx_wr     <= fileloader_wr64 when fileloader_act = '1' and fileloader_gfx = '1' and fileloader_a64(15 downto 13) = "010" else
                        '1' when (cpu_mreq_n = '0' and cpu_wr_n = '0' and cpu_addr(15 downto 13) = "010") else 
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
                   fileloader_wr64 when fileloader_act = '1' and fileloader_gfx = '1' else
                   '1' when (cpu_mreq_n = '0' and cpu_wr_n = '0' and cpu_addr(15 downto 14) /= "00") else 
                   '0';

sdram_wr_mask   <= "000000001" when romloader_act = '1' else
                   "000000001" when fileloader_act = '1' and fileloader_sna = '1' else
                   "111111110" when fileloader_act = '1' and fileloader_gfx = '1' else
                   "111111111";

sdram_rd        <= '0' when romloader_act='1' or fileloader_act='1' else
                   '1' when cpu_mreq_n = '0' and cpu_rd_n = '0' else 
                   '0';

sdram_di(7 downto 0) <= romloader_do when romloader_act = '1' else
                        fileloader_do8 when fileloader_act = '1' and fileloader_sna = '1' else
                        cpu_do;

sdram_di(71 downto 8) <= x"0000000000000000" when romloader_act = '1' else
                         fileloader_do64 when fileloader_act = '1' and fileloader_gfx = '1' else
                         cpu_gfx_do;

sdram_addr        <= "000000" & romloader_a(15 downto 0) when romloader_act = '1' else
                     "000000" & fileloader_a8 when fileloader_act = '1' and fileloader_sna = '1' else
                     "000000" & fileloader_a64 when fileloader_act = '1' and fileloader_gfx = '1' else
                     "000000" & cpu_addr;

AUDIO_L        <= "0000" & port_xxfe_reg(4) & "00000000000";
AUDIO_R        <= "0000" & port_xxfe_reg(4) & "00000000000";

BEEPER         <= port_xxfe_reg(4);

CLK_BUS        <= clk_sdram;
CLK_SDR_OUT    <= clk_sdram_out;

VGA_HS         <= sync_hsync;
VGA_VS         <= sync_vsync;
VGA_BLANK      <= sync_blank;

-------------------------------------------------------------------------------
-- File loader (load game data into 8 cpus, load regs from snapshot)
process (clk_sdram)
begin
    if rising_edge(clk_sdram) then
         fileloader_wr64 <= '0';
         fileloader_wr8 <= '0';
         
         prev_fileloader_act <= fileloader_act;
         if (fileloader_act = '1' and prev_fileloader_act = '0') then -- start of file loader
            regs_wr <= '0';
            fileloader_sna <= '1';
            fileloader_gfx <= '0';
				fileloader_a8 <= x"3FFF";
				fileloader_a64 <= x"3FFF"; -- base address to load snap
         end if;
         if (fileloader_act = '0' and prev_fileloader_act = '1') then -- end of file loader
            regs_wr <= '0';
            fileloader_sna <= '0';
            fileloader_gfx <= '0';
         end if;
         
        if fileloader_wr = '1' then

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
            else
                fileloader_sna <= '0';
                fileloader_gfx <= '0';
                regs(223 downto 0) <= fileloader_do & regs(223 downto 8);
                if (fileloader_a = 442396-1) then -- write regs at the end
                    regs_wr <= '1';
                end if;
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
process (selector, sdram_do, kb_do, joy_do, cpu_inst)
    variable d : std_logic_vector(7 downto 0);
begin
    case selector is
        when "000" => d := sdram_do(7 downto 0);
        when "001" => d := sdram_do(7 downto 0);
        when "010" => d := "111" & kb_do;
        when "011" => d := joy_do;
        when others => d := (others => '1');
    end case;
    cpu_di <= d;
    if selector = "001" and not (GFX_INST_FROM_MAIN and cpu_inst = '1') then
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
    (others => '1');
    
end rtl;
