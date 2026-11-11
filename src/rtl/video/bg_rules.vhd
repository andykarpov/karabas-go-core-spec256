-------------------------------------------------------------------------------
-- The background shown (docs/SIMD.md section 7, games/spec256.py: the block of the rules)
-------------------------------------------------------------------------------
-- 16 conditions of a byte: the byte at an address, masked, = a value (or <); the bit of a condition
-- follows the writes of the CPU (I_WR), the loader gives the bits that hold in the snapshot. 16 rules:
-- a background and the conditions it needs; the first rule whose conditions all hold, else the default.
-- A background is n, 0xFE none, 0xFD (a rule) or 0xFF (the default) the one there is; a rule of
-- 0xFF is no rule.
--
-- The settings are written as the block of the rules of the .256 (I_CFG_A = its offset):
--   0 flags (O_FLAGS), 1 default, 2-3 the conditions that hold at the start, 4 + 4n: condition n
--   (address low, high, mask, value), 68-69 the conditions that compare with <, 72 + 4n: rule n
--   (background, conditions low, high, reserved), 153 the background at the start.
-- I_INIT (one clock, before the writes) sets what a file without the block has: condition n with
-- mask 0xFF, rule n needs condition n (the "NN: addr=VVh" rules of a .CFG, written by the loader as
-- a background, an address and a value), no rules, the default 0xFF, the background 0 at the start.
-- While I_LOAD is 1 the background is the one at the start and the bits those of the snapshot.

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

entity bg_rules is
port (
	I_CLK		: in std_logic;
	I_INIT		: in std_logic;
	I_LOAD		: in std_logic;
	I_CFG_WE	: in std_logic;
	I_CFG_A		: in std_logic_vector(7 downto 0);
	I_CFG_D		: in std_logic_vector(7 downto 0);
	I_WR		: in std_logic;		-- a write of the CPU to memory
	I_WR_A		: in std_logic_vector(15 downto 0);
	I_WR_D		: in std_logic_vector(7 downto 0);
	O_FLAGS		: out std_logic_vector(7 downto 0);
	O_BG		: out std_logic_vector(7 downto 0);	-- the background
	O_NONE		: out std_logic			-- no background
);
end entity;

architecture rtl of bg_rules is

	type byte16_t is array (0 to 15) of std_logic_vector(7 downto 0);
	type word16_t is array (0 to 15) of std_logic_vector(15 downto 0);

	signal flags		: std_logic_vector(7 downto 0) := (others => '0');
	signal dflt		: std_logic_vector(7 downto 0) := x"FF";
	signal start		: std_logic_vector(7 downto 0) := x"00";
	signal holds0		: std_logic_vector(15 downto 0) := (others => '0');
	signal c_addr		: word16_t := (others => (others => '0'));
	signal c_mask		: byte16_t := (others => x"FF");
	signal c_val		: byte16_t := (others => (others => '0'));
	signal c_lt		: std_logic_vector(15 downto 0) := (others => '0');
	signal r_bg		: byte16_t := (others => x"FF");
	signal r_need		: word16_t := (others => (others => '0'));
	signal holds		: std_logic_vector(15 downto 0) := (others => '0');
	signal bg		: std_logic_vector(7 downto 0) := x"00";
	signal none		: std_logic := '0';
	signal sel		: std_logic_vector(7 downto 0);

begin

-- the settings
process (I_CLK)
	variable n : integer range 0 to 15;
begin
	if rising_edge(I_CLK) then
		if I_INIT = '1' then
			flags <= (others => '0');
			dflt <= x"FF";
			start <= x"00";
			holds0 <= (others => '0');
			c_lt <= (others => '0');
			for i in 0 to 15 loop
				c_addr(i) <= (others => '0');
				c_mask(i) <= x"FF";
				c_val(i) <= (others => '0');
				r_bg(i) <= x"FF";
				r_need(i) <= (others => '0');
				r_need(i)(i) <= '1';
			end loop;
		elsif I_CFG_WE = '1' then
			-- the index of a condition or a rule from the offset (4 bits wrap: 64-67 is condition 15)
			case to_integer(unsigned(I_CFG_A)) is
				when 0 => flags <= I_CFG_D;
				when 1 => dflt <= I_CFG_D;
				when 2 => holds0(7 downto 0) <= I_CFG_D;
				when 3 => holds0(15 downto 8) <= I_CFG_D;
				when 4 to 67 =>
					n := to_integer(unsigned(I_CFG_A(5 downto 2)) - 1);
					case I_CFG_A(1 downto 0) is
						when "00" => c_addr(n)(7 downto 0) <= I_CFG_D;
						when "01" => c_addr(n)(15 downto 8) <= I_CFG_D;
						when "10" => c_mask(n) <= I_CFG_D;
						when others => c_val(n) <= I_CFG_D;
					end case;
				when 68 => c_lt(7 downto 0) <= I_CFG_D;
				when 69 => c_lt(15 downto 8) <= I_CFG_D;
				when 72 to 135 =>
					n := to_integer(unsigned(I_CFG_A(5 downto 2)) - 2);
					case I_CFG_A(1 downto 0) is
						when "00" => r_bg(n) <= I_CFG_D;
						when "01" => r_need(n)(7 downto 0) <= I_CFG_D;
						when "10" => r_need(n)(15 downto 8) <= I_CFG_D;
						when others => null;
					end case;
				when 153 => start <= I_CFG_D;
				when others => null;
			end case;
		end if;
	end if;
end process;

-- the first rule whose conditions all hold, else the default
process (dflt, r_bg, r_need, holds)
	variable s : std_logic_vector(7 downto 0);
begin
	s := dflt;
	for i in 15 downto 0 loop
		if r_bg(i) /= x"FF" and (holds or not r_need(i)) = x"FFFF" then
			s := r_bg(i);
		end if;
	end loop;
	sel <= s;
end process;

process (I_CLK)
	variable b : unsigned(7 downto 0);
begin
	if rising_edge(I_CLK) then
		if I_LOAD = '1' then
			holds <= holds0;
			if start = x"FE" or start = x"FF" then
				none <= '1';
			else
				bg <= start;
				none <= '0';
			end if;
		else
			if I_WR = '1' then
				for i in 0 to 15 loop
					if I_WR_A = c_addr(i) then
						b := unsigned(I_WR_D and c_mask(i));
						if (c_lt(i) = '0' and b = unsigned(c_val(i))) or (c_lt(i) = '1' and b < unsigned(c_val(i))) then
							holds(i) <= '1';
						else
							holds(i) <= '0';
						end if;
					end if;
				end loop;
			end if;
			if sel = x"FE" then
				none <= '1';
			elsif sel /= x"FF" and sel /= x"FD" then
				bg <= sel;
				none <= '0';
			end if;
		end if;
	end if;
end process;

O_FLAGS <= flags;
O_BG <= bg;
O_NONE <= none;

end architecture;
