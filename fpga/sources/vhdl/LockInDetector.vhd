library IEEE;
use ieee.std_logic_1164.all; 
use ieee.numeric_std.ALL;
use ieee.std_logic_unsigned.all; 
use work.CustomDataTypes.all;

entity LockInDetector is
    port(
        --
        -- Clocking and reset
        --
        clk         :   in  std_logic;
        aresetn     :   in  std_logic;
        reset_i     :   in  std_logic;
        --
        -- Control
        --
        regs_i      :   in  t_param_reg_array(3 downto 0);
        --
        -- Signal out
        --
        dac_o       :   out t_dac;    
        --
        -- Data in
        --
        data_i      :   in  t_adc;
        valid_i     :   in  std_logic;
        --
        -- Data out
        --
        data_o      :   out t_adc_array;
        valid_o     :   out std_logic_vector(1 downto 0)
    );
end LockInDetector;

architecture Behavioral of LockInDetector is

COMPONENT DDS_Fixed_Phase
  PORT (
    aclk : IN STD_LOGIC;
    aresetn : IN STD_LOGIC;
    s_axis_phase_tvalid : IN STD_LOGIC;
    s_axis_phase_tdata : IN STD_LOGIC_VECTOR(31 DOWNTO 0);
    m_axis_data_tvalid : OUT STD_LOGIC;
    m_axis_data_tdata : OUT STD_LOGIC_VECTOR(15 DOWNTO 0)
  );
END COMPONENT;

COMPONENT DDS_Mult
  PORT (
    CLK : IN STD_LOGIC;
    A : IN STD_LOGIC_VECTOR(11 DOWNTO 0);
    B : IN STD_LOGIC_VECTOR(7 DOWNTO 0);
    P : OUT STD_LOGIC_VECTOR(19 DOWNTO 0)
  );
END COMPONENT;

COMPONENT DDS_Stream_Phase
  PORT (
    aclk : IN STD_LOGIC;
    aresetn : IN STD_LOGIC;
    s_axis_phase_tvalid : IN STD_LOGIC;
    s_axis_phase_tdata : IN STD_LOGIC_VECTOR(63 DOWNTO 0);
    m_axis_data_tvalid : OUT STD_LOGIC;
    m_axis_data_tdata : OUT STD_LOGIC_VECTOR(31 DOWNTO 0)
  );
END COMPONENT;

COMPONENT Mixer_Mult
  PORT (
    CLK : IN STD_LOGIC;
    A : IN STD_LOGIC_VECTOR(13 DOWNTO 0);
    B : IN STD_LOGIC_VECTOR(11 DOWNTO 0);
    P : OUT STD_LOGIC_VECTOR(25 DOWNTO 0)
  );
END COMPONENT;

COMPONENT LockInFilter
  PORT (
    aclk : IN STD_LOGIC;
    aresetn : IN STD_LOGIC;
    s_axis_config_tdata : IN STD_LOGIC_VECTOR(15 DOWNTO 0);
    s_axis_config_tvalid : IN STD_LOGIC;
    s_axis_config_tready : OUT STD_LOGIC;
    s_axis_data_tdata : IN STD_LOGIC_VECTOR(31 DOWNTO 0);
    s_axis_data_tvalid : IN STD_LOGIC;
    s_axis_data_tready : OUT STD_LOGIC;
    m_axis_data_tdata : OUT STD_LOGIC_VECTOR(71 DOWNTO 0);
    m_axis_data_tvalid : OUT STD_LOGIC
  );
END COMPONENT;

--
-- Phase and frequency signals
--
constant DDS_PHASE_WIDTH    :   natural :=  32;
constant DDS_OUT_WIDTH      :   natural :=  12;
subtype t_phase is std_logic_vector(DDS_PHASE_WIDTH - 1 downto 0);
type t_phase_array is array(natural range <>) of t_phase;
signal freq             :   t_phase_array(1 downto 0);
signal phase            :   t_phase;
signal dds_phase_i      :   std_logic_vector(63 downto 0);
signal dds_dac_o        :   std_logic_vector(15 downto 0);
signal dds_mult_i       :   std_logic_vector(11 downto 0);
signal dds_multiplier   :   std_logic_vector(7 downto 0);
signal dds_mult_o       :   std_logic_vector(19 downto 0);
signal dds_mix_o        :   std_logic_vector(31 downto 0);   
signal dds_sin, dds_cos :   std_logic_vector(DDS_OUT_WIDTH - 1 downto 0);
signal dds_reset        :   std_logic;
--
-- Multiplier signals
--
signal data_slv_i               :   std_logic_vector(13 downto 0);
signal mult_cos_o, mult_sin_o   :   std_logic_vector(data_slv_i'length + DDS_OUT_WIDTH - 1 downto 0);   
--
-- Filtering signals
--
signal cicLog2Rate                      :   unsigned(3 downto 0);
signal cicShift                         :   natural;
signal setShift                         :   unsigned(3 downto 0);
signal filterConfig, filterConfig_old   :   std_logic_vector(15 downto 0);
signal filter_valid                     :   std_logic;
signal filt_cos_i, filt_sin_i           :   std_logic_vector(31 downto 0);
signal filt_cos_o, filt_sin_o           :   std_logic_vector(71 downto 0);
signal filt_cos_valid, filt_sin_valid   :   std_logic;

begin
--
-- Generate the output for the DAC to for phase-sensitive detection
--
freq(0) <= regs_i(0);
freq(1) <= regs_i(1);
phase <= regs_i(2);
dds_multiplier <= regs_i(3)(7 downto 0);
dds_reset <= aresetn and not(reset_i);
FixedPhase: DDS_Fixed_Phase
port map(
    aclk                =>  clk,
    aresetn             =>  dds_reset,
    s_axis_phase_tvalid =>  '1',
    s_axis_phase_tdata  =>  std_logic_vector(freq(0)),
    m_axis_data_tvalid  =>  open,
    m_axis_data_tdata   =>  dds_dac_o
);

dds_mult_i <= std_logic_vector(resize(signed(dds_dac_o),dds_mult_i'length));

OutputMult: DDS_Mult
port map(
    clk =>  clk,
    A   =>  dds_mult_i,
    B   =>  dds_multiplier,
    P   =>  dds_mult_o
);

dac_o <= resize(shift_right(signed(dds_mult_o),6),t_dac'length);
--
-- Generate the signal used for mixing
--
dds_phase_i <= phase & freq(1);
StreamPhase: DDS_Stream_Phase
port map(
    aclk                =>  clk,
    aresetn             =>  dds_reset,
    s_axis_phase_tvalid =>  '1',
    s_axis_phase_tdata  =>  dds_phase_i,
    m_axis_data_tvalid  =>  open,
    m_axis_data_tdata   =>  dds_mix_o
);
dds_cos <= dds_mix_o(DDS_OUT_WIDTH - 1 downto 0);
dds_sin <= dds_mix_o(DDS_OUT_WIDTH + 16 - 1 downto 16); 
--
-- Mix/multiply
--
data_slv_i <= std_logic_vector(resize(data_i,data_slv_i'length));
CosMult: Mixer_Mult
port map(
    clk     =>  clk,
    A       =>  data_slv_i,
    B       =>  dds_cos,
    P       =>  mult_cos_o
);

SinMult: Mixer_Mult
port map(
    clk     =>  clk,
    A       =>  data_slv_i,
    B       =>  dds_sin,
    P       =>  mult_sin_o
);
--
-- Filter
--
cicLog2Rate <= unsigned(regs_i(3)(11 downto 8));
setShift <= unsigned(regs_i(3)(15 downto 12));
cicShift <= to_integer(cicLog2Rate) + to_integer(cicLog2Rate) + to_integer(cicLog2Rate);
filterConfig <= std_logic_vector(shift_left(to_unsigned(1,filterConfig'length),to_integer(cicLog2Rate)));
ChangeProc: process(clk,aresetn) is
begin
    if aresetn = '0' then
        filterConfig_old <= filterConfig;
        filter_valid <= '0';
    elsif rising_edge(clk) then
        filterConfig_old <= filterConfig;
        if filterConfig /= filterConfig_old then
            filter_valid <= '1';
        else
            filter_valid <= '0';
        end if;
    end if;
end process; 

filt_cos_i <= std_logic_vector(resize(signed(mult_cos_o),filt_cos_i'length));
filt_sin_i <= std_logic_vector(resize(signed(mult_sin_o),filt_cos_i'length));

CosFilter : LockInFilter
PORT MAP (
    aclk                    => clk,
    aresetn                 => aresetn,
    s_axis_config_tdata     => filterConfig,
    s_axis_config_tvalid    => filter_valid,
    s_axis_config_tready    => open,
    s_axis_data_tdata       => filt_cos_i,
    s_axis_data_tvalid      => '1',
    s_axis_data_tready      => open,
    m_axis_data_tdata       => filt_cos_o,
    m_axis_data_tvalid      => filt_cos_valid
);
  
SinFilter : LockInFilter
PORT MAP (
    aclk                    => clk,
    aresetn                 => aresetn,
    s_axis_config_tdata     => filterConfig,
    s_axis_config_tvalid    => filter_valid,
    s_axis_config_tready    => open,
    s_axis_data_tdata       => filt_sin_i,
    s_axis_data_tvalid      => '1',
    s_axis_data_tready      => open,
    m_axis_data_tdata       => filt_sin_o,
    m_axis_data_tvalid      => filt_sin_valid
); 

data_o(0) <= resize(shift_right(signed(filt_cos_o(64 downto 0)),cicShift + to_integer(setShift)),t_adc'length);
data_o(1) <= resize(shift_right(signed(filt_sin_o(64 downto 0)),cicShift + to_integer(setShift)),t_adc'length);
valid_o <= filt_sin_valid & filt_cos_valid;

end Behavioral;
