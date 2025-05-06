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
    constant OP_ADD : std_logic_vector(2 downto 0) := "000";
    constant OP_SUB : std_logic_vector(2 downto 0) := "001";
    constant OP_AND : std_logic_vector(2 downto 0) := "010";
    constant OP_OR  : std_logic_vector(2 downto 0) := "011";
    
    component ripple_adder is
        Port ( A : in STD_LOGIC_VECTOR (3 downto 0);
               B : in STD_LOGIC_VECTOR (3 downto 0);
               Cin : in STD_LOGIC;
               S : out STD_LOGIC_VECTOR (3 downto 0);
               Cout : out STD_LOGIC);
    end component;
    
    signal w_B : STD_LOGIC_VECTOR (7 downto 0);  -- Modified B input for subtraction
    signal w_Cin : STD_LOGIC;                    -- Carry in for first adder
    signal w_Cout_low : STD_LOGIC;               -- Carry out from lower adder
    signal w_Cout_high : STD_LOGIC;              -- Carry out from higher adder
    signal w_Sum : STD_LOGIC_VECTOR (7 downto 0); -- Addition/subtraction result
    signal w_And : STD_LOGIC_VECTOR (7 downto 0); -- AND result
    signal w_Or : STD_LOGIC_VECTOR (7 downto 0);  -- OR result
    signal result_out : STD_LOGIC_VECTOR (7 downto 0); -- Final result
    
    signal N_flag : std_logic;  -- Negative
    signal Z_flag : std_logic;  -- Zero
    signal C_flag : std_logic;  -- Carry
    signal V_flag : std_logic;  -- Overflow
    
begin
    w_B <= not i_B when i_op = OP_SUB else i_B;
    w_Cin <= '1' when i_op = OP_SUB else '0';
    
    lower_adder: ripple_adder
    port map (
        A => i_A(3 downto 0),
        B => w_B(3 downto 0),
        Cin => w_Cin,
        S => w_Sum(3 downto 0),
        Cout => w_Cout_low
    );
    
    upper_adder: ripple_adder
    port map (
        A => i_A(7 downto 4),
        B => w_B(7 downto 4),
        Cin => w_Cout_low,
        S => w_Sum(7 downto 4),
        Cout => w_Cout_high
    );
    
    w_And <= i_A and i_B;
    w_Or <= i_A or i_B;
    
    process(i_op, w_Sum, w_And, w_Or)
    begin
        case i_op is
            when OP_ADD | OP_SUB =>
                result_out <= w_Sum;
            when OP_AND =>
                result_out <= w_And;
            when OP_OR =>
                result_out <= w_Or;
            when others =>
                result_out <= w_Sum;  
        end case;
    end process;
        
    N_flag <= result_out(7);
    
    Z_flag <= '1' when result_out = "00000000" else '0';
    
    C_flag <= w_Cout_high when (i_op = OP_ADD) else
              not w_Cout_high when (i_op = OP_SUB) else 
              '0';  
    
    process(i_op, i_A, i_B, result_out, w_B)
    begin
        if i_op = OP_ADD then
            V_flag <= (i_A(7) and i_B(7) and not result_out(7)) or 
                     (not i_A(7) and not i_B(7) and result_out(7));
        elsif i_op = OP_SUB then
            V_flag <= (i_A(7) and not i_B(7) and not result_out(7)) or 
                     (not i_A(7) and i_B(7) and result_out(7));
        else
            V_flag <= '0';
        end if;
    end process;
    
    o_result <= result_out;
    o_flags <= N_flag & Z_flag & C_flag & V_flag;  -- NZCV format
    
end Behavioral;