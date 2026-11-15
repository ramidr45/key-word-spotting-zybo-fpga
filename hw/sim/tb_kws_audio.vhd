--------------------------------------------------------------------------------
-- tb_kws_audio.vhd  (VHDL-2008, auto-verifiant)
-- * modele esclave I2C du SSM2603 : acquitte et enregistre les ecritures
-- * modele codec maitre I2S : BCLK 3.072 MHz, LRCLK 48 kHz, mots 24 bits connus
-- * maitre AXI4-Lite : lit STATUS, active la capture, depile la FIFO et verifie
-- Lancement : ./run_sim.sh   (GHDL)  -> affiche "TEST PASSED" ou des erreurs
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb_kws_audio is
end entity;

architecture sim of tb_kws_audio is
  constant TCLK  : time := 10 ns;      -- 100 MHz
  constant TBCLK : time := 326 ns;     -- ~3.072 MHz

  signal clk     : std_logic := '0';
  signal aresetn : std_logic := '0';

  signal awaddr, araddr : std_logic_vector(7 downto 0) := (others => '0');
  signal awvalid, wvalid, bready, arvalid, rready : std_logic := '0';
  signal awready, wready, bvalid, arready, rvalid : std_logic;
  signal wdata, rdata : std_logic_vector(31 downto 0) := (others => '0');
  signal bresp, rresp : std_logic_vector(1 downto 0);

  signal bclk, lrclk, recdat : std_logic := '0';
  signal pbdat, muten : std_logic;
  signal scl_t, sda_t : std_logic;
  signal sda_slave    : std_logic := '1';      -- '0' = l'esclave tire SDA a 0
  signal scl_bus, sda_bus : std_logic;
  signal led : std_logic_vector(3 downto 0);
  signal rgb : std_logic_vector(2 downto 0);
  signal sw  : std_logic_vector(3 downto 0) := "0000";
  signal btn : std_logic_vector(3 downto 0) := "0000";

  -- ecritures attendues (reg, data) -- cf. ssm2603_ctrl
  type t_int_arr is array (natural range <>) of integer;
  -- 10 premieres : configuration micro (au reset) ; 10 suivantes : entree ligne (apres reinit)
  constant EXP_REG  : t_int_arr := (16#0F#, 16#06#, 16#00#, 16#02#, 16#04#, 16#05#, 16#07#, 16#08#, 16#09#, 16#06#,
                                    16#0F#, 16#06#, 16#00#, 16#02#, 16#04#, 16#05#, 16#07#, 16#08#, 16#09#, 16#06#);
  constant EXP_DATA : t_int_arr := (16#000#, 16#071#, 16#117#, 16#179#, 16#015#, 16#000#, 16#04A#, 16#000#, 16#001#, 16#061#,
                                    16#000#, 16#070#, 16#117#, 16#179#, 16#012#, 16#000#, 16#04A#, 16#000#, 16#001#, 16#060#);
  signal i2c_writes : integer := 0;
  signal i2c_errors : integer := 0;

  signal sim_done : boolean := false;

  function left_word(n : integer) return std_logic_vector is
  begin
    return std_logic_vector(to_signed(((n * 37633) mod 8000000) - 4000000, 24));
  end function;
  function right_word(n : integer) return std_logic_vector is
  begin
    return std_logic_vector(to_signed(-(((n * 37633) mod 8000000) - 4000000) / 2, 24));
  end function;
begin

  clk <= not clk after TCLK/2 when not sim_done;

  -- bus I2C drain ouvert avec pull-up
  scl_bus <= '0' when scl_t = '0' else '1';
  sda_bus <= '0' when (sda_t = '0' or sda_slave = '0') else '1';

  dut : entity work.kws_audio_axi
    generic map (G_CLK_HZ => 100000000, G_I2C_HZ => 2500000, G_MS_CYCLES => 50, G_FIFO_AW => 6)
    port map (
      s_axi_aclk => clk, s_axi_aresetn => aresetn,
      s_axi_awaddr => awaddr, s_axi_awprot => "000", s_axi_awvalid => awvalid, s_axi_awready => awready,
      s_axi_wdata => wdata, s_axi_wstrb => "1111", s_axi_wvalid => wvalid, s_axi_wready => wready,
      s_axi_bresp => bresp, s_axi_bvalid => bvalid, s_axi_bready => bready,
      s_axi_araddr => araddr, s_axi_arprot => "000", s_axi_arvalid => arvalid, s_axi_arready => arready,
      s_axi_rdata => rdata, s_axi_rresp => rresp, s_axi_rvalid => rvalid, s_axi_rready => rready,
      mclk_locked => '1',
      ac_bclk => bclk, ac_reclrc => lrclk, ac_recdat => recdat, ac_pbdat => pbdat, ac_muten => muten,
      ac_scl_t => scl_t, ac_sda_t => sda_t, ac_sda_i => sda_bus,
      led => led, rgb => rgb, sw => sw, btn => btn
    );

  ------------------------------------------------------------------------------
  -- esclave I2C (SSM2603, adresse 0x1A)
  ------------------------------------------------------------------------------
  i2c_slave : process
    variable b    : std_logic_vector(7 downto 0);
    variable bytes : t_int_arr(0 to 2);
    variable k    : integer;
  begin
    loop
      -- START : SDA descend pendant que SCL est haut
      wait until falling_edge(sda_bus) and scl_bus = '1';
      for i in 0 to 2 loop
        for j in 7 downto 0 loop
          wait until rising_edge(scl_bus);
          b(j) := sda_bus;
        end loop;
        wait until falling_edge(scl_bus);
        if i = 0 and b /= x"34" then
          report "I2C : mauvaise adresse " & integer'image(to_integer(unsigned(b))) severity error;
          i2c_errors <= i2c_errors + 1;
        end if;
        sda_slave <= '0';                         -- ACK
        wait until falling_edge(scl_bus);
        sda_slave <= '1';
        bytes(i) := to_integer(unsigned(b));
      end loop;
      k := i2c_writes;
      if k <= EXP_REG'high then
        if (bytes(1) / 2) /= EXP_REG(k) or ((bytes(1) mod 2) * 256 + bytes(2)) /= EXP_DATA(k) then
          report "I2C ecriture " & integer'image(k) & " inattendue : reg=" & integer'image(bytes(1)/2) &
                 " data=" & integer'image((bytes(1) mod 2) * 256 + bytes(2)) severity error;
          i2c_errors <= i2c_errors + 1;
        end if;
      end if;
      i2c_writes <= k + 1;
    end loop;
  end process;

  ------------------------------------------------------------------------------
  -- codec maitre I2S : 32 BCLK par canal, LRCLK change sur front descendant
  ------------------------------------------------------------------------------
  i2s_gen : process
    variable w : std_logic_vector(23 downto 0);
    variable n : integer := 0;
  begin
    wait for 1 us;
    while not sim_done loop
      for ch in 0 to 1 loop
        if ch = 0 then w := left_word(n); else w := right_word(n); end if;
        for b in 0 to 31 loop
          -- front descendant : mise a jour LRCLK / donnee
          bclk <= '0';
          if b = 0 then
            lrclk <= '0' when ch = 0 else '1';
          end if;
          if b >= 1 and b <= 24 then
            recdat <= w(24 - b);                  -- MSB au 2e BCLK du canal
          else
            recdat <= '0';
          end if;
          wait for TBCLK/2;
          bclk <= '1';
          wait for TBCLK/2;
        end loop;
      end loop;
      n := n + 1;
    end loop;
    wait;
  end process;

  ------------------------------------------------------------------------------
  -- maitre AXI + verifications
  ------------------------------------------------------------------------------
  stim : process
    procedure axi_write(a : integer; d : std_logic_vector(31 downto 0)) is
    begin
      wait until rising_edge(clk);
      awaddr <= std_logic_vector(to_unsigned(a, 8)); wdata <= d;
      awvalid <= '1'; wvalid <= '1'; bready <= '0';
      wait until rising_edge(clk) and awready = '1';
      awvalid <= '0'; wvalid <= '0'; bready <= '1';
      wait until rising_edge(clk) and bvalid = '1';
      bready <= '0';
    end procedure;
    procedure axi_read(a : integer; variable d : out std_logic_vector(31 downto 0)) is
    begin
      wait until rising_edge(clk);
      araddr <= std_logic_vector(to_unsigned(a, 8)); arvalid <= '1'; rready <= '1';
      wait until rising_edge(clk) and arready = '1';
      arvalid <= '0';
      wait until rising_edge(clk) and rvalid = '1';
      d := rdata;
      rready <= '0';
    end procedure;

    variable d      : std_logic_vector(31 downto 0);
    variable errors : integer := 0;
    variable got    : integer := 0;
    variable first  : integer := -1;
    variable expect : std_logic_vector(31 downto 0);
    variable lvl    : integer;
    variable t0     : time;
  begin
    aresetn <= '0';
    wait for 200 ns;
    aresetn <= '1';

    axi_read(16#14#, d);
    assert d = x"4B575331" report "VERSION incorrecte" severity error;
    if d /= x"4B575331" then errors := errors + 1; end if;

    -- attendre la fin de la configuration du codec
    t0 := now;
    loop
      axi_read(16#04#, d);
      exit when d(0) = '1';
      if now - t0 > 2 ms then
        report "timeout init codec" severity error; errors := errors + 1; exit;
      end if;
      wait for 5 us;
    end loop;
    report "codec configure, ecritures I2C = " & integer'image(i2c_writes);
    if d(1) = '1' then report "i2c_err leve" severity error; errors := errors + 1; end if;
    if i2c_writes /= 10 then
      report "nombre d'ecritures I2C incorrect" severity error; errors := errors + 1;
    end if;
    if led(1) /= '1' then report "LD1 (init_done) eteinte" severity error; errors := errors + 1; end if;

    -- capture canal gauche
    axi_write(16#00#, x"00000003");     -- capture_en + clear
    wait for 400 us;                    -- ~19 trames

    loop
      axi_read(16#24#, d);
      lvl := to_integer(unsigned(d));
      exit when lvl = 0 or got >= 15;
      axi_read(16#08#, d);
      if first < 0 then
        -- retrouve l'indice n de la premiere trame capturee
        for n in 0 to 200 loop
          if std_logic_vector(resize(signed(left_word(n)), 32)) = d then first := n; exit; end if;
        end loop;
        if first < 0 then report "premier echantillon inconnu" severity error; errors := errors + 1; first := 0; end if;
      end if;
      expect := std_logic_vector(resize(signed(left_word(first + got)), 32));
      if d /= expect then
        report "echantillon " & integer'image(got) & " incorrect" severity error;
        errors := errors + 1;
      end if;
      got := got + 1;
    end loop;
    report "echantillons gauche verifies : " & integer'image(got);
    if got < 10 then report "trop peu d'echantillons" severity error; errors := errors + 1; end if;

    -- canal droit
    axi_write(16#00#, x"00000013");
    wait for 200 us;
    axi_read(16#08#, d);
    lvl := -1;
    for n in 0 to 400 loop
      if std_logic_vector(resize(signed(right_word(n)), 32)) = d then lvl := n; exit; end if;
    end loop;
    if lvl < 0 then report "canal droit incorrect" severity error; errors := errors + 1; end if;

    -- overflow : FIFO de 64 en simulation, on attend plus de 64 trames
    wait for 1.6 ms;
    axi_read(16#04#, d);
    if d(2) /= '1' then report "overflow non signale" severity error; errors := errors + 1; end if;
    axi_write(16#00#, x"00000002");     -- clear + capture off
    axi_read(16#04#, d);
    if d(2) /= '0' or d(3) /= '1' then report "clear FIFO inefficace" severity error; errors := errors + 1; end if;

    -- LEDs pilotees par logiciel
    axi_write(16#10#, x"80000005");
    wait for 100 ns;
    if led /= "0101" then report "LEDs logicielles incorrectes" severity error; errors := errors + 1; end if;

    -- bascule sur l'entree ligne + reconfiguration du codec
    axi_write(16#00#, x"00000044");     -- b6 ligne + b2 reinit
    wait for 1 us;
    t0 := now;
    loop
      axi_read(16#04#, d);
      exit when d(0) = '1';
      if now - t0 > 2 ms then report "timeout reinit ligne" severity error; errors := errors + 1; exit; end if;
      wait for 5 us;
    end loop;
    axi_read(16#00#, d);
    if d(6) /= '1' then report "CTRL b6 (ligne) non relu" severity error; errors := errors + 1; end if;
    report "reconfiguration ligne : ecritures I2C totales = " & integer'image(i2c_writes);
    if i2c_writes /= 20 then report "reconfiguration ligne incomplete" severity error; errors := errors + 1; end if;

    -- compteur de trames
    axi_read(16#0C#, d);
    report "trames recues : " & integer'image(to_integer(unsigned(d)));
    if to_integer(unsigned(d)) < 50 then report "compteur de trames faible" severity error; errors := errors + 1; end if;

    errors := errors + i2c_errors;
    if errors = 0 then
      report "TEST PASSED" severity note;
    else
      report "TEST FAILED : " & integer'image(errors) & " erreur(s)" severity error;
    end if;
    sim_done <= true;
    wait;
  end process;

end architecture;
