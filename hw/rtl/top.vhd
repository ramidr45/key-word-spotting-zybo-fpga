--------------------------------------------------------------------------------
-- top.vhd  --  Zybo (1re generation, Zynq-7010) : Keyword Spotting (audio SSM2603 -> ARM)
-- Instancie le Block Design "system" (PS7 + Clocking Wizard + kws_audio_axi)
-- et ajoute les primitives d'E/S : IOBUF drain ouvert I2C, ODDR pour MCLK.
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
library unisim;
use unisim.vcomponents.all;

entity top is
  port (
    DDR_addr          : inout std_logic_vector(14 downto 0);
    DDR_ba            : inout std_logic_vector(2 downto 0);
    DDR_cas_n         : inout std_logic;
    DDR_ck_n          : inout std_logic;
    DDR_ck_p          : inout std_logic;
    DDR_cke           : inout std_logic;
    DDR_cs_n          : inout std_logic;
    DDR_dm            : inout std_logic_vector(3 downto 0);
    DDR_dq            : inout std_logic_vector(31 downto 0);
    DDR_dqs_n         : inout std_logic_vector(3 downto 0);
    DDR_dqs_p         : inout std_logic_vector(3 downto 0);
    DDR_odt           : inout std_logic;
    DDR_ras_n         : inout std_logic;
    DDR_reset_n       : inout std_logic;
    DDR_we_n          : inout std_logic;
    FIXED_IO_ddr_vrn  : inout std_logic;
    FIXED_IO_ddr_vrp  : inout std_logic;
    FIXED_IO_mio      : inout std_logic_vector(53 downto 0);
    FIXED_IO_ps_clk   : inout std_logic;
    FIXED_IO_ps_porb  : inout std_logic;
    FIXED_IO_ps_srstb : inout std_logic;
    -- codec audio SSM2603
    ac_bclk   : in    std_logic;
    ac_mclk   : out   std_logic;
    ac_muten  : out   std_logic;
    ac_pbdat  : out   std_logic;
    ac_recdat : in    std_logic;
    ac_reclrc : in    std_logic;
    ac_scl    : inout std_logic;
    ac_sda    : inout std_logic;
    -- carte
    led       : out   std_logic_vector(3 downto 0);
    sw        : in    std_logic_vector(3 downto 0);
    btn       : in    std_logic_vector(3 downto 0)
  );
end entity;

architecture rtl of top is

  component system_wrapper is
    port (
      DDR_addr          : inout std_logic_vector(14 downto 0);
      DDR_ba            : inout std_logic_vector(2 downto 0);
      DDR_cas_n         : inout std_logic;
      DDR_ck_n          : inout std_logic;
      DDR_ck_p          : inout std_logic;
      DDR_cke           : inout std_logic;
      DDR_cs_n          : inout std_logic;
      DDR_dm            : inout std_logic_vector(3 downto 0);
      DDR_dq            : inout std_logic_vector(31 downto 0);
      DDR_dqs_n         : inout std_logic_vector(3 downto 0);
      DDR_dqs_p         : inout std_logic_vector(3 downto 0);
      DDR_odt           : inout std_logic;
      DDR_ras_n         : inout std_logic;
      DDR_reset_n       : inout std_logic;
      DDR_we_n          : inout std_logic;
      FIXED_IO_ddr_vrn  : inout std_logic;
      FIXED_IO_ddr_vrp  : inout std_logic;
      FIXED_IO_mio      : inout std_logic_vector(53 downto 0);
      FIXED_IO_ps_clk   : inout std_logic;
      FIXED_IO_ps_porb  : inout std_logic;
      FIXED_IO_ps_srstb : inout std_logic;
      mclk              : out std_logic;
      ac_bclk           : in  std_logic;
      ac_reclrc         : in  std_logic;
      ac_recdat         : in  std_logic;
      ac_pbdat          : out std_logic;
      ac_muten          : out std_logic;
      ac_scl_t          : out std_logic;
      ac_sda_t          : out std_logic;
      ac_sda_i          : in  std_logic;
      led               : out std_logic_vector(3 downto 0);
      rgb               : out std_logic_vector(2 downto 0);
      sw                : in  std_logic_vector(3 downto 0);
      btn               : in  std_logic_vector(3 downto 0)
    );
  end component;

  signal mclk_int   : std_logic;
  signal scl_t      : std_logic;
  signal sda_t      : std_logic;
  signal sda_i      : std_logic;
  signal scl_i_nc   : std_logic;
  signal rgb        : std_logic_vector(2 downto 0);

begin

  u_sys : system_wrapper
    port map (
      DDR_addr => DDR_addr, DDR_ba => DDR_ba, DDR_cas_n => DDR_cas_n,
      DDR_ck_n => DDR_ck_n, DDR_ck_p => DDR_ck_p, DDR_cke => DDR_cke,
      DDR_cs_n => DDR_cs_n, DDR_dm => DDR_dm, DDR_dq => DDR_dq,
      DDR_dqs_n => DDR_dqs_n, DDR_dqs_p => DDR_dqs_p, DDR_odt => DDR_odt,
      DDR_ras_n => DDR_ras_n, DDR_reset_n => DDR_reset_n, DDR_we_n => DDR_we_n,
      FIXED_IO_ddr_vrn => FIXED_IO_ddr_vrn, FIXED_IO_ddr_vrp => FIXED_IO_ddr_vrp,
      FIXED_IO_mio => FIXED_IO_mio, FIXED_IO_ps_clk => FIXED_IO_ps_clk,
      FIXED_IO_ps_porb => FIXED_IO_ps_porb, FIXED_IO_ps_srstb => FIXED_IO_ps_srstb,
      mclk      => mclk_int,
      ac_bclk   => ac_bclk,
      ac_reclrc => ac_reclrc,
      ac_recdat => ac_recdat,
      ac_pbdat  => ac_pbdat,
      ac_muten  => ac_muten,
      ac_scl_t  => scl_t,
      ac_sda_t  => sda_t,
      ac_sda_i  => sda_i,
      led       => led,
      rgb       => rgb,
      sw        => sw,
      btn       => btn
    );

  -- pas de LED RGB sur la Zybo de 1re generation : sortie rgb non utilisee

  -- MCLK 12.288 MHz vers le codec : transfert d'horloge propre via ODDR
  u_mclk_oddr : ODDR
    generic map (DDR_CLK_EDGE => "SAME_EDGE", INIT => '0', SRTYPE => "SYNC")
    port map (Q => ac_mclk, C => mclk_int, CE => '1', D1 => '1', D2 => '0', R => '0', S => '0');

  -- I2C en drain ouvert : I = '0', T = '1' -> haute impedance (pull-up)
  u_scl_buf : IOBUF
    port map (O => scl_i_nc, IO => ac_scl, I => '0', T => scl_t);
  u_sda_buf : IOBUF
    port map (O => sda_i, IO => ac_sda, I => '0', T => sda_t);

end architecture;
