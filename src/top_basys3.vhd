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
    
    component sevenseg_decoder is
        port (
            i_hex    : in std_logic_vector(3 downto 0);
            o_seg    : out std_logic_vector(6 downto 0)
        );
    end component;
    
    -- Button debounce and synchronization signals
    signal btnC_sync1     : std_logic := '0';
    signal btnC_sync2     : std_logic := '0';
    signal btnC_debounced : std_logic := '0';
    signal btnC_prev      : std_logic := '0';
    signal btnC_edge      : std_logic := '0';
    
    -- Clocking
    signal slow_clk       : std_logic;
    signal tdm_clk        : std_logic; -- For the display refresh
    
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
    
    -- Display enable signals
    signal display_enable : std_logic;
    signal display_an     : std_logic_vector(3 downto 0);
    
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
    
    -- TDM clock divider (100MHz to 1kHz)
    -- 100MHz / (2 * 50000) = 1kHz
    tdm_clock_div: clock_divider
        generic map ( k_DIV => 50000 )
        port map (
            i_clk   => clk,
            i_reset => btnL,
            o_clk   => tdm_clk
        );
    
    -- Controller FSM
    controller_fsm_inst: controller_fsm
        port map (
            i_reset => btnU,
            i_adv   => btnC_edge,
            o_cycle => fsm_cycle
        );
    
    -- ALU
    alu_inst: ALU
        port map (
            i_A      => op_A,
            i_B      => op_B,
            i_op     => sw(2 downto 0),
            o_result => alu_result,
            o_flags  => alu_flags
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
            i_clk   => tdm_clk,  -- Use faster clock for smoother display
            i_reset => btnU,
            i_D3    => digit_sign,
            i_D2    => digit_hund,
            i_D1    => digit_tens,
            i_D0    => digit_ones,
            o_data  => display_digit,
            o_sel   => display_an
        );
    
    -- Connect 7-segment decoder
    sevenseg_inst: sevenseg_decoder
        port map (
            i_hex => display_digit,
            o_seg => seg
        );
    
    -- CONCURRENT STATEMENTS ----------------------------
    
    -- Handle the minus sign display
    -- Use "1111" (dash) for negative, "0000" (blank) for non-negative
    digit_sign <= "1111" when (is_negative = '1') else "0000";
        
    -- Map FSM state to lower 4 LEDs and ALU flags to upper 4 LEDs
    led(3 downto 0) <= fsm_cycle;
    led(15 downto 12) <= alu_flags when fsm_cycle = STATE_RESULT else "0000";
    -- Ground unused LEDs
    led(11 downto 4) <= (others => '0');
    
    -- Display enable logic - only enable display in states OP1, OP2, and RESULT
    display_enable <= '0' when fsm_cycle = STATE_CLEAR else '1';
    
    -- Connect anodes - blank the display in CLEAR state
    an <= "1111" when (display_enable = '0') else display_an;
    
    -- PROCESSES ----------------------------------------
    
    -- Button edge detection process 
    process(slow_clk, btnU)
    begin
        if btnU = '1' then
            btnC_sync1 <= '0';
            btnC_sync2 <= '0';
            btnC_debounced <= '0';
            btnC_prev <= '0';
            btnC_edge <= '0';
        elsif rising_edge(slow_clk) then
            -- Two-stage synchronizer for button
            btnC_sync1 <= btnC;
            btnC_sync2 <= btnC_sync1;
            btnC_debounced <= btnC_sync2;
            
            -- Edge detection (rising edge only)
            btnC_prev <= btnC_debounced;
            if btnC_debounced = '1' and btnC_prev = '0' then
                btnC_edge <= '1';
            else
                btnC_edge <= '0';
            end if;
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
            -- Only capture when transitioning to the next state
            if btnC_edge = '1' then
                case fsm_cycle is
                    when STATE_CLEAR =>
                        -- When moving from CLEAR to OP1, prepare to capture op_A
                        -- (op_A will be captured on next button press)
                        null;
                    when STATE_OP1 =>
                        -- Capture op_A when moving from OP1 to OP2
                        op_A <= sw(7 downto 0);
                    when STATE_OP2 =>
                        -- Capture op_B when moving from OP2 to RESULT
                        op_B <= sw(7 downto 0);
                    when others =>
                        -- Do nothing in other states
                        null;
                end case;
            end if;
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
                display_data <= sw(7 downto 0);  -- Show current switch value for input
                
            when STATE_OP2 =>
                display_data <= sw(7 downto 0);  -- Show current switch value for input
                
            when STATE_RESULT =>
                display_data <= alu_result;      -- Show computation result
                
            when others =>
                display_data <= (others => '0');
        end case;
    end process;
    
end top_basys3_arch;