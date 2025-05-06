----------------------------------------------------------------------------------
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

entity controller_fsm is
    Port ( i_reset : in STD_LOGIC;
           i_adv : in STD_LOGIC;
           o_cycle : out STD_LOGIC_VECTOR (3 downto 0));
end controller_fsm;

architecture FSM of controller_fsm is
    -- Define state encoding constants (one-hot encoding)
    constant STATE_CLEAR  : std_logic_vector(3 downto 0) := "0001";  -- S0
    constant STATE_OP1    : std_logic_vector(3 downto 0) := "0010";  -- S1
    constant STATE_OP2    : std_logic_vector(3 downto 0) := "0100";  -- S2
    constant STATE_RESULT : std_logic_vector(3 downto 0) := "1000";  -- S3
    
    -- Define state register that will store the current state
    signal current_state : std_logic_vector(3 downto 0) := STATE_CLEAR;
begin
    -- State transition process
    process(i_reset, i_adv)
    begin
        if i_reset = '1' then
            current_state <= STATE_CLEAR;
        elsif rising_edge(i_adv) then
            case current_state is
                when STATE_CLEAR =>
                    current_state <= STATE_OP1;
                when STATE_OP1 =>
                    current_state <= STATE_OP2;
                when STATE_OP2 =>
                    current_state <= STATE_RESULT;
                when STATE_RESULT =>
                    current_state <= STATE_CLEAR;
                when others =>
                    current_state <= STATE_CLEAR;
            end case;
        end if;
    end process;
    
    o_cycle <= current_state;
end FSM;