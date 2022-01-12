library IEEE;
use ieee.std_logic_1164.all; 
use ieee.numeric_std.ALL;
use ieee.std_logic_unsigned.all; 
use work.CustomDataTypes.all;
--
-- This quickly averages incoming signals and creates a decimated
-- output at a reduced sample rate.  The decimation ratio can only
-- be powers of 2 so that the averaging occurs very quickly by a 
-- bit shift.
--
-- This module assumes that the inputs are 2, 16-bit signed integers
-- packed in an array of 2 elements
--
entity QuickAvg is
    port(
        clk         :   in  std_logic;          --Input clock
        aresetn     :   in  std_logic;          --Asynchronous reset
        reg_i       :   in  t_param_reg;        --(4 downto 0 => log2Avgs)
        enable_i    :   in  std_logic;          --Input enable signal
        adc_i       :   in  t_adc_array;        --Input ADC data
        valid_i     :   in  std_logic;          --Input valid signal
        adc_o       :   out t_adc_array;        --Output, averaged ADC data
        valid_o     :   out std_logic           --Indicates valid averaged data
    );
end QuickAvg;

architecture Behavioural of QuickAvg is

--
-- Padding of integrated signals and their extended widhts
--
constant PADDING    :   natural :=  32;  
constant EXT_WIDTH  :   natural :=  ADC_WIDTH + PADDING; 
--
-- Parameters
--
signal log2Avgs     :   natural range 0 to 31   :=  0;
signal numAvgs      :   unsigned(31 downto 0)   :=  to_unsigned(1,32);
signal shift        :   natural range 0 to 31   :=  0;
--
-- Counter for averaging
--
signal avgCount     :   unsigned(numAvgs'length-1 downto 0) :=  (others => '0');
--
-- Split input signals and averaged signals
--
signal adc1, adc1_tmp, adc2, adc2_tmp   :   signed(EXT_WIDTH-1 downto 0) :=  (others => '0');

begin
--
-- Parse parameters
--
log2Avgs <= to_integer(unsigned(reg_i(4 downto 0)));
shift <= to_integer(unsigned(reg_i(10 downto 5)));
numAvgs <= shift_left(to_unsigned(1,numAvgs'length),log2Avgs);
--
-- Split input signal into the two channels as signed integers
--
adc1_tmp <= resize(signed(adc_i(0)),adc1_tmp'length);
adc2_tmp <= resize(signed(adc_i(1)),adc2_tmp'length);
--
-- Main procedure for doing the averaging. A new sample is assumed
-- to arrive when valid_i = '1'
--
MainProc: process(clk,aresetn) is
begin
    if aresetn = '0' then
        avgCount <= (others => '0');
        adc1 <= (others => '0');
        adc2 <= (others => '0');
        valid_o <= '0';
        adc_o <= (others => (others => '0'));
    elsif rising_edge(clk) then
        if enable_i = '0' then
            --
            -- When module is disabled
            --
            avgCount <= (others => '0');
            adc1 <= (others => '0');
            adc2 <= (others => '0');
            valid_o <= '0';
            adc_o <= (others => (others => '0'));
        elsif valid_i = '1' then
            --
            -- When input data is valid
            --
            if log2Avgs = 0 then
                --
                -- If no averaging is to be done then pass input
                -- data directly to output
                --
                adc_o <= adc_i;
                valid_o <= '1';
                avgCount <= (others => '0');
            elsif avgCount = 0 then
                --
                -- If averaging is to be done, assign the current
                -- input to the stored averaged input
                --
                adc1 <= adc1_tmp;
                adc2 <= adc2_tmp;
                valid_o <= '0';
                avgCount <= avgCount + 1;
            elsif avgCount = numAvgs - 1 then
                --
                -- When averaging, this is the last count value before output
                -- So the output data is the last adc%d value plus the current input
                --
                adc_o(0) <= resize(shift_right(adc1 + adc1_tmp,log2Avgs - shift),ADC_WIDTH);
                adc_o(1) <= resize(shift_right(adc2 + adc2_tmp,log2Avgs - shift),ADC_WIDTH);
                valid_o <= '1';
                avgCount <= (others => '0');
            else
                --
                -- Otherwise average the incoming data
                --
                adc1 <= adc1 + adc1_tmp;
                adc2 <= adc2 + adc2_tmp;
                valid_o <= '0';
                avgCount <= avgCount + 1;
            end if;
        else
            --
            -- If valid_i = '0' then make sure valid_o is also '0'
            --
            valid_o <= '0';
        end if;
    end if;
end process;

end architecture Behavioural;