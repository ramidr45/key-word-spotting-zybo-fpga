--------------------------------------------------------------------------------
-- i2s_rx.vhd
-- Recepteur I2S (codec maitre). BCLK/LRCLK/DATA sont SURECHANTILLONNES dans le
-- domaine clk (100 MHz) : pas de domaine d'horloge BCLK, pas de FIFO asynchrone.
-- BCLK = 3.072 MHz (48 kHz x 64) -> ~32 cycles clk par periode BCLK.
-- Format I2S : MSB un BCLK apres le front de LRCLK, LRCLK bas = gauche.
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity i2s_rx is
  generic (
    G_BITS : integer := 24
  );
  port (
    clk      : in  std_logic;
    rst      : in  std_logic;
    bclk     : in  std_logic;   -- broches brutes (asynchrones)
    lrclk    : in  std_logic;
    sdata    : in  std_logic;
    sdata_s  : out std_logic;   -- donnee resynchronisee (pour le bouclage vers le DAC)
    left     : out std_logic_vector(G_BITS-1 downto 0);
    right    : out std_logic_vector(G_BITS-1 downto 0);
    valid    : out std_logic    -- impulsion 1 cycle : une trame G+D complete
  );
end entity;

architecture rtl of i2s_rx is
  signal bclk_sr  : std_logic_vector(2 downto 0) := (others => '0');
  signal lr_sr    : std_logic_vector(1 downto 0) := (others => '0');
  signal dat_sr   : std_logic_vector(1 downto 0) := (others => '0');
  attribute ASYNC_REG : string;
  attribute ASYNC_REG of bclk_sr : signal is "TRUE";
  attribute ASYNC_REG of lr_sr   : signal is "TRUE";
  attribute ASYNC_REG of dat_sr  : signal is "TRUE";

  signal lr_prev  : std_logic := '0';
  signal cnt      : integer range 0 to G_BITS := G_BITS;
  signal shreg    : std_logic_vector(G_BITS-1 downto 0) := (others => '0');
  signal left_r   : std_logic_vector(G_BITS-1 downto 0) := (others => '0');
  signal right_r  : std_logic_vector(G_BITS-1 downto 0) := (others => '0');
  signal valid_r  : std_logic := '0';
begin

  left    <= left_r;
  right   <= right_r;
  valid   <= valid_r;
  sdata_s <= dat_sr(1);

  process (clk)
    variable sh : std_logic_vector(G_BITS-1 downto 0);
  begin
    if rising_edge(clk) then
      bclk_sr <= bclk_sr(1 downto 0) & bclk;
      lr_sr   <= lr_sr(0) & lrclk;
      dat_sr  <= dat_sr(0) & sdata;
      valid_r <= '0';

      if rst = '1' then
        cnt     <= G_BITS;
        lr_prev <= '0';
      elsif bclk_sr(2) = '0' and bclk_sr(1) = '1' then      -- front montant de BCLK
        if lr_sr(1) /= lr_prev then
          lr_prev <= lr_sr(1);                               -- nouveau canal : bit de retard I2S
          cnt     <= 0;
        elsif cnt < G_BITS then
          sh    := shreg(G_BITS-2 downto 0) & dat_sr(1);
          shreg <= sh;
          cnt   <= cnt + 1;
          if cnt = G_BITS - 1 then                           -- dernier bit du mot
            if lr_prev = '0' then
              left_r <= sh;
            else
              right_r <= sh;
              valid_r <= '1';                                -- trame complete apres le canal droit
            end if;
          end if;
        end if;
      end if;
    end if;
  end process;

end architecture;
