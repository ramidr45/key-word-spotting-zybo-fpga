--------------------------------------------------------------------------------
-- i2c_master.vhd
-- Maitre I2C minimal (ecriture seule) : envoie 3 octets [adresse, b1, b2]
-- Sorties en drain ouvert : *_t = '1' => ligne relachee (pull-up), '0' => tiree a 0
-- Projet : Keyword Spotting sur Zybo Z7-10 (codec SSM2603)
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity i2c_master is
  generic (
    G_CLK_HZ : integer := 100000000;
    G_I2C_HZ : integer := 100000
  );
  port (
    clk     : in  std_logic;
    rst     : in  std_logic;                     -- actif haut, synchrone
    start   : in  std_logic;                     -- impulsion : lance une transaction
    byte0   : in  std_logic_vector(7 downto 0);  -- adresse 7 bits + R/W
    byte1   : in  std_logic_vector(7 downto 0);
    byte2   : in  std_logic_vector(7 downto 0);
    busy    : out std_logic;
    done    : out std_logic;                     -- impulsion fin de transaction
    ack_err : out std_logic;                     -- '1' si un NACK a ete recu (valide avec done)
    scl_t   : out std_logic;
    sda_t   : out std_logic;
    sda_i   : in  std_logic
  );
end entity;

architecture rtl of i2c_master is
  constant C_QDIV : integer := G_CLK_HZ / (4 * G_I2C_HZ);  -- 1/4 de periode SCL

  type t_state is (S_IDLE, S_START, S_BIT, S_STOP, S_DONE);
  signal state    : t_state := S_IDLE;
  signal div_cnt  : integer range 0 to C_QDIV := 0;
  signal tick     : std_logic := '0';
  signal phase    : unsigned(1 downto 0) := (others => '0');
  signal bit_cnt  : integer range 0 to 8 := 0;   -- 0..7 : donnees MSB d'abord, 8 : ACK
  signal byte_sel : integer range 0 to 2 := 0;
  signal shreg    : std_logic_vector(7 downto 0) := (others => '0');
  signal b1_r     : std_logic_vector(7 downto 0) := (others => '0');
  signal b2_r     : std_logic_vector(7 downto 0) := (others => '0');
  signal scl_r    : std_logic := '1';
  signal sda_r    : std_logic := '1';
  signal err_r    : std_logic := '0';
  signal done_r   : std_logic := '0';
  signal sda_s    : std_logic_vector(1 downto 0) := "11";
begin

  scl_t   <= scl_r;
  sda_t   <= sda_r;
  busy    <= '0' when state = S_IDLE else '1';
  done    <= done_r;
  ack_err <= err_r;

  -- generateur de tick (4 ticks par periode SCL)
  process (clk)
  begin
    if rising_edge(clk) then
      tick <= '0';
      if rst = '1' or state = S_IDLE then
        div_cnt <= 0;
      elsif div_cnt = C_QDIV - 1 then
        div_cnt <= 0;
        tick    <= '1';
      else
        div_cnt <= div_cnt + 1;
      end if;
      sda_s <= sda_s(0) & sda_i;
    end if;
  end process;

  process (clk)
  begin
    if rising_edge(clk) then
      done_r <= '0';
      if rst = '1' then
        state <= S_IDLE;
        scl_r <= '1';
        sda_r <= '1';
        err_r <= '0';
        phase <= (others => '0');
      else
        case state is
          when S_IDLE =>
            scl_r <= '1';
            sda_r <= '1';
            phase <= (others => '0');
            if start = '1' then
              shreg    <= byte0;
              b1_r     <= byte1;
              b2_r     <= byte2;
              byte_sel <= 0;
              bit_cnt  <= 0;
              err_r    <= '0';
              state    <= S_START;
            end if;

          when S_START =>
            if tick = '1' then
              phase <= phase + 1;
              case phase is
                when "00" => sda_r <= '1'; scl_r <= '1';
                when "01" => sda_r <= '0';                  -- START : SDA descend, SCL haut
                when "10" => scl_r <= '0';
                when others =>
                  phase <= (others => '0');
                  state <= S_BIT;
              end case;
            end if;

          when S_BIT =>
            if tick = '1' then
              phase <= phase + 1;
              case phase is
                when "00" =>                               -- SCL bas : on pose la donnee
                  scl_r <= '0';
                  if bit_cnt = 8 then
                    sda_r <= '1';                          -- relache pour l'ACK esclave
                  else
                    sda_r <= shreg(7);
                  end if;
                when "01" =>
                  scl_r <= '1';
                when "10" =>                               -- milieu du niveau haut : echantillonnage
                  if bit_cnt = 8 and sda_s(1) = '1' then
                    err_r <= '1';
                  end if;
                when others =>
                  scl_r <= '0';
                  if bit_cnt = 8 then
                    bit_cnt <= 0;
                    if byte_sel = 0 then
                      byte_sel <= 1; shreg <= b1_r;
                    elsif byte_sel = 1 then
                      byte_sel <= 2; shreg <= b2_r;
                    else
                      state <= S_STOP;
                    end if;
                  else
                    bit_cnt <= bit_cnt + 1;
                    shreg   <= shreg(6 downto 0) & '0';
                  end if;
              end case;
            end if;

          when S_STOP =>
            if tick = '1' then
              phase <= phase + 1;
              case phase is
                when "00" => scl_r <= '0'; sda_r <= '0';
                when "01" => scl_r <= '1';
                when "10" => sda_r <= '1';                  -- STOP : SDA monte, SCL haut
                when others =>
                  phase <= (others => '0');
                  state <= S_DONE;
              end case;
            end if;

          when S_DONE =>
            done_r <= '1';
            state  <= S_IDLE;
        end case;
      end if;
    end if;
  end process;

end architecture;
