--+----------------------------------------------------------------------------
--|
--| NAMING CONVENSIONS :
--|
--|    xb_<port name>           = off-chip bidirectional port ( _pads file )
--|    xi_<port name>           = off-chip input port         ( _pads file )
--|    xo_<port name>           = off-chip output port        ( _pads file )
--|    b_<port name>            = on-chip bidirectional port
--|    i_<port name>            = on-chip input port
--|    o_<port name>            = on-chip output port
--|    c_<signal name>          = combinatorial signal
--|    f_<signal name>          = synchronous signal
--|    ff_<signal name>         = pipeline stage (ff_, fff_, etc.)
--|    <signal name>_n          = active low signal
--|    w_<signal name>          = top level wiring signal
--|    g_<generic name>         = generic
--|    k_<constant name>        = constant
--|    v_<variable name>        = variable
--|    sm_<state machine type>  = state machine type definition
--|    s_<signal name>          = state name
--|
--+----------------------------------------------------------------------------
library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;


entity top_basys3 is
    port(
        -- inputs
        clk     :   in std_logic; -- native 100MHz FPGA clock
        sw      :   in std_logic_vector(15 downto 0); -- operands and opcode
        btnU    :   in std_logic; -- reset
        btnL    :   in std_logic; -- clock divider reset
        btnC    :   in std_logic; -- fsm cycle
        
        -- outputs
        led     :   out std_logic_vector(15 downto 0);
        -- 7-segment display segments (active-low cathodes)
        seg     :   out std_logic_vector(6 downto 0);
        -- 7-segment display active-low enables (anodes)
        an      :   out std_logic_vector(3 downto 0)
    );
end top_basys3;

architecture top_basys3_arch of top_basys3 is 
  
    -- Component declarations
    component clock_divider is
        generic ( constant k_DIV : natural := 2 );
        port ( 
            i_clk    : in std_logic;
            i_reset  : in std_logic;
            o_clk    : out std_logic
        );
    end component;
    
    component controller_fsm is
        port (
            i_reset  : in std_logic;
            i_adv    : in std_logic;
            o_cycle  : out std_logic_vector(3 downto 0)
        );
    end component;
    
    component ALU is
        port (
            i_A      : in std_logic_vector(7 downto 0);
            i_B      : in std_logic_vector(7 downto 0);
            i_op     : in std_logic_vector(2 downto 0);
            o_result : out std_logic_vector(7 downto 0);
            o_flags  : out std_logic_vector(3 downto 0)
        );
    end component;
    
    component twos_comp is
        port (
            i_bin    : in std_logic_vector(7 downto 0);
            o_sign   : out std_logic;
            o_hund   : out std_logic_vector(3 downto 0);
            o_tens   : out std_logic_vector(3 downto 0);
            o_ones   : out std_logic_vector(3 downto 0)
        );
    end component;
    
    component TDM4 is
        generic ( constant k_WIDTH : natural := 4 );
        port (
            i_clk    : in std_logic;
            i_reset  : in std_logic;
            i_D3     : in std_logic_vector(k_WIDTH - 1 downto 0);
            i_D2     : in std_logic_vector(k_WIDTH - 1 downto 0);
            i_D1     : in std_logic_vector(k_WIDTH - 1 downto 0);
            i_D0     : in std_logic_vector(k_WIDTH - 1 downto 0);
            o_data   : out std_logic_vector(k_WIDTH - 1 downto 0);
            o_sel    : out std_logic_vector(3 downto 0)
        );
    end component;
    
    -- Function to convert 4-bit binary to 7-segment display
    function sevenseg_decoder(hex : std_logic_vector(3 downto 0)) return std_logic_vector is
    begin
        case hex is
            when "0000" => return "1000000"; -- 0
            when "0001" => return "1111001"; -- 1
            when "0010" => return "0100100"; -- 2
            when "0011" => return "0110000"; -- 3
            when "0100" => return "0011001"; -- 4
            when "0101" => return "0010010"; -- 5
            when "0110" => return "0000010"; -- 6
            when "0111" => return "1111000"; -- 7
            when "1000" => return "0000000"; -- 8
            when "1001" => return "0010000"; -- 9
            when "1010" => return "0001000"; -- A
            when "1011" => return "0000011"; -- b
            when "1100" => return "1000110"; -- C
            when "1101" => return "0100001"; -- d
            when "1110" => return "0000110"; -- E
            when "1111" => return "0001110"; -- F
            when others => return "0111111"; -- dash
        end case;
    end function;
    
    -- Signals
    -- Clocking
    signal slow_clk       : std_logic;
    
    -- CPU signals
    signal fsm_cycle      : std_logic_vector(3 downto 0);
    signal op_A, op_B     : std_logic_vector(7 downto 0) := (others => '0');
    signal alu_result     : std_logic_vector(7 downto 0);
    signal alu_flags      : std_logic_vector(3 downto 0);
    
    -- Display signals
    signal display_data   : std_logic_vector(7 downto 0);
    signal is_negative    : std_logic;
    signal digit_hund     : std_logic_vector(3 downto 0);
    signal digit_tens     : std_logic_vector(3 downto 0);
    signal digit_ones     : std_logic_vector(3 downto 0);
    signal digit_sign     : std_logic_vector(3 downto 0);
    signal display_digit  : std_logic_vector(3 downto 0);
    signal segment_data   : std_logic_vector(6 downto 0);
    signal fsm_state : STD_LOGIC_VECTOR(3 downto 0) := "0001"; -- Default to IDLE

    
begin
    -- PORT MAPS ----------------------------------------
    
    -- Clock divider (100MHz to 4Hz)
    -- 100MHz / (2 * 12500000) = 4Hz
    clock_div_inst: clock_divider
        generic map ( k_DIV => 12500000 )
        port map (
            i_clk   => clk,
            i_reset => btnL,
            o_clk   => slow_clk
        );
    
    -- Controller FSM
    controller_fsm_inst: controller_fsm
        port map (
            i_reset => btnU,
            i_adv   => btnC,
            o_cycle => fsm_cycle
        );
    
    -- ALU
    alu_inst: ALU
        port map (
            i_A       => op_A,
            i_B       => op_B,
            i_op      => sw(2 downto 0),
            o_result  => alu_result,
            o_flags   => alu_flags
        );
    
    -- Two's complement to decimal converter
    twos_comp_inst: twos_comp
        port map (
            i_bin   => display_data,
            o_sign  => is_negative,
            o_hund  => digit_hund,
            o_tens  => digit_tens,
            o_ones  => digit_ones
        );
    
    -- Time Division Multiplexer for display
    tdm4_inst: TDM4
        generic map ( k_WIDTH => 4 )
        port map (
            i_clk   => clk,
            i_reset => btnU,
            i_D3    => digit_sign,
            i_D2    => digit_hund,
            i_D1    => digit_tens,
            i_D0    => digit_ones,
            o_data  => display_digit,
            o_sel   => an
        );
    
    -- CONCURRENT STATEMENTS ----------------------------
    
    -- Convert 4-bit binary digit to 7-segment display pattern
    segment_data <= sevenseg_decoder(display_digit);
    
    -- Output to 7-segment display
    seg <= segment_data;
    
    -- Map FSM state to lower 4 LEDs and ALU flags to upper 4 LEDs
    led(3 downto 0) <= fsm_cycle;
    led(15 downto 12) <= alu_flags;
    -- Ground unused LEDs
    led(11 downto 4) <= (others => '0');
    
    -- Process for determining the sign display digit
    digit_sign <= "1111" when is_negative = '1' else "1111"; -- Display dash or blank for negative
    
    -- Process for selecting what data to display based on FSM state
    process(fsm_cycle, sw, op_A, op_B, alu_result)
    begin
        -- Default blank display
        display_data <= (others => '0');
        
        case fsm_cycle is
            when "0001" => -- IDLE state - clear display
                display_data <= (others => '0');
                
            when "0010" => -- OP1 state - display operand 1
                display_data <= sw(7 downto 0);
                
            when "0100" => -- OP2 state - display operand 2
                display_data <= sw(7 downto 0);
                
            when "1000" => -- RESULT state - display ALU result
                display_data <= alu_result;
                
            when others =>
                display_data <= (others => '0');
        end case;
    end process;
-- Add a new state register in top_basys3

    -- In the process that captures operands based on FSM state
    -- Add state transition logic
    process(slow_clk, btnU)
    begin
        if btnU = '1' then
            -- Reset operand registers and FSM state
            op_A <= (others => '0');
            op_B <= (others => '0');
            fsm_state <= "0001"; -- IDLE state
        elsif rising_edge(slow_clk) then
            -- State transitions based on FSM cycle output
            case fsm_state is
                when "0001" => -- IDLE state
                    if btnC = '1' then
                        fsm_state <= "0010"; -- Move to OP1 state
                    end if;
                    
                when "0010" => -- OP1 state
                    -- Store operand A
                    op_A <= sw(7 downto 0);
                    if btnC = '1' then
                        fsm_state <= "0100"; -- Move to OP2 state
                    end if;
                    
                when "0100" => -- OP2 state
                    -- Store operand B
                    op_B <= sw(7 downto 0);
                    if btnC = '1' then
                        fsm_state <= "1000"; -- Move to RESULT state
                    end if;
                    
                when "1000" => -- RESULT state
                    if btnC = '1' then
                        fsm_state <= "0001"; -- Return to IDLE state
                    end if;
                    
                when others =>
                    fsm_state <= "0001"; -- Default to IDLE for safety
            end case;
        end if;
    end process;
            
end top_basys3_arch;