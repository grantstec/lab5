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

-- Top-level module
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
    
    component sevenseg_decoder is
        port (
            i_hex    : in std_logic_vector(3 downto 0);
            o_seg    : out std_logic_vector(6 downto 0)
        );
    end component;
    
    -- Function to convert 4-bit binary to 7-segment display
    function sevenseg_decode(hex : std_logic_vector(3 downto 0)) return std_logic_vector is
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
    
    -- Button debounce and synchronization signals
    signal btnC_sync1     : std_logic := '0';
    signal btnC_sync2     : std_logic := '0';
    signal btnC_debounced : std_logic := '0';
    
    -- Clocking
    signal slow_clk       : std_logic;
    
    -- State constants (one-hot encoding)
    constant STATE_CLEAR  : std_logic_vector(3 downto 0) := "0001";  -- S0
    constant STATE_OP1    : std_logic_vector(3 downto 0) := "0010";  -- S1
    constant STATE_OP2    : std_logic_vector(3 downto 0) := "0100";  -- S2
    constant STATE_RESULT : std_logic_vector(3 downto 0) := "1000";  -- S3
    
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
            i_adv   => btnC_debounced,
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
    
    -- Handle the minus sign display
    -- Use the minus sign (dash) for negative numbers
    digit_sign <= "1111" when is_negative = '1' else  -- Display dash for negative
                  "1111";                            -- Otherwise blank
    
    -- Convert 4-bit binary digit to 7-segment display pattern using the function
    seg <= sevenseg_decode(display_digit);
    
    -- Map FSM state to lower 4 LEDs and ALU flags to upper 4 LEDs
    led(3 downto 0) <= fsm_cycle;
    led(15 downto 12) <= alu_flags;
    -- Ground unused LEDs
    led(11 downto 4) <= (others => '0');
    
    -- PROCESSES ----------------------------------------
    
    -- Button debounce/synchronization process 
    process(slow_clk, btnU)
    begin
        if btnU = '1' then
            btnC_sync1 <= '0';
            btnC_sync2 <= '0';
            btnC_debounced <= '0';
        elsif rising_edge(slow_clk) then
            -- Two-stage synchronizer
            btnC_sync1 <= btnC;
            btnC_sync2 <= btnC_sync1;
            
            -- Debounced signal (simple synchronizer with slow clock)
            btnC_debounced <= btnC_sync2;
        end if;
    end process;
    
    -- Operand capture process
    process(slow_clk, btnU)
    begin
        if btnU = '1' then
            op_A <= (others => '0');
            op_B <= (others => '0');
        elsif rising_edge(slow_clk) then
            -- Capture operands based on current state
            case fsm_cycle is
                when STATE_OP1 =>
                    op_A <= sw(7 downto 0);
                when STATE_OP2 =>
                    op_B <= sw(7 downto 0);
                when others =>
                    -- Do nothing in other states
            end case;
        end if;
    end process;
    
    -- Display data selection process
    process(fsm_cycle, sw, op_A, op_B, alu_result)
    begin
        -- Default: blank display
        display_data <= (others => '0');
        
        -- Select data to display based on current state
        case fsm_cycle is
            when STATE_CLEAR =>
                display_data <= (others => '0');
                
            when STATE_OP1 =>
                display_data <= sw(7 downto 0);
                
            when STATE_OP2 =>
                display_data <= sw(7 downto 0);
                
            when STATE_RESULT =>
                display_data <= alu_result;
                
            when others =>
                display_data <= (others => '0');
        end case;
    end process;
    
end top_basys3_arch;

-- Sevenseg_decoder implementation in a separate architecture unit
-- This allows test benches to reference it
library ieee;
use ieee.std_logic_1164.all;

entity sevenseg_decoder is
    Port ( i_hex : in STD_LOGIC_VECTOR (3 downto 0);
           o_seg : out STD_LOGIC_VECTOR (6 downto 0));
end sevenseg_decoder;

architecture Behavioral of sevenseg_decoder is
begin
    -- 7-segment display decoder (active-low outputs)
    with i_hex select
        o_seg <= "1000000" when x"0",   -- 0
                 "1111001" when x"1",   -- 1
                 "0100100" when x"2",   -- 2
                 "0110000" when x"3",   -- 3
                 "0011001" when x"4",   -- 4
                 "0010010" when x"5",   -- 5
                 "0000010" when x"6",   -- 6
                 "1111000" when x"7",   -- 7
                 "0000000" when x"8",   -- 8
                 "0010000" when x"9",   -- 9
                 "0001000" when x"A",   -- A
                 "0000011" when x"B",   -- b
                 "1000110" when x"C",   -- C
                 "0100001" when x"D",   -- d
                 "0000110" when x"E",   -- E
                 "0001110" when x"F",   -- F
                 "0111111" when others; -- dash (default)
end Behavioral;