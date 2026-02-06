-------------------------------------------------------------------------------
-- GFX SIMD
-------------------------------------------------------------------------------

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.std_logic_arith.conv_integer;
use IEEE.numeric_std.all;
use IEEE.std_logic_unsigned.all;

entity gfx_cpu is
port(

    clk                 : in std_logic;
    ena                 : in std_logic;
    reset               : in std_logic;

    -- cpu
    addr                : in std_logic_vector(15 downto 0);
    rd_n                : in std_logic;
    wr_n                : in std_logic;
    m1_n                : in std_logic;
    mreq_n              : in std_logic;
    di                  : in std_logic_vector(7 downto 0);

	 -- additional signals from cpu
    regs                : in std_logic_vector(211 downto 0);
    ir                  : in std_logic_vector(7 downto 0);
    mc                  : in std_logic_vector(2 downto 0);
    ts                  : in std_logic_vector(2 downto 0);

    -- gfx data
    gfx_di              : in std_logic_vector(63 downto 0);
    gfx_do              : out std_logic_vector(63 downto 0);

	 -- ram ready
	 ram_rdy             : in std_logic;

    -- gfx busy
    busy                : out std_logic
);
end gfx_cpu;

architecture rtl of gfx_cpu is
	
    -- Векторные регистры (8 элементов по 8 бит)
    type reg_file_t is array (0 to 7) of std_logic_vector(7 downto 0);
    signal v_reg_a : reg_file_t := (others => (others => '0'));
	 
	 -- временный буфер хранения последних прочитанных данных (для LDI / LDIR итп)
	 signal tmp : std_logic_vector(63 downto 0);

	 -- FSM для захвата мультибайтных опкодов
	 type opcode_t is array(0 to 3) of std_logic_vector(7 downto 0);
	 signal opcode: opcode_t := (others => (others => '0'));
	 signal opcode_len : std_logic_vector(2 downto 0) := (others => '0');
	 signal last_opcode: opcode_t := (others => (others => '0'));
	 signal last_opcode_len : std_logic_vector(2 downto 0) := (others => '0');
	 signal opcode_valid : std_logic;
	 type opmachine IS(OP_IDLE, OP_B1, OP_B2, OP_B3, OP_B4, OP_DONE);
	 signal opcode_state : opmachine := OP_IDLE;
	 signal opcode_cycle : std_logic := '0';
	 
    -- Опкоды стандартных команд Z80
    constant OP_ADD_A_HL : std_logic_vector(7 downto 0) := x"86"; -- ADD A, (HL)
    constant OP_ADC_A_HL : std_logic_vector(7 downto 0) := x"8E"; -- ADC A, (HL)
    constant OP_SUB_A_HL : std_logic_vector(7 downto 0) := x"96"; -- SUB A, (HL)
    constant OP_SBC_A_HL : std_logic_vector(7 downto 0) := x"9E"; -- SBC A, (HL)

    constant OP_AND_A_HL : std_logic_vector(7 downto 0) := x"A6"; -- OR  A, (HL)
    constant OP_OR_A_HL  : std_logic_vector(7 downto 0) := x"B6"; -- OR  A, (HL)
    constant OP_XOR_A_HL : std_logic_vector(7 downto 0) := x"AE"; -- XOR A, (HL)

    constant OP_LD_A_HL  : std_logic_vector(7 downto 0) := x"7E"; -- LD  A, (HL)   - 7E
    constant OP_LD_A_BC  : std_logic_vector(7 downto 0) := x"0A"; -- LD  A, (BC)   - 0A
    constant OP_LD_A_DE  : std_logic_vector(7 downto 0) := x"1A"; -- LD  A, (DE)   - 1A
    constant OP_LD_A_NN  : std_logic_vector(7 downto 0) := x"3A"; -- LD  A, (nn)   - 3A nn
    constant OP_LD_A_IX  : std_logic_vector(15 downto 0) := x"7EDD"; -- LD  A, (IX+n) - DD 7E nn
    constant OP_LD_A_IY  : std_logic_vector(15 downto 0) := x"7EFD"; -- LD  A, (IY+n) - FD 7E nn
    constant OP_POP_AF   : std_logic_vector(7 downto 0) := x"F1"; -- POP AF	     - F1
	 
    constant OP_LD_HL_A  : std_logic_vector(7 downto 0) := x"77"; -- LD  (HL), A   - 77
	 constant OP_LD_BC_A  : std_logic_vector(7 downto 0) := x"02"; -- LD  (BC), A   - 02
	 constant OP_LD_DE_A  : std_logic_vector(7 downto 0) := x"12"; -- LD  (DE), A   - 12
	 constant OP_LD_NN_A  : std_logic_vector(7 downto 0) := x"32"; -- LD  (nn), A   - 32 nn
	 constant OP_LD_IX_A  : std_logic_vector(15 downto 0) := x"77DD"; -- LD  (IX+d), A - DD 77 nn
	 constant OP_LD_IY_A  : std_logic_vector(15 downto 0) := x"77FD"; -- LD  (IY+d), A - FD 77 nn
    constant OP_PUSH_AF  : std_logic_vector(7 downto 0) := x"F5"; -- PUSH AF	     - F5
	 
	 constant OP_LDI      : std_logic_vector(15 downto 0) := x"A0ED"; -- LDI  - ED A0
	 constant OP_LDD      : std_logic_vector(15 downto 0) := x"A8ED"; -- LDD  - ED A8
	 constant OP_LDIR     : std_logic_vector(15 downto 0) := x"B0ED"; -- LDIR - ED B0
	 constant OP_LDDR     : std_logic_vector(15 downto 0) := x"B8ED"; -- LDDR - ED B8
	 
	 constant OP_RLCA		 : std_logic_vector(15 downto 0) := x"07CB"; -- RLCA - CB 07
	 constant OP_RRCA		 : std_logic_vector(15 downto 0) := x"0FCB"; -- RRCA - CB 0F
	 constant OP_RLA		 : std_logic_vector(15 downto 0) := x"17CB"; -- RLA  - CB 17
	 constant OP_RRA		 : std_logic_vector(15 downto 0) := x"1FCB"; -- RRA  - CB 1F
	 

begin 

opcode_cycle <= '1' when m1_n = '0' and rd_n = '0' and mreq_n = '0' else '0';

-- fetch opcode
process(clk, reset)
begin
	if reset = '1' then
		opcode_state <= OP_IDLE;
		opcode_len <= "000";
		opcode_valid <= '0';
	elsif rising_edge(clk) and ena = '1' then

			opcode_valid <= '0';
			
			case opcode_state is
				when OP_IDLE =>
				
					if opcode_cycle = '1' and ram_rdy = '1' then -- первый байт опкода
						opcode(0) <= di;
						opcode_len <= "001";
						if di = x"CB" or di = x"ED" or di = x"DD" or di = x"FD" then
							opcode_state <= OP_B2;
						else
							opcode_state <= OP_IDLE;
							opcode_valid <= '1';
							last_opcode(0) <= di;
							last_opcode_len <= "001";
						end if;
					end if;
					
				when OP_B2 => 
					if rd_n = '0' and mreq_n = '0' and ram_rdy = '1' then
						opcode(1) <= di;
						opcode_len <= "010";
						if (opcode(0) = x"DD" or opcode(0) = x"FD") and di = x"CB" then
							opcode_state <= OP_B3;
						else
							opcode_state <= OP_IDLE;
							opcode_valid <= '1';
							last_opcode(0) <= opcode(0);
							last_opcode(1) <= di;
							last_opcode_len <= "010";							
						end if;
					end if;
					
				when OP_B3 =>
					if rd_n = '0' and mreq_n = '0' and ram_rdy = '1' then
						opcode(2) <= di;
						opcode_len <= "011";
						opcode_state <= OP_B4;
					end if;
					
				when OP_B4 => 
					if rd_n = '0' and mreq_n = '0' and ram_rdy = '1' then
						opcode(3) <= di;
						opcode_len <= "100";
						opcode_state <= OP_IDLE;
						opcode_valid <= '1';
						last_opcode(0) <= opcode(0);
						last_opcode(1) <= opcode(1);
						last_opcode(2) <= opcode(2);
						last_opcode(3) <= di;
						last_opcode_len <= "100";						
					end if;
					
				when OP_DONE =>
					opcode_valid <= '1';
					opcode_state <= OP_IDLE;
					last_opcode <= opcode;
					last_opcode_len <= opcode_len;
					
				when others =>
					opcode_state <= OP_IDLE;
			end case;
			
	end if;
end process;


process(clk)
begin
	if rising_edge(clk) and ena = '1' then 
		if m1_n = '1' and mreq_n = '0' then
			
			-- mem read
			if rd_n = '0' and ram_rdy = '1' then
				if last_opcode_len = 1 then
					case last_opcode(0) is
						-- LD A, (HL) ; LD A, (BC) ; LD A, (DE); POP AF
						when OP_LD_A_HL | OP_LD_A_BC | OP_LD_A_DE | OP_POP_AF =>
							for i in 0 to 7 loop
								v_reg_a(i) <= gfx_di((i*8)+7 downto i*8);
							end loop;
						-- ADD A, (HL)
						when OP_ADD_A_HL => 
							for i in 0 to 7 loop
								v_reg_a(i) <= std_logic_vector(unsigned(v_reg_a(i)) + 
													unsigned(gfx_di((i*8)+7 downto i*8)));
								end loop;
						-- SUB A, (HL)
						when OP_SUB_A_HL => 
							for i in 0 to 7 loop
								v_reg_a(i) <= std_logic_vector(unsigned(v_reg_a(i)) - 
													unsigned(gfx_di((i*8)+7 downto i*8)));												
							end loop;
						-- OR A, (HL)
						when OP_OR_A_HL =>
							for i in 0 to 7 loop
							  v_reg_a(i) <= v_reg_a(i) or gfx_di((i*8)+7 downto i*8);
							end loop;
						-- AND A, (HL)
						when OP_AND_A_HL =>
							for i in 0 to 7 loop
							  v_reg_a(i) <= v_reg_a(i) and gfx_di((i*8)+7 downto i*8);
							end loop;
						-- XOR A, (HL)
						when OP_XOR_A_HL =>
							for i in 0 to 7 loop
							  v_reg_a(i) <= v_reg_a(i) xor gfx_di((i*8)+7 downto i*8);
							end loop;
						when others => null;
					end case;
				end if;
				
				if last_opcode_len >= 2 then
					-- LD A, (nn)
					if last_opcode(0) = OP_LD_A_NN then
						for i in 0 to 7 loop
							v_reg_a(i) <= gfx_di((i*8)+7 downto i*8);
						end loop;
					else
						case last_opcode(1) & last_opcode(0) is
							-- LD A, (IX+n) ; LD A, (IY+n)
							when OP_LD_A_IX | OP_LD_A_IY =>
								for i in 0 to 7 loop
									v_reg_a(i) <= gfx_di((i*8)+7 downto i*8);
								end loop;
							-- LDI ; LDIR ; LDD ; LDDR
							when OP_LDI | OP_LDIR | OP_LDD | OP_LDDR =>
								tmp <= gfx_di;
							-- RLCA
							when OP_RLCA => 
								for i in 0 to 7 loop
									v_reg_a(i) <= gfx_di(i*8) & gfx_di((i*8)+7 downto (i*8)+1);
								end loop;
							-- RRCA
							when OP_RRCA => 
								for i in 0 to 7 loop
									v_reg_a(i) <= gfx_di((i*8)+6 downto (i*8)) & gfx_di((i*8)+7);
								end loop;
							when others => null;
						end case;
					end if;
				end if;
				
			end if;
			
			-- mem write 
			if wr_n = '0' then
				
				-- LD (HL), A ; LD (DE), A ; LD (BC), A; PUSH AF
				if last_opcode_len = 1 then
					if(last_opcode(0) = OP_LD_HL_A or last_opcode(0) = OP_LD_DE_A or 
						last_opcode(0) = OP_LD_BC_A or last_opcode(0) = OP_PUSH_AF) then
				
						for i in 0 to 7 loop
							gfx_do((i*8)+7 downto i*8) <= v_reg_a(i);
						end loop;
					end if;
				end if;
				
				-- LDI ; LDIR ; LDD ; LDDR ; LD (IX+n), A ; LD (IY+n), A
				if last_opcode_len >= 2 then
					if (last_opcode(1) & last_opcode(0) = OP_LDI) or 
						(last_opcode(1) & last_opcode(0) = OP_LDIR) or 
						(last_opcode(1) & last_opcode(0) = OP_LDD) or 
						(last_opcode(1) & last_opcode(0) = OP_LDDR)
					then
						gfx_do <= tmp;
					elsif (last_opcode(1) & last_opcode(0) = OP_LD_IX_A) or
							(last_opcode(1) & last_opcode(0) = OP_LD_IY_A) then
							for i in 0 to 7 loop
								gfx_do((i*8)+7 downto i*8) <= v_reg_a(i);
						end loop;
					end if;
				end if;
				
			end if;
			
		end if;
	end if;
end process;

end rtl;
