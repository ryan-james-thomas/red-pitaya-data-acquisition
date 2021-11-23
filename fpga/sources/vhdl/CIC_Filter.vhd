library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity CIC_Filter is
    generic(
        NUM_STAGES          :   natural :=  3;
        MAX_SAMPLE_WIDTH    :   natural :=  16;
        USE_SCALING         :   boolean :=  false 
    );
    port(
        clk         :   in  std_logic;
        aresetn     :   in  std_logic;
        samples_i   :   in  unsigned;
        scale_i     :   in  unsigned;
        data_i      :   in  signed;
        valid_i     :   in  std_logic;
        data_o      :   out signed;  
        valid_o     :   out std_logic
    );
end CIC_Filter;

architecture Behavioral of CIC_Filter is

subtype t_sample_count is unsigned(MAX_SAMPLE_WIDTH - 1 downto 0);
subtype t_data_local is signed(NUM_STAGES*MAX_SAMPLE_WIDTH + data_i'length - 1 downto 0);

type t_sample_count_array is array(natural range <>) of t_sample_count;
type t_data_local_array is array(natural range <>) of t_data_local;

signal resetn       :   std_logic;
signal samples, samplesOld      :   t_sample_count;

signal sample_int   :   t_sample_count_array(NUM_STAGES - 1 downto 0);
signal data_int     :   t_data_local_array(NUM_STAGES - 1 downto 0);
signal valid_int    :   std_logic_vector(NUM_STAGES - 1 downto 0);

signal sample_dec   :   t_sample_count;

signal sample_comb  :   t_sample_count_array(NUM_STAGES - 1 downto 0);
signal data_comb    :   t_data_local_array(NUM_STAGES - 1 downto 0);
signal data_comb_old:   t_data_local_array(NUM_STAGES - 1 downto 0);
signal valid_comb   :   std_logic_vector(NUM_STAGES - 1 downto 0);

signal data_filt    :   signed(data_o'length - 1 downto 0);
signal valid_filt   :   std_logic;

begin

SampleCheck: process(clk,aresetn) is
begin
    if aresetn = '0' then
        samples <= resize(samples_i,samples'length);
        samplesOld <= resize(samples_i,samples'length);
        resetn <= '0';
    elsif rising_edge(clk) then
        samples <= resize(samples_i,samples'length);
        samplesOld <= samples;
        if samples /= samplesOld then
            resetn <= '0';
        else
            resetn <= '1';
        end if;
    end if;
end process;
samples <= resize(samples_i,samples'length);

Integrator0: process(clk,resetn) is
begin
    if resetn = '0' then
        sample_int(0) <= (0 => '1', others => '0');
        data_int(0) <= (others => '0');
        valid_int(0) <= '0';
    elsif rising_edge(clk) then
        if valid_i = '1' then
            data_int(0) <= data_int(0) + data_i;
            if sample_int(0) < samples then
                sample_int(0) <= sample_int(0) + 1;
                valid_int(0) <= '0';
            else
                valid_int(0) <= '1';
            end if;
        else
            valid_int(0) <= '0';
        end if;
    end if;
end process;

GEN_INTEGRATOR: for I in 1 to NUM_STAGES - 1 generate
    IntegratorX: process(clk,resetn) is
    begin
        if resetn = '0' then
            sample_int(I) <= (0 => '1', others => '0');
            data_int(I) <= (others => '0');
            valid_int(I) <= '0';
        elsif rising_edge(clk) then
            if valid_i = '1' then
                data_int(I) <= data_int(I) + data_int(I - 1);
                if sample_int(I) < samples then
                    sample_int(I) <= sample_int(I) + 1;
                    valid_int(I) <= '0';
                else
                    valid_int(I) <= '1';
                end if;
            else
                valid_int(I) <= '0';
            end if;
        end if;
    end process;
end generate GEN_INTEGRATOR;


Comb0: process(clk,resetn) is
begin
    if resetn = '0' then
        sample_dec <= (others => '0');
        data_comb_old(0) <= (others => '0');
        data_comb(0) <= (others => '0');
        valid_comb(0) <= '0';
    elsif rising_edge(clk) then
        if valid_int(NUM_STAGES - 1) = '1' then
            if sample_dec = 0 then
                valid_comb(0) <= '1';
                data_comb_old(0) <= data_int(NUM_STAGES - 1);
                data_comb(0) <= data_int(NUM_STAGES - 1) - data_comb_old(0);
                sample_dec <= samples - 1;
            else
                sample_dec <= sample_dec - 1;
                valid_comb(0) <= '0';
            end if;
        else
            valid_comb(0) <= '0';
        end if;
    end if;
end process;

GEN_COMB: for I in 1 to NUM_STAGES - 1 generate
    Comb0: process(clk,resetn) is
    begin
        if resetn = '0' then
            data_comb(I) <= (others => '0');
            data_comb_old(I) <= (others => '0');
            valid_comb(I) <= '0';
        elsif rising_edge(clk) then
            if valid_comb(I - 1) = '1' then
                data_comb_old(I) <= data_comb(I - 1);
                data_comb(I) <= data_comb(I - 1) - data_comb_old(I);
                valid_comb(I) <= '1';
            else
                valid_comb(I) <= '0';
            end if;
        end if;
    end process;
end generate GEN_COMB;

valid_filt <= valid_comb(NUM_STAGES - 1);
data_filt  <= resize(shift_right(data_comb(NUM_STAGES - 1),to_integer(scale_i)),data_o'length) when USE_SCALING else
              resize(data_comb(NUM_STAGES - 1),data_o'length);

data_o  <= resize(data_i,data_o'length) when samples = 1 else data_filt;
valid_o <= valid_i when samples = 1 else valid_filt;

end Behavioral;
