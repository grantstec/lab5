library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

entity ALU is
    Port ( i_A : in STD_LOGIC_VECTOR (7 downto 0);
           i_B : in STD_LOGIC_VECTOR (7 downto 0);
           i_op : in STD_LOGIC_VECTOR (2 downto 0);
           o_result : out STD_LOGIC_VECTOR (7 downto 0);
           o_flags : out STD_LOGIC_VECTOR (3 downto 0)); -- NZCV
end ALU;

architecture Behavioral of ALU is
    -- ALU operation constants
    constant OP_ADD : std_logic_vector(2 downto 0) := "000";
    constant OP_SUB : std_logic_vector(2 downto 0) := "001";
    constant OP_AND : std_logic_vector(2 downto 0) := "010";
    constant OP_OR  : std_logic_vector(2 downto 0) := "011";
    
    -- Component declaration for ripple adder
    component ripple_adder is
        Port ( A : in STD_LOGIC_VECTOR (3 downto 0);
               B : in STD_LOGIC_VECTOR (3 downto 0);
               Cin : in STD_LOGIC;
               S : out STD_LOGIC_VECTOR (3 downto 0);
               Cout : out STD_LOGIC);
    end component;
    
    -- Internal signals
    signal w_B : STD_LOGIC_VECTOR (7 downto 0);
    signal w_Cin : STD_LOGIC;
    signal w_Cout_low : STD_LOGIC;
    signal w_Cout_high : STD_LOGIC;
    signal w_Sum : STD_LOGIC_VECTOR (7 downto 0);
    signal w_And : STD_LOGIC_VECTOR (7 downto 0);
    signal w_Or : STD_LOGIC_VECTOR (7 downto 0);
    signal result_out : STD_LOGIC_VECTOR (7 downto 0);
    
    -- Flag signals
    signal N_flag : std_logic;  -- Negative
    signal Z_flag : std_logic;  -- Zero
    signal C_flag : std_logic;  -- Carry
    signal V_flag : std_logic;  -- Overflow
    
begin
    -- For subtraction, invert B and set carry in to 1 (A - B = A + ~B + 1)
    w_B <= not i_B when i_op = OP_SUB else i_B;
    w_Cin <= '1' when i_op = OP_SUB else '0';
    
    -- Lower 4-bit ripple adder
    lower_adder: ripple_adder
    port map (
        A => i_A(3 downto 0),
        B => w_B(3 downto 0),
        Cin => w_Cin,
        S => w_Sum(3 downto 0),
        Cout => w_Cout_low
    );
    
    -- Upper 4-bit ripple adder
    upper_adder: ripple_adder
    port map (
        A => i_A(7 downto 4),
        B => w_B(7 downto 4),
        Cin => w_Cout_low,
        S => w_Sum(7 downto 4),
        Cout => w_Cout_high
    );
    
    -- Logical operations
    w_And <= i_A and i_B;
    w_Or <= i_A or i_B;
    
    -- Result MUX
    with i_op select
    result_out <= w_Sum when OP_ADD | OP_SUB,
                 w_And when OP_AND,
                 w_Or when OP_OR,
                 w_Sum when others;
    
    -- Set the negative flag based on the MSB of the result
    N_flag <= result_out(7);
    
    -- Set the zero flag if result is all zeros
    Z_flag <= '1' when result_out = "00000000" else '0';
    
    -- Carry flag
    -- For subtraction: C = NOT borrow
    -- In the case of A - B:
    -- - If A >= B, there's no borrow needed, so C = 1
    -- - If A < B, a borrow is needed, so C = 0
    process(i_op, w_Cout_high, i_A, i_B)
    begin
        if i_op = OP_ADD then
            C_flag <= w_Cout_high;  -- Normal carry for addition
        elsif i_op = OP_SUB then
            -- For subtraction, C = 1 means no borrow, C = 0 means borrow
            -- In 2's complement subtraction, the carry out is inverted to get the borrow status
            if i_A >= i_B then
                C_flag <= '1';  -- No borrow needed
            else
                C_flag <= '0';  -- Borrow needed
            end if;
        else
            C_flag <= '0';  -- No carry for logical operations
        end if;
    end process;
    
    -- Overflow flag
    -- Calculate overflow based on the operation
    process(i_op, i_A, i_B, result_out)
    begin
        if i_op = OP_ADD then
            -- Overflow in addition: when adding two positives gives negative or two negatives gives positive
            V_flag <= (not i_A(7) and not i_B(7) and result_out(7)) or 
                      (i_A(7) and i_B(7) and not result_out(7));
        elsif i_op = OP_SUB then
            -- Overflow in subtraction: when subtracting a negative from positive gives negative
            -- or subtracting a positive from negative gives positive
            V_flag <= (not i_A(7) and i_B(7) and result_out(7)) or 
                      (i_A(7) and not i_B(7) and not result_out(7));
        else
            -- No overflow for logical operations
            V_flag <= '0';
        end if;
    end process;
    
    -- Output assignments
    o_result <= result_out;
    o_flags <= N_flag & Z_flag & C_flag & V_flag;  -- NZCV format
    
end Behavioral;