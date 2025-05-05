----------------------------------------------------------------------------------
-- Company: 
-- Engineer: 
-- 
-- Create Date: 04/18/2025 02:42:49 PM
-- Design Name: 
-- Module Name: controller_fsm - FSM
-- Project Name: 
-- Target Devices: 
-- Tool Versions: 
-- Description: 
-- 
-- Dependencies: 
-- 
-- Revision:
-- Revision 0.01 - File Created
-- Additional Comments:
-- 
----------------------------------------------------------------------------------
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
-- Uncomment the following library declaration if using
-- arithmetic functions with Signed or Unsigned values
--use IEEE.NUMERIC_STD.ALL;
-- Uncomment the following library declaration if instantiating
-- any Xilinx leaf cells in this code.
--library UNISIM;
--use UNISIM.VComponents.all;

entity controller_fsm is
    Port ( i_reset : in STD_LOGIC;
           i_adv : in STD_LOGIC;
           o_cycle : out STD_LOGIC_VECTOR (3 downto 0));
end controller_fsm;

architecture FSM of controller_fsm is
    signal current_state : STD_LOGIC_VECTOR(3 downto 0) := "0001"; -- Default to IDLE
    signal next_state : STD_LOGIC_VECTOR(3 downto 0);
begin
   process(i_reset, i_adv, current_state)
   begin
       -- Default: maintain current state
       next_state <= current_state;
       
       if i_reset = '1' then
           -- Reset to IDLE state
           next_state <= "0001";
       elsif i_adv = '1' then
           -- Use case statement for state transitions
           case current_state is
               when "0001" => -- IDLE state
                   next_state <= "0010"; -- Go to OP1
               when "0010" => -- OP1 state
                   next_state <= "0100"; -- Go to OP2
               when "0100" => -- OP2 state
                   next_state <= "1000"; -- Go to RESULT
               when "1000" => -- RESULT state
                   next_state <= "0001"; -- Back to IDLE
               when others =>  -- Handle unexpected states
                   next_state <= "0001"; -- Go to IDLE
           end case;
       end if;
   end process;
   
   -- State update (without clock)
   current_state <= next_state;
   
   -- Output assignment
   o_cycle <= current_state;
                   
end FSM;