--------------------------------------------------------------------------------
-- kws_audio_axi.vhd
-- Peripherique AXI4-Lite "audio" pour le Keyword Spotting sur Zybo Z7-10.
--   * configuration du codec SSM2603 (I2C)        -> ssm2603_ctrl
--   * reception I2S 24 bits 48 kHz (codec maitre)  -> i2s_rx
--   * FIFO 8192 x 32 lue par l'ARM                 -> audio_fifo
--   * LEDs / RGB / switchs / boutons
--   * bouclage micro -> casque (SW0 ou CTRL bit 3) pour tester l'analogique sans logiciel
--
-- Carte des registres (base 0x43C0_0000) :
--   0x00 CTRL    RW  b0 capture_en, b1 fifo_clear (W1, auto), b2 codec_reinit (W1, auto),
--                    b3 loopback, b5:4 canal (00 gauche, 01 droite, 10 moyenne G+D),
--                    b6 entree : 0 micro (rose), 1 ligne (bleu) -- prise en compte au reinit
--   0x04 STATUS  RO  b0 init_done, b1 i2c_err, b2 overflow (collant, efface par fifo_clear),
--                    b3 empty, b4 full, b5 mclk_locked, b29:16 niveau FIFO
--   0x08 DATA    RO  lecture = depile un echantillon (24 bits signe, etendu sur 32)
--   0x0C FRAMES  RO  nombre de trames I2S recues depuis le reset
--   0x10 LEDS    RW  b3:0 LD3..LD0, b6:4 RGB (R,G,B), b31 = 1 : le logiciel pilote les LEDs
--   0x14 VERSION RO  0x4B575331 ("KWS1")
--   0x18 LAST    RO  dernier echantillon gauche (signe)
--   0x1C INPUTS  RO  b3:0 switchs, b7:4 boutons
--   0x20 THRESH  RW  seuil d'activite audio (LD3 en mode materiel)
--   0x24 LEVEL   RO  niveau FIFO
--
-- LEDs en mode materiel (LEDS b31 = 0, etat apres programmation du FPGA) :
--   LD0 = battement de coeur, LD1 = codec configure, LD2 = erreur I2C, LD3 = activite micro
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity kws_audio_axi is
  generic (
    G_CLK_HZ    : integer := 100000000;
    G_I2C_HZ    : integer := 100000;
    G_MS_CYCLES : integer := 100000;
    G_FIFO_AW   : integer := 13
  );
  port (
    -- AXI4-Lite esclave
    s_axi_aclk    : in  std_logic;
    s_axi_aresetn : in  std_logic;
    s_axi_awaddr  : in  std_logic_vector(7 downto 0);
    s_axi_awprot  : in  std_logic_vector(2 downto 0);
    s_axi_awvalid : in  std_logic;
    s_axi_awready : out std_logic;
    s_axi_wdata   : in  std_logic_vector(31 downto 0);
    s_axi_wstrb   : in  std_logic_vector(3 downto 0);
    s_axi_wvalid  : in  std_logic;
    s_axi_wready  : out std_logic;
    s_axi_bresp   : out std_logic_vector(1 downto 0);
    s_axi_bvalid  : out std_logic;
    s_axi_bready  : in  std_logic;
    s_axi_araddr  : in  std_logic_vector(7 downto 0);
    s_axi_arprot  : in  std_logic_vector(2 downto 0);
    s_axi_arvalid : in  std_logic;
    s_axi_arready : out std_logic;
    s_axi_rdata   : out std_logic_vector(31 downto 0);
    s_axi_rresp   : out std_logic_vector(1 downto 0);
    s_axi_rvalid  : out std_logic;
    s_axi_rready  : in  std_logic;
    -- codec
    mclk_locked   : in  std_logic;
    ac_bclk       : in  std_logic;
    ac_reclrc     : in  std_logic;
    ac_recdat     : in  std_logic;
    ac_pbdat      : out std_logic;
    ac_muten      : out std_logic;
    ac_scl_t      : out std_logic;
    ac_sda_t      : out std_logic;
    ac_sda_i      : in  std_logic;
    -- carte
    led           : out std_logic_vector(3 downto 0);
    rgb           : out std_logic_vector(2 downto 0);  -- 2:R 1:G 0:B
    sw            : in  std_logic_vector(3 downto 0);
    btn           : in  std_logic_vector(3 downto 0)
  );

  -- inference de l'interface AXI dans le Block Design (module reference)
  attribute X_INTERFACE_INFO : string;
  attribute X_INTERFACE_PARAMETER : string;
  attribute X_INTERFACE_INFO of s_axi_aclk    : signal is "xilinx.com:signal:clock:1.0 s_axi_aclk CLK";
  attribute X_INTERFACE_PARAMETER of s_axi_aclk : signal is "ASSOCIATED_BUSIF S_AXI, ASSOCIATED_RESET s_axi_aresetn";
  attribute X_INTERFACE_INFO of s_axi_aresetn : signal is "xilinx.com:signal:reset:1.0 s_axi_aresetn RST";
  attribute X_INTERFACE_PARAMETER of s_axi_aresetn : signal is "POLARITY ACTIVE_LOW";
  attribute X_INTERFACE_INFO of s_axi_awaddr  : signal is "xilinx.com:interface:aximm:1.0 S_AXI AWADDR";
  attribute X_INTERFACE_PARAMETER of s_axi_awaddr : signal is "PROTOCOL AXI4LITE, DATA_WIDTH 32, ADDR_WIDTH 8";
  attribute X_INTERFACE_INFO of s_axi_awprot  : signal is "xilinx.com:interface:aximm:1.0 S_AXI AWPROT";
  attribute X_INTERFACE_INFO of s_axi_awvalid : signal is "xilinx.com:interface:aximm:1.0 S_AXI AWVALID";
  attribute X_INTERFACE_INFO of s_axi_awready : signal is "xilinx.com:interface:aximm:1.0 S_AXI AWREADY";
  attribute X_INTERFACE_INFO of s_axi_wdata   : signal is "xilinx.com:interface:aximm:1.0 S_AXI WDATA";
  attribute X_INTERFACE_INFO of s_axi_wstrb   : signal is "xilinx.com:interface:aximm:1.0 S_AXI WSTRB";
  attribute X_INTERFACE_INFO of s_axi_wvalid  : signal is "xilinx.com:interface:aximm:1.0 S_AXI WVALID";
  attribute X_INTERFACE_INFO of s_axi_wready  : signal is "xilinx.com:interface:aximm:1.0 S_AXI WREADY";
  attribute X_INTERFACE_INFO of s_axi_bresp   : signal is "xilinx.com:interface:aximm:1.0 S_AXI BRESP";
  attribute X_INTERFACE_INFO of s_axi_bvalid  : signal is "xilinx.com:interface:aximm:1.0 S_AXI BVALID";
  attribute X_INTERFACE_INFO of s_axi_bready  : signal is "xilinx.com:interface:aximm:1.0 S_AXI BREADY";
  attribute X_INTERFACE_INFO of s_axi_araddr  : signal is "xilinx.com:interface:aximm:1.0 S_AXI ARADDR";
  attribute X_INTERFACE_INFO of s_axi_arprot  : signal is "xilinx.com:interface:aximm:1.0 S_AXI ARPROT";
  attribute X_INTERFACE_INFO of s_axi_arvalid : signal is "xilinx.com:interface:aximm:1.0 S_AXI ARVALID";
  attribute X_INTERFACE_INFO of s_axi_arready : signal is "xilinx.com:interface:aximm:1.0 S_AXI ARREADY";
  attribute X_INTERFACE_INFO of s_axi_rdata   : signal is "xilinx.com:interface:aximm:1.0 S_AXI RDATA";
  attribute X_INTERFACE_INFO of s_axi_rresp   : signal is "xilinx.com:interface:aximm:1.0 S_AXI RRESP";
  attribute X_INTERFACE_INFO of s_axi_rvalid  : signal is "xilinx.com:interface:aximm:1.0 S_AXI RVALID";
  attribute X_INTERFACE_INFO of s_axi_rready  : signal is "xilinx.com:interface:aximm:1.0 S_AXI RREADY";
end entity;

architecture rtl of kws_audio_axi is

  constant C_VERSION : std_logic_vector(31 downto 0) := x"4B575331";

  alias clk : std_logic is s_axi_aclk;
  signal rst : std_logic;

  -- registres
  signal ctrl_capture  : std_logic := '0';
  signal ctrl_loop     : std_logic := '0';
  signal ctrl_chan     : std_logic_vector(1 downto 0) := "00";
  signal ctrl_line     : std_logic := '0';
  signal fifo_clr_p    : std_logic := '0';
  signal reinit_p      : std_logic := '0';
  signal leds_reg      : std_logic_vector(31 downto 0) := (others => '0');
  signal thresh_reg    : unsigned(23 downto 0) := to_unsigned(16#040000#, 24);
  signal overflow      : std_logic := '0';
  signal frames        : unsigned(31 downto 0) := (others => '0');

  -- codec / audio
  signal init_done, i2c_err : std_logic;
  signal scl_t_i, sda_t_i   : std_logic;
  signal rec_s       : std_logic;
  signal s_left      : std_logic_vector(23 downto 0);
  signal s_right     : std_logic_vector(23 downto 0);
  signal s_valid     : std_logic;
  signal sample_sel  : signed(24 downto 0);
  signal last_left   : std_logic_vector(31 downto 0) := (others => '0');
  signal locked_s    : std_logic_vector(1 downto 0) := "00";

  -- FIFO
  signal fifo_wr, fifo_rd, fifo_clr : std_logic;
  signal fifo_din, fifo_dout : std_logic_vector(31 downto 0);
  signal fifo_empty, fifo_full, empty_d, fifo_ok : std_logic;
  signal fifo_level : std_logic_vector(G_FIFO_AW downto 0);

  -- AXI
  type t_rstate is (R_IDLE, R_WAIT, R_POP, R_RESP);
  signal rstate      : t_rstate := R_IDLE;
  signal raddr       : std_logic_vector(7 downto 0) := (others => '0');
  signal arready_r   : std_logic := '0';
  signal rvalid_r    : std_logic := '0';
  signal rdata_r     : std_logic_vector(31 downto 0) := (others => '0');
  signal awready_r   : std_logic := '0';
  signal wready_r    : std_logic := '0';
  signal bvalid_r    : std_logic := '0';
  signal pop_p       : std_logic := '0';

  -- LEDs / entrees
  signal hb_cnt      : unsigned(26 downto 0) := (others => '0');
  signal act_cnt     : unsigned(23 downto 0) := (others => '0');
  signal act_led     : std_logic;
  signal sw_s, btn_s : std_logic_vector(3 downto 0) := (others => '0');
  signal sw_m, btn_m : std_logic_vector(3 downto 0) := (others => '0');
  attribute ASYNC_REG : string;
  attribute ASYNC_REG of sw_m  : signal is "TRUE";
  attribute ASYNC_REG of sw_s  : signal is "TRUE";
  attribute ASYNC_REG of btn_m : signal is "TRUE";
  attribute ASYNC_REG of btn_s : signal is "TRUE";
  attribute ASYNC_REG of locked_s : signal is "TRUE";

  function sext32(v : std_logic_vector(23 downto 0)) return std_logic_vector is
  begin
    return std_logic_vector(resize(signed(v), 32));
  end function;

begin

  rst <= not s_axi_aresetn;

  ------------------------------------------------------------------------------
  -- codec : configuration I2C
  ------------------------------------------------------------------------------
  process (clk)
  begin
    if rising_edge(clk) then
      locked_s <= locked_s(0) & mclk_locked;
      sw_m  <= sw;   sw_s  <= sw_m;
      btn_m <= btn;  btn_s <= btn_m;
    end if;
  end process;

  u_ctrl : entity work.ssm2603_ctrl
    generic map (G_CLK_HZ => G_CLK_HZ, G_I2C_HZ => G_I2C_HZ, G_MS_CYCLES => G_MS_CYCLES)
    port map (
      clk => clk, rst => rst, enable => locked_s(1), reinit => reinit_p, line_in => ctrl_line,
      init_done => init_done, i2c_err => i2c_err,
      scl_t => scl_t_i, sda_t => sda_t_i, sda_i => ac_sda_i
    );
  ac_scl_t <= scl_t_i;
  ac_sda_t <= sda_t_i;
  ac_muten <= '1';                     -- MUTEN actif bas : '1' = son actif

  ------------------------------------------------------------------------------
  -- reception I2S
  ------------------------------------------------------------------------------
  u_i2s : entity work.i2s_rx
    generic map (G_BITS => 24)
    port map (
      clk => clk, rst => rst,
      bclk => ac_bclk, lrclk => ac_reclrc, sdata => ac_recdat,
      sdata_s => rec_s, left => s_left, right => s_right, valid => s_valid
    );

  -- bouclage micro -> casque (meme BCLK/LRCLK, codec maitre)
  ac_pbdat <= rec_s when (ctrl_loop = '1' or sw_s(0) = '1') else '0';

  -- choix du canal
  sample_sel <= resize(signed(s_right), 25) when ctrl_chan = "01" else
                shift_right(resize(signed(s_left), 25) + resize(signed(s_right), 25), 1) when ctrl_chan = "10" else
                resize(signed(s_left), 25);

  fifo_din <= std_logic_vector(resize(sample_sel(23 downto 0), 32));
  fifo_wr  <= s_valid and ctrl_capture;
  fifo_clr <= fifo_clr_p or rst;

  u_fifo : entity work.audio_fifo
    generic map (G_AW => G_FIFO_AW, G_DW => 32)
    port map (
      clk => clk, clr => fifo_clr, wr_en => fifo_wr, din => fifo_din,
      rd_en => fifo_rd, dout => fifo_dout, empty => fifo_empty, full => fifo_full,
      level => fifo_level
    );
  fifo_rd <= pop_p;
  fifo_ok <= (not fifo_empty) and (not empty_d);

  process (clk)
  begin
    if rising_edge(clk) then
      empty_d <= fifo_empty;
      if rst = '1' then
        frames   <= (others => '0');
        overflow <= '0';
      else
        if s_valid = '1' then
          frames    <= frames + 1;
          last_left <= sext32(s_left);
        end if;
        if fifo_clr_p = '1' then
          overflow <= '0';
        elsif fifo_wr = '1' and fifo_full = '1' then
          overflow <= '1';
        end if;
      end if;
    end if;
  end process;

  ------------------------------------------------------------------------------
  -- AXI4-Lite : ecriture
  ------------------------------------------------------------------------------
  s_axi_awready <= awready_r;
  s_axi_wready  <= wready_r;
  s_axi_bvalid  <= bvalid_r;
  s_axi_bresp   <= "00";

  process (clk)
    variable a : integer range 0 to 63;
  begin
    if rising_edge(clk) then
      awready_r  <= '0';
      wready_r   <= '0';
      fifo_clr_p <= '0';
      reinit_p   <= '0';
      if rst = '1' then
        bvalid_r     <= '0';
        ctrl_capture <= '0';
        ctrl_loop    <= '0';
        ctrl_chan    <= "00";
        ctrl_line    <= '0';
        leds_reg     <= (others => '0');
        thresh_reg   <= to_unsigned(16#040000#, 24);
      else
        if bvalid_r = '1' and s_axi_bready = '1' then
          bvalid_r <= '0';
        end if;
        if s_axi_awvalid = '1' and s_axi_wvalid = '1' and awready_r = '0' and bvalid_r = '0' then
          awready_r <= '1';
          wready_r  <= '1';
          bvalid_r  <= '1';
          a := to_integer(unsigned(s_axi_awaddr(7 downto 2)));
          case a is
            when 0 =>
              ctrl_capture <= s_axi_wdata(0);
              fifo_clr_p   <= s_axi_wdata(1);
              reinit_p     <= s_axi_wdata(2);
              ctrl_loop    <= s_axi_wdata(3);
              ctrl_chan    <= s_axi_wdata(5 downto 4);
              ctrl_line    <= s_axi_wdata(6);
            when 4 =>
              leds_reg <= s_axi_wdata;
            when 8 =>
              thresh_reg <= unsigned(s_axi_wdata(23 downto 0));
            when others => null;
          end case;
        end if;
      end if;
    end if;
  end process;

  ------------------------------------------------------------------------------
  -- AXI4-Lite : lecture (lecture de DATA = depilement)
  ------------------------------------------------------------------------------
  s_axi_arready <= arready_r;
  s_axi_rvalid  <= rvalid_r;
  s_axi_rdata   <= rdata_r;
  s_axi_rresp   <= "00";

  process (clk)
    variable a : integer range 0 to 63;
  begin
    if rising_edge(clk) then
      arready_r <= '0';
      pop_p     <= '0';
      if rst = '1' then
        rstate   <= R_IDLE;
        rvalid_r <= '0';
      else
        case rstate is
          when R_IDLE =>
            if s_axi_arvalid = '1' and arready_r = '0' then
              arready_r <= '1';
              raddr     <= s_axi_araddr;
              rstate    <= R_WAIT;
            end if;
          when R_WAIT =>
            rstate <= R_POP;
          when R_POP =>
            a := to_integer(unsigned(raddr(7 downto 2)));
            case a is
              when 0 => rdata_r <= x"000000" & '0' & ctrl_line & ctrl_chan & ctrl_loop & "00" & ctrl_capture;
              when 1 => rdata_r <= "00" & std_logic_vector(resize(unsigned(fifo_level), 14)) &
                                   "0000000000" & locked_s(1) & fifo_full & fifo_empty &
                                   overflow & i2c_err & init_done;
              when 2 =>
                if fifo_ok = '1' then
                  rdata_r <= fifo_dout;
                  pop_p   <= '1';
                else
                  rdata_r <= (others => '0');
                end if;
              when 3 => rdata_r <= std_logic_vector(frames);
              when 4 => rdata_r <= leds_reg;
              when 5 => rdata_r <= C_VERSION;
              when 6 => rdata_r <= last_left;
              when 7 => rdata_r <= x"000000" & btn_s & sw_s;
              when 8 => rdata_r <= x"00" & std_logic_vector(thresh_reg);
              when 9 => rdata_r <= std_logic_vector(resize(unsigned(fifo_level), 32));
              when others => rdata_r <= (others => '0');
            end case;
            rvalid_r <= '1';
            rstate   <= R_RESP;
          when R_RESP =>
            if s_axi_rready = '1' then
              rvalid_r <= '0';
              rstate   <= R_IDLE;
            end if;
        end case;
      end if;
    end if;
  end process;

  ------------------------------------------------------------------------------
  -- LEDs
  ------------------------------------------------------------------------------
  process (clk)
    variable mag : unsigned(23 downto 0);
  begin
    if rising_edge(clk) then
      hb_cnt <= hb_cnt + 1;
      if s_valid = '1' then
        if s_left(23) = '1' then
          mag := unsigned(not s_left) + 1;
        else
          mag := unsigned(s_left);
        end if;
        if mag > thresh_reg then
          act_cnt <= to_unsigned(10000000, 24);   -- 100 ms
        end if;
      end if;
      if act_cnt /= 0 then
        act_cnt <= act_cnt - 1;
      end if;
    end if;
  end process;

  act_led <= '1' when act_cnt /= 0 else '0';
  led <= leds_reg(3 downto 0) when leds_reg(31) = '1' else
         act_led & i2c_err & init_done & hb_cnt(26);

  -- RGB avec rapport cyclique 1/8 (la LED est tres lumineuse)
  rgb <= leds_reg(4) & leds_reg(5) & leds_reg(6)
           when (leds_reg(31) = '1' and hb_cnt(2 downto 0) = "000") else "000";

end architecture;
