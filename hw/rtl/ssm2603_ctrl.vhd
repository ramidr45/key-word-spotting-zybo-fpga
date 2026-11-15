--------------------------------------------------------------------------------
-- ssm2603_ctrl.vhd
-- Sequenceur de configuration du codec SSM2603 (Zybo Z7) via I2C.
-- Adresse I2C 7 bits = 0x1A  -> octet d'ecriture 0x34
-- Chaque registre : octet1 = (reg << 1) | data[8], octet2 = data[7:0]
--
-- Configuration : micro (jack rose MIC IN, boost 20 dB) ou entree ligne (jack bleu
-- LINE IN, 0 dB) selon line_in, ADC + DAC actifs,
-- I2S 24 bits, codec MAITRE (genere BCLK / LRCLK), 48 kHz avec MCLK 12.288 MHz,
-- sortie casque active (pour le bouclage micro -> casque).
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity ssm2603_ctrl is
  generic (
    G_CLK_HZ     : integer := 100000000;
    G_I2C_HZ     : integer := 100000;
    G_MS_CYCLES  : integer := 100000      -- nb de cycles d'horloge pour 1 ms (reduit en simulation)
  );
  port (
    clk        : in  std_logic;
    rst        : in  std_logic;
    enable     : in  std_logic;   -- demarre la config quand '1' (ex : MCLK verrouillee)
    reinit     : in  std_logic;   -- impulsion : refaire toute la configuration
    line_in    : in  std_logic;   -- '0' : micro (jack rose), '1' : entree ligne (jack bleu)
    init_done  : out std_logic;
    i2c_err    : out std_logic;   -- collant : au moins un NACK pendant la config
    scl_t      : out std_logic;
    sda_t      : out std_logic;
    sda_i      : in  std_logic
  );
end entity;

architecture rtl of ssm2603_ctrl is

  constant C_DEV_ADDR_W : std_logic_vector(7 downto 0) := x"34";

  -- entree ROM : bit 16 = '1' -> attente de N ms (N = bits 15:0)
  --              sinon bits 15:9 = registre, bits 8:0 = donnee
  type t_rom is array (natural range <>) of std_logic_vector(16 downto 0);
  function W(reg : integer; data : integer) return std_logic_vector is
  begin
    return '0' & std_logic_vector(to_unsigned(reg, 7)) & std_logic_vector(to_unsigned(data, 9));
  end function;
  function WAIT_MS(ms : integer) return std_logic_vector is
  begin
    return '1' & std_logic_vector(to_unsigned(ms, 16));
  end function;

  constant C_ROM : t_rom := (
    W(16#0F#, 16#000#),  -- R15 : reset logiciel
    WAIT_MS(5),
    W(16#06#, 16#071#),  -- R6  : alim : LINEIN off, MIC/ADC/DAC on, OUT off (pour l'instant), OSC/CLKOUT off
    W(16#00#, 16#117#),  -- R0  : volume entree ligne G+D 0 dB (non utilise avec le micro)
    W(16#02#, 16#179#),  -- R2  : volume casque G+D 0 dB
    W(16#04#, 16#015#),  -- R4  : chemin analogique : MICBOOST=1, MUTEMIC=0, INSEL=micro, DACSEL=1
    W(16#05#, 16#000#),  -- R5  : chemin numerique : filtre passe-haut ADC actif, DAC non muet
    W(16#07#, 16#04A#),  -- R7  : interface : I2S, 24 bits, MAITRE
    W(16#08#, 16#000#),  -- R8  : 48 kHz ADC/DAC, MCLK = 12.288 MHz, BOSR=0
    WAIT_MS(80),         --       charge de VMID (condensateur) avant activation
    W(16#09#, 16#001#),  -- R9  : ACTIVE = 1
    W(16#06#, 16#061#)   -- R6  : sortie casque alimentee
  );

  type t_state is (S_WAIT_EN, S_FETCH, S_I2C_START, S_I2C_WAIT, S_DELAY, S_DONE);
  signal state     : t_state := S_WAIT_EN;
  signal idx       : integer range 0 to C_ROM'length := 0;
  signal entry     : std_logic_vector(16 downto 0);
  signal ms_cnt    : integer range 0 to 65535 := 0;
  signal cyc_cnt   : integer range 0 to G_MS_CYCLES := 0;
  signal i2c_start : std_logic := '0';
  signal i2c_busy  : std_logic;
  signal i2c_done  : std_logic;
  signal i2c_nack  : std_logic;
  signal b1, b2    : std_logic_vector(7 downto 0) := (others => '0');
  signal err_r     : std_logic := '0';
  signal done_r    : std_logic := '0';
  signal pwr_cnt   : integer range 0 to G_MS_CYCLES := 0;
  signal pwr_ms    : integer range 0 to 20 := 0;
  signal line_r    : std_logic := '0';

  -- adapte une entree ROM a l'entree choisie (R4 chemin analogique, R6 alimentation)
  function adapt(e : std_logic_vector(16 downto 0); line : std_logic) return std_logic_vector is
    variable v : std_logic_vector(16 downto 0) := e;
  begin
    if line = '1' and e(16) = '0' then
      if unsigned(e(15 downto 9)) = 4 then
        v(8 downto 0) := "000010010";      -- R4 = 0x012 : INSEL=ligne, MUTEMIC=1, DACSEL=1
      elsif unsigned(e(15 downto 9)) = 6 then
        v(0) := '0';                       -- R6 : LINEIN alimentee
      end if;
    end if;
    return v;
  end function;
begin

  init_done <= done_r;
  i2c_err   <= err_r;

  u_i2c : entity work.i2c_master
    generic map (G_CLK_HZ => G_CLK_HZ, G_I2C_HZ => G_I2C_HZ)
    port map (
      clk => clk, rst => rst, start => i2c_start,
      byte0 => C_DEV_ADDR_W, byte1 => b1, byte2 => b2,
      busy => i2c_busy, done => i2c_done, ack_err => i2c_nack,
      scl_t => scl_t, sda_t => sda_t, sda_i => sda_i
    );

  process (clk)
    variable ev : std_logic_vector(16 downto 0);
  begin
    if rising_edge(clk) then
      i2c_start <= '0';
      if rst = '1' or reinit = '1' then
        state   <= S_WAIT_EN;
        idx     <= 0;
        done_r  <= '0';
        err_r   <= '0';
        pwr_cnt <= 0;
        pwr_ms  <= 0;
      else
        case state is
          when S_WAIT_EN =>
            -- attend enable puis ~10 ms de stabilisation (alim / MCLK)
            line_r <= line_in;
            if enable = '1' then
              if pwr_cnt = G_MS_CYCLES - 1 then
                pwr_cnt <= 0;
                if pwr_ms = 10 then
                  state <= S_FETCH;
                else
                  pwr_ms <= pwr_ms + 1;
                end if;
              else
                pwr_cnt <= pwr_cnt + 1;
              end if;
            else
              pwr_cnt <= 0;
              pwr_ms  <= 0;
            end if;

          when S_FETCH =>
            if idx = C_ROM'length then
              state <= S_DONE;
            else
              ev    := adapt(C_ROM(idx), line_r);
              entry <= ev;
              idx   <= idx + 1;
              if ev(16) = '1' then
                ms_cnt  <= to_integer(unsigned(ev(15 downto 0)));
                cyc_cnt <= 0;
                state   <= S_DELAY;
              else
                b1    <= ev(15 downto 8);  -- reg(6:0) & data(8)
                b2    <= ev(7 downto 0);
                state <= S_I2C_START;
              end if;
            end if;

          when S_I2C_START =>
            i2c_start <= '1';
            state     <= S_I2C_WAIT;

          when S_I2C_WAIT =>
            if i2c_done = '1' then
              if i2c_nack = '1' then
                err_r <= '1';
              end if;
              state <= S_FETCH;
            end if;

          when S_DELAY =>
            if ms_cnt = 0 then
              state <= S_FETCH;
            elsif cyc_cnt = G_MS_CYCLES - 1 then
              cyc_cnt <= 0;
              ms_cnt  <= ms_cnt - 1;
            else
              cyc_cnt <= cyc_cnt + 1;
            end if;

          when S_DONE =>
            done_r <= '1';
        end case;
      end if;
    end if;
  end process;

end architecture;
