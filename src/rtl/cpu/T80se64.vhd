library IEEE; 
use IEEE.std_logic_1164.all; 
use IEEE.std_logic_unsigned.all;
use IEEE.numeric_std.all; 

entity T80se64 is
port (
    RESET_n : in std_logic;
    CLK_n : in std_logic;
    ENA : in std_logic;
    INT_n : in std_logic;
    NMI_n : in std_logic;
    M1_n : out std_logic;
    MREQ_n : out std_logic;
    IORQ_n : out std_logic;
    RD_n : out std_logic;
    WR_n : out std_logic;
    A : out std_logic_vector(15 downto 0);
    DI : in std_logic_vector(63 downto 0);
    DO : out std_logic_vector(63 downto 0);
    REGS : in std_logic_vector(211 downto 0) := (others => '0'); -- IFF2, IFF1, IM, IY, HL', DE', BC', IX, HL, DE, BC, PC, SP, R, I, F', A', F, A
    REGS_WR : in std_logic := '0'
);
end T80se64;

architecture rtl of T80se64 is

begin

    CPU_0: entity work.t80se
        generic map (Mode => 0, T2Write => 0, IOWait => 1)
        port map (
            RESET_n       => RESET_n,
            CLK_n         => CLK_n,
            CLKEN         => ENA,
            WAIT_n        => '1',
            INT_n         => INT_n,
            NMI_n         => NMI_n,
            BUSRQ_n       => '1',
            M1_n          => M1_n,
            MREQ_n        => MREQ_n,
            IORQ_n        => IORQ_n,
            RD_n          => RD_n,
            WR_n          => WR_n,
            RFSH_n        => open,
            HALT_n        => open,
            BUSAK_n       => open,
            A             => A,
            DI            => DI(7 downto 0),
            DO            => DO(7 downto 0),
            DIRset        => REGS_WR,
            DIR           => REGS
        );

  g_CPU: for ii in 1 to 7 generate
        CPU: entity work.t80se
        generic map (Mode => 0, T2Write => 0, IOWait => 1)
        port map (
            RESET_n       => RESET_n,
            CLK_n         => CLK_n,
            CLKEN         => ENA,
            WAIT_n        => '1',
            INT_n         => INT_n,
            NMI_n         => NMI_n,
            BUSRQ_n       => '1',
            M1_n          => open,
            MREQ_n        => open,
            IORQ_n        => open,
            RD_n          => open,
            WR_n          => open,
            RFSH_n        => open,
            HALT_n        => open,
            BUSAK_n       => open,
            A             => open,
            DI            => DI((ii+1)*8-1 downto ii*8),
            DO            => DO((ii+1)*8-1 downto ii*8),
            DIRset        => REGS_WR,
            DIR           => REGS
        );
  end generate g_CPU;

end rtl;
