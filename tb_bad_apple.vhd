library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;
entity tb_bad_apple is end;
architecture test of tb_bad_apple is
  signal clk : std_logic := '0';
  signal rst : std_logic := '1';
  signal rx : std_logic := '1';
  signal db : std_logic_vector(7 downto 0);
  signal rs,e : std_logic;
  type ram_t is array(0 to 63) of std_logic_vector(7 downto 0);
  signal cgram : ram_t := (others=>(others=>'0'));
  constant BT : time := 8680 ns;
begin
  clk <= not clk after 10 ns;
  dut: entity work.bad_apple_top port map(clk=>clk,rst=>rst,uart_rx=>rx,lcd_data=>db,lcd_rs=>rs,lcd_e=>e);
  monitor: process
    variable addr : natural := 0;
    variable cg : boolean := false;
    variable rise_at : time := 0 ns;
    variable rise_data : std_logic_vector(7 downto 0);
    variable rise_rs : std_logic;
  begin
    wait on e;
    if rising_edge(e) then
      rise_at:=now; rise_data:=db; rise_rs:=rs;
    elsif falling_edge(e) then
      assert now-rise_at>=1 us report "E pulse too short" severity failure;
      assert db=rise_data and rs=rise_rs report "Data changed during E pulse" severity failure;
      if rs='0' then
        if db(7)='1' then cg:=false;
        elsif db(6)='1' then cg:=true; addr:=to_integer(unsigned(db(5 downto 0))); end if;
      elsif cg then
        cgram(addr)<=db; addr:=(addr+1) mod 64;
      end if;
    end if;
  end process;
  stimulus: process
    procedure send_byte(v : natural) is
      variable b : unsigned(7 downto 0);
    begin
      b:=to_unsigned(v,8); rx<='0'; wait for BT;
      for i in 0 to 7 loop rx<=b(i); wait for BT; end loop;
      rx<='1'; wait for BT;
    end procedure;
    procedure packet(pattern : natural; corrupt : boolean := false) is
      variable sum : natural := 0;
    begin
      send_byte(255);
      for i in 0 to 63 loop send_byte(pattern); sum:=sum+pattern; end loop;
      for i in 0 to 11 loop send_byte(32); sum:=sum+32; end loop;
      if corrupt then sum:=sum+1; end if;
      send_byte(sum mod 256);
    end procedure;
    procedure expect(pattern : natural) is
    begin
      for i in 0 to 63 loop
        assert unsigned(cgram(i))=pattern report "CGRAM mismatch at " & integer'image(i) severity failure;
      end loop;
    end procedure;
  begin
    wait for 1 us; rst<='0'; wait for 110 ms;
    packet(21); wait for 20 ms; expect(21);
    packet(10,true); wait for 20 ms; expect(21);
    send_byte(255); send_byte(3); send_byte(7); -- abandoned packet
    packet(10); wait for 20 ms; expect(10);
    report "PASS: UART reception, checksum rejection, packet resync, CGRAM and E timing" severity note;
    stop; wait;
  end process;
  watchdog: process begin wait for 300 ms; assert false report "Test timed out" severity failure; end process;
end;
