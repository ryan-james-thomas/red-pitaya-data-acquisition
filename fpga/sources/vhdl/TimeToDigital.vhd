library IEEE;
use ieee.std_logic_1164.all; 
use ieee.numeric_std.ALL;
use ieee.std_logic_unsigned.all; 
use work.CustomDataTypes.all;

entity TimeToDigital is
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
        trigEdge    :   in  std_logic;
        start_i     :   in  std_logic;
        --
        -- Output data
        --
        data_o      :   out unsigned(31 downto 0);
        valid_o     :   out std_logic
    );
end TimeToDigital;

architecture rtl of TimeToDigital is

type t_state_local is (idle,running);
signal state        :   t_state_local;
    
signal threshold    :   t_adc;
signal hysteresis   :   t_adc;
signal diff         :   t_adc_array;

signal counter      :   unsigned(31 downto 0);
--signal maxcount     :   unsigned(31 downto 0);
signal armed        :   std_logic;
signal detect       :   std_logic_vector(1 downto 0);

signal startSync    :   std_logic_vector(1 downto 0);

begin
--
-- Retrieve parameters from registers
--
threshold   <= signed(regs_i(0)(15 downto 0));
hysteresis  <= signed(regs_i(0)(31 downto 16));
--maxcount    <= resize(shift_left(unsigned(regs_i(1)(29 downto 0)),2),maxcount'length);
detect      <= regs_i(1)(31 downto 30);

diff(0) <= data_i - threshold;
signal_sync(clk,aresetn,start_i,startSync);
Main: process(clk,aresetn) is
begin
    if aresetn = '0' then
        armed <= '1';
        diff(1) <= diff(0);
        data_o <= (others => '0');
        valid_o <= '0';
    elsif rising_edge(clk) then
        --
        -- Store old differences
        --
        diff(1) <= diff(0);

        if diff(0) > 0 and diff(1) < 0 then
            --
            -- Positive edge
            --
            if armed = '1' and detect(0) = '0' then
                data_o <= counter;
                valid_o <= '1';
                armed <= '0';
            else
                valid_o <= '0';
            end if;
        elsif diff(0) < 0 and diff(1) > 0 then
            --
            -- Negative edge
            --
            if armed = '1' and detect(1) = '0' then
                data_o <= counter;
                valid_o <= '1';
                armed <= '0';
            else
                valid_o <= '0';
            end if;
        elsif diff(0) > hysteresis or diff(0) < -hysteresis then
            armed <= '1';
            valid_o <= '0';
        else
            valid_o <= '0';
        end if;

    end if;
end process;

CounterProcess: process(clk,aresetn) is
begin
    if aresetn = '0' then
        state <= idle;
        counter <= (others => '0');
    elsif rising_edge(clk) then
        if (startSync = "01" and trigEdge = '1') or (startSync = "10" and trigEdge = '0') then
            counter <= (0 => '1', others => '0');
        elsif counter > 0 and reset_i = '0' then
            counter <= counter + 1;
        else
            counter <= (others => '0');
        end if;
    end if;
end process;
    
end architecture rtl;