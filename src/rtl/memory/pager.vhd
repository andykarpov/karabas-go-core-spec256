-------------------------------------------------------------------------------
-- pager: the port #7FFD of the 128K and the bank of an address (docs/SIMD.md section 7)
-- The banks of the SRAM (sram.v): 0-7 the RAM banks of the 128K, 8 the ROM 0 (the 128 menu),
-- 9 the ROM 1 (the 48 BASIC). 0000-3FFF: the ROM of bit 4, 4000-7FFF: bank 5, 8000-BFFF: bank 2,
-- C000-FFFF: the bank of bits 2..0. Bit 5 locks the port until SET.
-- #7FFD is written on A15 = 0, A1 = 0 (the decoding of the 128K). SET loads SET_VAL: #30 on a reset
-- and while a file loads (ROM 1, banks 5, 2, 0, locked: a 48K game as on the 48K), the value of the
-- snapshot at the end of a 128K one. The shadow screen (bit 3) is kept but not shown.
-------------------------------------------------------------------------------
library IEEE;
use IEEE.std_logic_1164.all;

entity pager is
port (
    CLK         : in  std_logic;
    SET         : in  std_logic;
    SET_VAL     : in  std_logic_vector(5 downto 0);
    IORQ_N      : in  std_logic;
    WR_N        : in  std_logic;
    M1_N        : in  std_logic;
    A           : in  std_logic_vector(15 downto 0);
    D           : in  std_logic_vector(7 downto 0);
    BANK_A      : in  std_logic_vector(15 downto 14);  -- the address to map
    BANK        : out std_logic_vector(3 downto 0);
    P7FFD       : out std_logic_vector(5 downto 0)
);
end pager;

architecture rtl of pager is
signal p : std_logic_vector(5 downto 0) := "110000";
begin

process (CLK)
begin
    if rising_edge(CLK) then
        if SET = '1' then
            p <= SET_VAL;
        elsif IORQ_N = '0' and WR_N = '0' and M1_N = '1' and A(15) = '0' and A(1) = '0' and p(5) = '0' then
            p <= D(5 downto 0);
        end if;
    end if;
end process;

with BANK_A select BANK <=
    "100" & p(4)    when "00",
    "0101"          when "01",
    "0010"          when "10",
    '0' & p(2 downto 0) when others;

P7FFD <= p;

end rtl;
