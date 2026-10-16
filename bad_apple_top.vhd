library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- EDGE Spartan 7, 50 MHz, LCD 8-bit; board ties LCD R/W to GND.
-- UART: 115200 8N1. Packet = FF + 76 payload bytes + SUM(payload) mod 256.
-- Payload: 64 CGRAM bytes (0..31), then 12 ASCII bytes for line 2 columns 5..16.
entity bad_apple_top is
  generic (CLK_HZ : positive := 50000000; BAUD : positive := 115200);
  port (clk, rst, uart_rx : in std_logic;
        lcd_data : out std_logic_vector(7 downto 0);
        lcd_rs, lcd_e : out std_logic);
end entity;

architecture rtl of bad_apple_top is
  subtype byte_t is std_logic_vector(7 downto 0);
  type payload_t is array (0 to 75) of byte_t;
  function empty_frame return payload_t is
    variable f : payload_t := (others => x"00");
    constant t : string(1 to 12) := " Waiting... ";
  begin
    for i in 0 to 11 loop f(64+i) := std_logic_vector(to_unsigned(character'pos(t(i+1)),8)); end loop;
    return f;
  end function;
  constant TITLE : string(1 to 12) := " Bad Apple! ";
  type init_t is array(0 to 6) of byte_t;
  constant INIT : init_t := (x"30",x"30",x"30",x"38",x"08",x"01",x"06");
  constant BIT_CYCLES : positive := CLK_HZ / BAUD;
  constant US_CYCLES : positive := CLK_HZ / 1000000;
  signal rx_meta, rx_sync : std_logic := '1';
  signal rst_meta, rst_sync : std_logic := '1';
  attribute ASYNC_REG : string;
  attribute ASYNC_REG of rx_meta, rx_sync, rst_meta, rst_sync : signal is "TRUE";
  type rx_state_t is (RX_IDLE,RX_START,RX_BITS,RX_STOP);
  signal rx_state : rx_state_t := RX_IDLE;
  signal bit_timer : natural range 0 to BIT_CYCLES-1 := 0;
  signal bit_index : natural range 0 to 7 := 0;
  signal shift_byte, rx_byte : byte_t := (others=>'0');
  signal rx_valid : std_logic := '0';
  signal receiving : std_logic := '0';
  signal payload_index : natural range 0 to 76 := 0;
  signal checksum : unsigned(7 downto 0) := (others=>'0');
  signal incoming, latest, displayed : payload_t := empty_frame;
  signal generation, seen : unsigned(15 downto 0) := (others=>'0');
  signal packet_timeout : natural range 0 to CLK_HZ/10 := 0;
  signal us_counter : natural range 0 to US_CYCLES-1 := 0;
  signal us_tick : std_logic := '0';
  type lcd_state_t is (POWER_WAIT, ISSUE, SETUP_WAIT, E_HIGH, HOLD_WAIT, GAP_WAIT, IDLE);
  signal lcd_state : lcd_state_t := POWER_WAIT;
  signal delay_us : natural range 0 to 50000 := 0;
  signal initialising : boolean := true;
  signal first_draw : boolean := true;
  signal init_index : natural range 0 to 6 := 0;
  signal draw_index : natural range 0 to 99 := 0;
  signal db : byte_t := x"00";
  signal rs_reg, e_reg : std_logic := '0';
begin
  assert CLK_HZ mod 1000000 = 0 report "CLK_HZ must be a multiple of 1 MHz" severity failure;
  assert BIT_CYCLES >= 8 report "Clock too slow for selected baud" severity failure;
  lcd_data <= db; lcd_rs <= rs_reg; lcd_e <= e_reg;
  process(clk)
  begin
    if rising_edge(clk) then
      rx_meta <= uart_rx; rx_sync <= rx_meta;
      rst_meta <= rst; rst_sync <= rst_meta;
    end if;
  end process;

  -- Sample start at its midpoint, then each data/stop bit one bit-time apart.
  process(clk)
  begin
    if rising_edge(clk) then
      rx_valid <= '0';
      if rst_sync='1' then
        rx_state<=RX_IDLE; bit_timer<=0; bit_index<=0;
      else
        case rx_state is
          when RX_IDLE =>
            if rx_sync='0' then bit_timer<=BIT_CYCLES/2-1; rx_state<=RX_START; end if;
          when RX_START =>
            if bit_timer=0 then
              if rx_sync='0' then bit_timer<=BIT_CYCLES-1; bit_index<=0; rx_state<=RX_BITS;
              else rx_state<=RX_IDLE; end if;
            else bit_timer<=bit_timer-1; end if;
          when RX_BITS =>
            if bit_timer=0 then
              shift_byte(bit_index)<=rx_sync; bit_timer<=BIT_CYCLES-1;
              if bit_index=7 then rx_state<=RX_STOP; else bit_index<=bit_index+1; end if;
            else bit_timer<=bit_timer-1; end if;
          when RX_STOP =>
            if bit_timer=0 then
              if rx_sync='1' then rx_byte<=shift_byte; rx_valid<='1'; end if;
              rx_state<=RX_IDLE;
            else bit_timer<=bit_timer-1; end if;
        end case;
      end if;
    end if;
  end process;

  -- Only publish complete valid packets. FF cannot appear in a valid payload.
  process(clk)
  begin
    if rising_edge(clk) then
      if rst_sync='1' then
        receiving<='0'; payload_index<=0; checksum<=(others=>'0');
        latest<=empty_frame; generation<=(others=>'0'); packet_timeout<=0;
      elsif rx_valid='1' then
        packet_timeout<=0;
        if receiving='1' and payload_index=76 then
          receiving<='0';
          if unsigned(rx_byte)=checksum then latest<=incoming; generation<=generation+1;
          elsif rx_byte=x"FF" then receiving<='1'; payload_index<=0; checksum<=(others=>'0'); end if;
        elsif rx_byte=x"FF" then
          receiving<='1'; payload_index<=0; checksum<=(others=>'0');
        elsif receiving='1' then
          if (payload_index<64 and unsigned(rx_byte)>31) or
             (payload_index>=64 and unsigned(rx_byte)>127) then receiving<='0';
          else
            incoming(payload_index)<=rx_byte;
            checksum<=checksum+unsigned(rx_byte); payload_index<=payload_index+1;
          end if;
        end if;
      elsif receiving='1' then
        if packet_timeout=CLK_HZ/10 then receiving<='0'; packet_timeout<=0;
        else packet_timeout<=packet_timeout+1; end if;
      end if;
    end if;
  end process;

  process(clk)
  begin
    if rising_edge(clk) then
      us_tick<='0';
      if rst_sync='1' then us_counter<=0;
      elsif us_counter=US_CYCLES-1 then us_counter<=0; us_tick<='1';
      else us_counter<=us_counter+1; end if;
    end if;
  end process;

  -- All logic uses clk; microsecond tick is a clock enable, never a generated clock.
  -- 1 us setup, 1 us E high, 1 us hold, >=100 us instruction gap.
  process(clk)
    variable pos : natural;
  begin
    if rising_edge(clk) then
      if rst_sync='1' then
        lcd_state<=POWER_WAIT; delay_us<=0; initialising<=true; init_index<=0;
        first_draw<=true; draw_index<=0; db<=x"00"; rs_reg<='0'; e_reg<='0';
        displayed<=empty_frame; seen<=(others=>'0');
      elsif us_tick='1' then
        case lcd_state is
          when POWER_WAIT =>
            if delay_us=49999 then delay_us<=0; lcd_state<=ISSUE;
            else delay_us<=delay_us+1; end if;
          when ISSUE =>
            rs_reg<='0'; e_reg<='0';
            if initialising then db<=INIT(init_index);
            elsif draw_index=0 then db<=x"40";
            elsif draw_index<=64 then db<=displayed(draw_index-1); rs_reg<='1';
            elsif draw_index=65 then db<=x"80";
            elsif draw_index<=81 then
              pos:=draw_index-66; rs_reg<='1';
              if pos<4 then db<=std_logic_vector(to_unsigned(pos,8));
              else db<=std_logic_vector(to_unsigned(character'pos(TITLE(pos-3)),8)); end if;
            elsif draw_index=82 then db<=x"C0";
            elsif draw_index<=98 then
              pos:=draw_index-83; rs_reg<='1';
              if pos<4 then db<=std_logic_vector(to_unsigned(pos+4,8));
              else db<=displayed(64+pos-4); end if;
            else db<=x"0C"; end if;
            lcd_state<=SETUP_WAIT;
          when SETUP_WAIT => e_reg<='1'; lcd_state<=E_HIGH;
          when E_HIGH => e_reg<='0'; lcd_state<=HOLD_WAIT;
          when HOLD_WAIT => delay_us<=0; lcd_state<=GAP_WAIT;
          when GAP_WAIT =>
            if (initialising and delay_us=4999) or ((not initialising) and delay_us=99) then
              delay_us<=0;
              if initialising then
                if init_index=6 then initialising<=false; lcd_state<=IDLE;
                else init_index<=init_index+1; lcd_state<=ISSUE; end if;
              elsif draw_index=99 then lcd_state<=IDLE;
              else draw_index<=draw_index+1; lcd_state<=ISSUE; end if;
            else delay_us<=delay_us+1; end if;
          when IDLE =>
            if first_draw or generation/=seen then
              displayed<=latest; seen<=generation; first_draw<=false;
              draw_index<=0; lcd_state<=ISSUE;
            end if;
        end case;
      end if;
    end if;
  end process;
end architecture;
