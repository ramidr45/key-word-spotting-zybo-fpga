--------------------------------------------------------------------------------
-- audio_fifo.vhd
-- FIFO synchrone (BRAM inferree), lecture registree (latence 1 cycle).
-- 8192 x 32 bits = 8 BRAM36 -> ~170 ms de tampon a 48 kHz.
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity audio_fifo is
  generic (
    G_AW : integer := 13;   -- profondeur = 2**G_AW
    G_DW : integer := 32
  );
  port (
    clk   : in  std_logic;
    clr   : in  std_logic;
    wr_en : in  std_logic;
    din   : in  std_logic_vector(G_DW-1 downto 0);
    rd_en : in  std_logic;
    dout  : out std_logic_vector(G_DW-1 downto 0);
    empty : out std_logic;
    full  : out std_logic;
    level : out std_logic_vector(G_AW downto 0)
  );
end entity;

architecture rtl of audio_fifo is
  type t_mem is array (0 to 2**G_AW - 1) of std_logic_vector(G_DW-1 downto 0);
  signal mem    : t_mem;
  attribute ram_style : string;
  attribute ram_style of mem : signal is "block";
  signal wp, rp : unsigned(G_AW downto 0) := (others => '0');
  signal cnt    : unsigned(G_AW downto 0);
  signal dout_r : std_logic_vector(G_DW-1 downto 0) := (others => '0');
  signal full_i, empty_i : std_logic;
begin
  cnt     <= wp - rp;
  full_i  <= '1' when cnt(G_AW) = '1' else '0';
  empty_i <= '1' when cnt = 0 else '0';
  full    <= full_i;
  empty   <= empty_i;
  level   <= std_logic_vector(cnt);
  dout    <= dout_r;

  -- port d'ecriture
  process (clk)
  begin
    if rising_edge(clk) then
      if wr_en = '1' and full_i = '0' then
        mem(to_integer(wp(G_AW-1 downto 0))) <= din;
      end if;
    end if;
  end process;

  -- port de lecture (registre) + pointeurs
  process (clk)
  begin
    if rising_edge(clk) then
      dout_r <= mem(to_integer(rp(G_AW-1 downto 0)));
      if clr = '1' then
        wp <= (others => '0');
        rp <= (others => '0');
      else
        if wr_en = '1' and full_i = '0' then
          wp <= wp + 1;
        end if;
        if rd_en = '1' and empty_i = '0' then
          rp <= rp + 1;
        end if;
      end if;
    end if;
  end process;
end architecture;
