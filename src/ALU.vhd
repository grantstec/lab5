library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

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
    
    -- Internal signals
    signal result_add : std_logic_vector(8 downto 0); -- Extra bit for carry
    signal result_sub : std_logic_vector(8 downto 0); -- Extra bit for borrow/carry
    signal result_and : std_logic_vector(7 downto 0);
    signal result_or  : std_logic_vector(7 downto 0);
    signal result_out : std_logic_vector(7 downto 0);
    
    -- Flag signals
    signal N_flag : std_logic;  -- Negative
    signal Z_flag : std_logic;  -- Zero
    signal C_flag : std_logic;  -- Carry
    signal V_flag : std_logic;  -- Overflow
    
begin
    
    result_add <= std_logic_vector('0' & unsigned(i_A) + unsigned(i_B));
    
    result_sub <= std_logic_vector('0' & unsigned(i_A) - unsigned(i_B));        
    
    result_and <= i_A and i_B;
    
    result_or <= i_A or i_B;
    
    process(i_op, result_add, result_sub, result_and, result_or)
    begin
        case i_op is
            when OP_ADD =>
                result_out <= result_add(7 downto 0);
                C_flag <= result_add(8);
                V_flag <= (i_A(7) and i_B(7) and not result_add(7)) or 
                         (not i_A(7) and not i_B(7) and result_add(7));
                
            when OP_SUB =>
                result_out <= result_sub(7 downto 0);
                C_flag <= not result_sub(8); 
                V_flag <= (i_A(7) and not i_B(7) and not result_sub(7)) or 
                         (not i_A(7) and i_B(7) and result_sub(7));
 
            when OP_AND =>
                result_out <= result_and;
                C_flag <= '0';
                V_flag <= '0';
                
            when OP_OR =>
                result_out <= result_or;
                C_flag <= '0';
                V_flag <= '0';
                
            when others =>
                result_out <= result_add(7 downto 0);
                C_flag <= '0';
                V_flag <= '0';
        end case;
    end process;
    
    N_flag <= result_out(7);
    
    Z_flag <= '1' when result_out = "00000000" else '0';
    
    o_result <= result_out;
    o_flags <= N_flag & Z_flag & C_flag & V_flag; 
    
end Behavioral;