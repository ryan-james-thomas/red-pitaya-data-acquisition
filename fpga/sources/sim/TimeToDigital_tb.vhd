library IEEE;
use ieee.std_logic_1164.all; 
use ieee.numeric_std.ALL;
use ieee.std_logic_unsigned.all; 
use work.CustomDataTypes.all;

entity TimeToDigital_tb is
--  Port ( );
end TimeToDigital_tb;

architecture Behavioral of TimeToDigital_tb is

component TimeToDigital is
    port(
        clk         :   in  std_logic;
        aresetn     :   in  std_logic;
        reset_i     :   in  std_logic;
        --
        -- Registers
        --
        regs_i      :   in  t_param_reg_array(1 downto 0);
        --
        -- Input data
        --
        data_i      :   in  t_adc;
        valid_i     :   in  std_logic;
        start_i     :   in  std_logic;
        --
        -- Output data
        --
        data_o      :   out unsigned(31 downto 0);
        valid_o     :   out std_logic
    );
end component;

--
-- Clocks and reset
--
signal clk_period   :   time    :=  10 ns;
signal sysClk,adcClk:   std_logic;
signal aresetn      :   std_logic;
signal reset_i      :   std_logic;

signal regs_i       :   t_param_reg_array(1 downto 0);
signal data_i       :   t_adc;
signal valid_i      :   std_logic;
signal start_i      :   std_logic;

signal data_o       :   unsigned(31 downto 0);
signal valid_o      :   std_logic;

signal counter      :   unsigned(31 downto 0);
signal polarity     :   std_logic;

signal incr       :   t_adc;
signal maxval     :   t_adc;

begin

clk_proc: process is
begin
    sysClk <= '0';
    adcClk <= '0';
    wait for clk_period/2;
    sysClk <= '1';
    adcClk <= '1';
    wait for clk_period/2;
end process;

TDC: TimeToDigital
port map(
    clk         =>  sysclk,
    aresetn     =>  aresetn,
    reset_i     =>  reset_i,
    regs_i      =>  regs_i,
    data_i      =>  data_i,
    valid_i     =>  valid_i,
    start_i     =>  start_i,
    data_o      =>  data_o,
    valid_o     =>  valid_o
);

ADC_proc: process(sysclk,aresetn) is
begin
    if aresetn = '0' then
        data_i <= -maxval;
        valid_i <= '0';
        polarity <= '1';
    elsif rising_edge(sysclk) then
        if data_i <= maxval and data_i >= -maxval then
            if polarity = '0' then
                data_i <= data_i - incr;
            else
                data_i <= data_i + incr;
            end if;
        elsif data_i >= maxval then
            data_i <= maxval;
            polarity <= '0';
        elsif data_i <= -maxval then
            data_i <= -maxval;
            polarity <= '1';
        end if;
    end if;
end process;

main_proc: process is
begin
    --
    -- Initialize the registers and reset
    --
    aresetn <= '0';
    wait for 50 ns;
    regs_i(0) <= std_logic_vector(to_signed(2048,16)) & std_logic_vector(to_signed(0,16));
    regs_i(1) <= "00" & std_logic_vector(to_unsigned(16384,30));
    reset_i <= '0';
    start_i <= '0';
    incr <= to_signed(100,16);
    maxval <= to_signed(4096,16);
    
    wait for 50 ns;
    aresetn <= '1';
    
    wait for 100 ns;
    wait until rising_edge(sysclk);
    start_i <= '1';
    wait until rising_edge(sysclk);
    start_i <= '0';
    
    wait;
    
end process;



end Behavioral;
