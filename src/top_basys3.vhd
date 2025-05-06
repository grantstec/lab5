library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;

entity top_basys3 is
    port(
        clk     :   in std_logic; 
        sw      :   in std_logic_vector(15 downto 0); 
        btnU    :   in std_logic; 
        btnL    :   in std_logic; 
        btnC    :   in std_logic; 
        
        led     :   out std_logic_vector(15 downto 0);
        seg     :   out std_logic_vector(6 downto 0);
        an      :   out std_logic_vector(3 downto 0)
    );
end top_basys3;

architecture top_basys3_arch of top_basys3 is 
  
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
    
    signal btnC_sync1     : std_logic := '0';
    signal btnC_sync2     : std_logic := '0';
    signal btnC_debounced : std_logic := '0';
    signal btnC_prev      : std_logic := '0';
    signal btnC_edge      : std_logic := '0';
    signal delayed_btnC_edge : std_logic := '0';
    signal slow_clk       : std_logic;
    signal tdm_clk        : std_logic; 
    constant STATE_CLEAR  : std_logic_vector(3 downto 0) := "0001";  -- S0
    constant STATE_OP1    : std_logic_vector(3 downto 0) := "0010";  -- S1
    constant STATE_OP2    : std_logic_vector(3 downto 0) := "0100";  -- S2
    constant STATE_RESULT : std_logic_vector(3 downto 0) := "1000";  -- S3
    signal fsm_cycle      : std_logic_vector(3 downto 0);
    signal op_A, op_B     : std_logic_vector(7 downto 0) := (others => '0');
    signal alu_result     : std_logic_vector(7 downto 0);
    signal alu_flags      : std_logic_vector(3 downto 0); -- NZCV format
    signal stored_op      : std_logic_vector(2 downto 0) := (others => '0');
    signal display_data   : std_logic_vector(7 downto 0);
    signal is_negative    : std_logic;
    signal digit_hund     : std_logic_vector(3 downto 0);
    signal digit_tens     : std_logic_vector(3 downto 0);
    signal digit_ones     : std_logic_vector(3 downto 0);
    signal digit_sign     : std_logic_vector(3 downto 0);
    signal display_digit  : std_logic_vector(3 downto 0);
    signal display_enable : std_logic;
    signal display_an     : std_logic_vector(3 downto 0);
    signal mod_display_an : std_logic_vector(3 downto 0);
    signal neg_flag, zero_flag, carry_flag, overflow_flag : std_logic;

begin
    
    clock_div_inst: clock_divider
        generic map ( k_DIV => 125000 )
        port map (
            i_clk   => clk,
            i_reset => btnL,
            o_clk   => slow_clk
        );
    
    tdm_clock_div: clock_divider
        generic map ( k_DIV => 50000 )
        port map (
            i_clk   => clk,
            i_reset => btnL,
            o_clk   => tdm_clk
        );
    
    controller_fsm_inst: controller_fsm
        port map (
            i_reset => btnU,
            i_adv   => btnC_edge,
            o_cycle => fsm_cycle
        );
    
    alu_inst: ALU
        port map (
            i_A      => op_A,
            i_B      => op_B,
            i_op     => stored_op, 
            o_result => alu_result,
            o_flags  => alu_flags
        );
    
    twos_comp_inst: twos_comp
        port map (
            i_bin   => display_data,
            o_sign  => is_negative,
            o_hund  => digit_hund,
            o_tens  => digit_tens,
            o_ones  => digit_ones
        );
    
    tdm4_inst: TDM4
        generic map ( k_WIDTH => 4 )
        port map (
            i_clk   => tdm_clk,
            i_reset => btnU,
            i_D3    => digit_sign,
            i_D2    => digit_hund,
            i_D1    => digit_tens,
            i_D0    => digit_ones,
            o_data  => display_digit,
            o_sel   => display_an
        );
    
    -- CONCURRENT STATEMENTS ----------------------------
    
    digit_sign <= "1111";  -- Default to blank
    
    neg_flag <= alu_flags(3);      -- N flag (bit 3)
    zero_flag <= alu_flags(2);     -- Z flag (bit 2)
    carry_flag <= alu_flags(1);    -- C flag (bit 1)
    overflow_flag <= alu_flags(0); -- V flag (bit 0)
        
    led(3 downto 0) <= fsm_cycle;
    
    led(15) <= neg_flag when fsm_cycle = STATE_RESULT else '0';      -- Negative flag
    led(14) <= carry_flag when fsm_cycle = STATE_RESULT else '0';    -- Carry flag
    led(13) <= overflow_flag when fsm_cycle = STATE_RESULT else '0'; -- Overflow flag
    led(12) <= zero_flag when fsm_cycle = STATE_RESULT else '0';     -- Zero flag
    
    led(11 downto 4) <= (others => '0');
    
    display_enable <= '0' when fsm_cycle = STATE_CLEAR else '1';
    
    mod_display_an <= display_an when (fsm_cycle = STATE_RESULT and is_negative = '1') or display_an /= "0111" else
                      "1111";
                      
    an <= "1111" when (display_enable = '0') else mod_display_an;
    
    
    process(display_digit, display_an, is_negative, fsm_cycle)
        variable decoded_segments : std_logic_vector(6 downto 0);
    begin
        case display_digit is
            when "0000" => decoded_segments := "1000000"; -- 0
            when "0001" => decoded_segments := "1111001"; -- 1
            when "0010" => decoded_segments := "0100100"; -- 2
            when "0011" => decoded_segments := "0110000"; -- 3
            when "0100" => decoded_segments := "0011001"; -- 4
            when "0101" => decoded_segments := "0010010"; -- 5
            when "0110" => decoded_segments := "0000010"; -- 6
            when "0111" => decoded_segments := "1111000"; -- 7
            when "1000" => decoded_segments := "0000000"; -- 8
            when "1001" => decoded_segments := "0010000"; -- 9
            when "1010" => decoded_segments := "0001000"; -- A
            when "1011" => decoded_segments := "0000011"; -- b
            when "1100" => decoded_segments := "1000110"; -- C
            when "1101" => decoded_segments := "0100001"; -- d
            when "1110" => decoded_segments := "0000110"; -- E
            when "1111" => decoded_segments := "0001110"; -- F
            when others => decoded_segments := "1111111"; -- All segments off
        end case;
        
        seg <= decoded_segments;
        
        if display_an = "0111" and fsm_cycle = STATE_RESULT and is_negative = '1' then
            seg <= "0111111"; -- Minus sign (only middle segment lit)
        end if;
    end process;
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
            btnC_sync1 <= btnC;
            btnC_sync2 <= btnC_sync1;
            btnC_debounced <= btnC_sync2;
            
            btnC_prev <= btnC_debounced;
            
            delayed_btnC_edge <= btnC_edge;
            
            if btnC_debounced = '1' and btnC_prev = '0' then
                btnC_edge <= '1';
            else
                btnC_edge <= '0';
            end if;
        end if;
    end process;
    
    process(slow_clk, btnU)
    begin
        if btnU = '1' then
            op_A <= (others => '0');
            op_B <= (others => '0');
            stored_op <= (others => '0');
        elsif rising_edge(slow_clk) then
            if delayed_btnC_edge = '1' then
                case fsm_cycle is
                    when STATE_OP1 => 
                        op_A <= sw(7 downto 0);
                        
                    when STATE_OP2 =>
                        op_B <= sw(7 downto 0);
                        
                    when STATE_RESULT =>
                        stored_op <= sw(2 downto 0);
                        
                    when others =>
                        null;
                end case;
            end if;
        end if;
    end process;

    process(fsm_cycle, op_A, op_B, alu_result)
    begin
        display_data <= (others => '0');
        
        case fsm_cycle is
            when STATE_CLEAR =>
                display_data <= (others => '0');
                
            when STATE_OP1 =>
                display_data <= op_A;
                
            when STATE_OP2 =>
                display_data <= op_B;
                
            when STATE_RESULT =>
                display_data <= alu_result;
                
            when others =>
                display_data <= (others => '0');
        end case;
    end process;
        
end top_basys3_arch;