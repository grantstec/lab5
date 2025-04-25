----------------------------------------------------------------------------------
--  ALU Test-bench
--  • Targets the 8-bit ALU of DDCA-RISC-V (Fig. 5-17)
--  • Exercises the four Table 5-1 operations (Add, Sub, And, Or)
--  • Verifies both the data result and the NZCV flag vector
----------------------------------------------------------------------------------

library ieee;
    use ieee.std_logic_1164.all;
    use ieee.numeric_std.all;

entity ALU_tb is
end ALU_tb;

architecture testbench of ALU_tb is

    --------------------------------------------------------------------------
    --  DUT declaration
    --------------------------------------------------------------------------
    component ALU
        port (
            i_A      : in  std_logic_vector(7 downto 0);
            i_B      : in  std_logic_vector(7 downto 0);
            i_op     : in  std_logic_vector(2 downto 0);
            o_result : out std_logic_vector(7 downto 0);
            o_flags  : out std_logic_vector(3 downto 0)   -- N  Z  C  V
        );
    end component;

    -- DUT I/O signals
    signal w_A, w_B, w_result : std_logic_vector(7 downto 0) := (others => '0');
    signal w_op     : std_logic_vector(2 downto 0) := (others => '0');
    signal w_flags  : std_logic_vector(3 downto 0) := (others => '0');

    -- Convenience op-codes (only the LSB two bits are required by Table 5-1,
    constant OP_ADD : std_logic_vector(2 downto 0) := "000";  -- 00
    constant OP_SUB : std_logic_vector(2 downto 0) := "001";  -- 01
    constant OP_AND : std_logic_vector(2 downto 0) := "010";  -- 10
    constant OP_OR  : std_logic_vector(2 downto 0) := "011";  -- 11

    -- Time between successive stimuli (no clock is needed for a pure-combinational ALU)
    constant k_step : time := 10 ns;

begin
    --------------------------------------------------------------------------
    --  DUT port-map
    --------------------------------------------------------------------------
    uut : ALU
        port map (
            i_A      => w_A,
            i_B      => w_B,
            i_op     => w_op,
            o_result => w_result,
            o_flags  => w_flags
        );

    --------------------------------------------------------------------------
    --  Test-plan process
    --------------------------------------------------------------------------
    stim_proc : process
        -- local helper to convert integers to 8-bit vectors quickly
        impure function to_vec(val : natural) return std_logic_vector is
        begin
            return std_logic_vector(to_unsigned(val, 8));
        end function;
    begin
        ----------------------------------------------------------------------------
        --  1. ADD - zero result (0 + 0)
        ----------------------------------------------------------------------------
        w_A  <= to_vec(0);
        w_B  <= to_vec(0);
        w_op <= OP_ADD;
        wait for k_step;

        assert w_result = to_vec(0)
            report "ADD 0+0: wrong result" severity error;
        assert w_flags  = "0100"             -- N=0 Z=1 C=0 V=0
            report "ADD 0+0: wrong NZCV" severity error;

        ----------------------------------------------------------------------------
        --  2. ADD - normal, no carry, no overflow  (5 + 3 = 8)
        ----------------------------------------------------------------------------
        w_A  <= to_vec(5);
        w_B  <= to_vec(3);
        w_op <= OP_ADD;
        wait for k_step;

        assert w_result = to_vec(8)
            report "ADD 5+3: wrong result" severity error;
        assert w_flags  = "0000"             -- N=0 Z=0 C=0 V=0
            report "ADD 5+3: wrong NZCV" severity error;

        ----------------------------------------------------------------------------
        --  3. ADD - generates carry out (240 + 17 = 257 -> 0x01, C=1)
        ----------------------------------------------------------------------------
        w_A  <= x"F0";           -- 240  (-16 signed)
        w_B  <= x"11";           -- 17
        w_op <= OP_ADD;
        wait for k_step;

        assert w_result = x"01"
            report "ADD carry: wrong result" severity error;
        assert w_flags  = "0010"             -- N=0 Z=0 C=1 V=0
            report "ADD carry: wrong NZCV" severity error;

        ----------------------------------------------------------------------------
        --  4. SUB - simple (10 - 3 = 7)
        ----------------------------------------------------------------------------
        w_A  <= to_vec(10);
        w_B  <= to_vec(3);
        w_op <= OP_SUB;
        wait for k_step;

        assert w_result = to_vec(7)
            report "SUB 10-3: wrong result" severity error;
        assert w_flags  = "0010"             -- N=0 Z=0 C=1 (no borrow) V=0
            report "SUB 10-3: wrong NZCV" severity error;

        ----------------------------------------------------------------------------
        --  5. SUB - negative result with no overflow (3 - 10 = -7)
        ----------------------------------------------------------------------------
        w_A  <= to_vec(3);
        w_B  <= to_vec(10);
        w_op <= OP_SUB;
        wait for k_step;

        assert w_result = x"F9"              -- 0xF9 = -7
            report "SUB 3-10: wrong result" severity error;
        assert w_flags  = "1000"             -- N=1 Z=0 C=0 V=0
            report "SUB 3-10: wrong NZCV" severity error;

        ----------------------------------------------------------------------------
        --  6. SUB - negative result with overflow (-100 - 30 = -130)
        ----------------------------------------------------------------------------
        w_A  <= to_vec(156);
        w_B  <= to_vec(30);
        w_op <= OP_SUB;
        wait for k_step;
 
        assert w_result = x"7E"              -- incorrectly = 126
            report "SUB 100-30: wrong result" severity error;
        assert w_flags  = "0011"             -- N=0 Z=0 C=1 V=1
            report "SUB 100-30: wrong NZCV" severity error;

        ----------------------------------------------------------------------------
        --  7. AND  (0x55 & 0x0F = 0x05)
        ----------------------------------------------------------------------------
        w_A  <= x"55";
        w_B  <= x"0F";
        w_op <= OP_AND;
        wait for k_step;

        assert w_result = x"05"
            report "AND: wrong result" severity error;
        assert w_flags  = "0000"             -- N=0 Z=0 C=0 V=0
            report "AND: wrong NZCV" severity error;

        ----------------------------------------------------------------------------
        --  8. OR   (0x80 | 0x01 = 0x81, negative set)
        ----------------------------------------------------------------------------
        w_A  <= x"80";
        w_B  <= x"01";
        w_op <= OP_OR;
        wait for k_step;

        assert w_result = x"81"
            report "OR: wrong result" severity error;
        assert w_flags  = "1000"             -- N=1 Z=0 C=0 V=0
            report "OR: wrong NZCV" severity error;

        ----------------------------------------------------------------------------
        --  All tests passed
        ----------------------------------------------------------------------------
        report "ALU test-bench completed successfully!" severity note;
        wait;   -- stop simulation
    end process;

end testbench;
