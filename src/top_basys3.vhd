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
    signal alu_flags      : std_logic_vector(3 downto 0); -- NZCV format
    
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
    signal mod_display_an : std_logic_vector(3 downto 0);
    
    -- Segment display signals
    signal normal_seg     : std_logic_vector(6 downto 0);
    
    -- Flag signals remapped
    signal neg_flag, zero_flag, carry_flag, overflow_flag : std_logic;
    signal stored_op : std_logic_vector(2 downto 0) := (others => '0');
    signal delayed_btnC_edge : std_logic := '0';

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
    
    -- In the ALU port map, use the stored operation instead of direct switches
    alu_inst: ALU
        port map (
            i_A      => op_A,
            i_B      => op_B,
            i_op     => stored_op,  -- Use stored operation instead of sw(2 downto 0)
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
            o_seg => normal_seg
        );
    
    -- CONCURRENT STATEMENTS ----------------------------
    
    -- Handle the minus sign display - always use blank (0xF) unless negative in RESULT state
    digit_sign <= "1111";  -- Always blank
    
    -- Remap ALU flags from NZCV format to individual signals
    neg_flag <= alu_flags(3);      -- N flag (bit 3)
    zero_flag <= alu_flags(2);     -- Z flag (bit 2)
    carry_flag <= alu_flags(1);    -- C flag (bit 1)
    overflow_flag <= alu_flags(0); -- V flag (bit 0)
        
    -- Map FSM state to lower 4 LEDs
    led(3 downto 0) <= fsm_cycle;
    
    -- Map ALU flags to upper LEDs as requested
    -- LED 15 = negative, 14 = carry, 13 = overflow, 12 = zero
    led(15) <= neg_flag when fsm_cycle = STATE_RESULT else '0';     -- Negative flag
    led(14) <= carry_flag when fsm_cycle = STATE_RESULT else '0';   -- Carry flag
    led(13) <= overflow_flag when fsm_cycle = STATE_RESULT else '0'; -- Overflow flag
    led(12) <= zero_flag when fsm_cycle = STATE_RESULT else '0';    -- Zero flag
    
    -- Ground unused LEDs
    led(11 downto 4) <= (others => '0');
    
    -- Display enable logic - only enable display in states OP1, OP2, and RESULT
    display_enable <= '0' when fsm_cycle = STATE_CLEAR else '1';
    
    -- Connect anodes - blank the display in CLEAR state 
    -- And handle special case for leftmost digit
    mod_display_an <= display_an when (fsm_cycle = STATE_RESULT and is_negative = '1') or display_an /= "0111" else
                      "1111"; -- Turn off leftmost digit when it's not needed
                      
    an <= "1111" when (display_enable = '0') else mod_display_an;
    
    -- PROCESSES ----------------------------------------
    
    -- Segment handling process - VHDL-93 compatible version using if-then-else
    process(display_digit, display_an, is_negative, fsm_cycle)
    begin
        -- By default, use the output from the sevenseg_decoder
        seg <= normal_seg;
        
        -- Special handling for leftmost digit when we need to show dash
        if display_an = "0111" and fsm_cycle = STATE_RESULT and is_negative = '1' then
            -- Override with dash pattern (just middle segment on)
            seg <= "0111111";
        end if;
    end process;
    
    -- Button edge detection process
    process(slow_clk, btnU)
    begin
        if btnU = '1' then
            btnC_sync1 <= '0';
            btnC_sync2 <= '0';
            btnC_debounced <= '0';
            btnC_prev <= '0';
            btnC_edge <= '0';
            delayed_btnC_edge <= '0';
        elsif rising_edge(slow_clk) then
            -- Two-stage synchronizer for button
            btnC_sync1 <= btnC;
            btnC_sync2 <= btnC_sync1;
            btnC_debounced <= btnC_sync2;
            
            -- Edge detection (rising edge only)
            btnC_prev <= btnC_debounced;
            
            -- Delay btnC_edge by one cycle
            delayed_btnC_edge <= btnC_edge;
            
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
            -- Reset operands and operation
            op_A <= (others => '0');
            op_B <= (others => '0');
            stored_op <= (others => '0');
        elsif rising_edge(slow_clk) then
            -- On delayed button press, capture values from switches
            if delayed_btnC_edge = '1' then
                case fsm_cycle is
                    when STATE_OP1 => 
                        -- We're now in OP1, capture op_A
                        op_A <= sw(7 downto 0);
                        
                    when STATE_OP2 =>
                        -- We're now in OP2, capture op_B
                        op_B <= sw(7 downto 0);
                        
                    when STATE_RESULT =>
                        -- We're now in RESULT, capture operation
                        stored_op <= sw(2 downto 0);
                        
                    when others =>
                        -- No capture in other states
                        null;
                end case;
            end if;
        end if;
    end process;
    -- Display data selection process
    process(fsm_cycle, op_A, op_B, alu_result)
    begin
        -- Default: blank display
        display_data <= (others => '0');
        
        -- Select data to display based on current state
        case fsm_cycle is
            when STATE_CLEAR =>
                -- Clear state - display is blank
                display_data <= (others => '0');
                
            when STATE_OP1 =>
                -- OP1 state - display the captured value of op_A
                display_data <= op_A;
                
            when STATE_OP2 =>
                -- OP2 state - display the captured value of op_B
                display_data <= op_B;
                
            when STATE_RESULT =>
                -- RESULT state - show the ALU result
                display_data <= alu_result;
                
            when others =>
                display_data <= (others => '0');
        end case;
    end process;
        
end top_basys3_arch;