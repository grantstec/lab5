----------------------------------------------------------------------------------
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

entity controller_fsm is
    Port ( i_reset : in STD_LOGIC;
           i_adv : in STD_LOGIC;
           o_cycle : out STD_LOGIC_VECTOR (3 downto 0));
end controller_fsm;

architecture FSM of controller_fsm is
begin
    -- Pure combinational logic - no internal state variables
    -- This avoids latches and multiple drivers
    o_cycle <= "0001" when i_reset = '1' else
               "0010" when i_adv = '1' else
               "0001";
end FSM;