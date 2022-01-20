library IEEE;
use ieee.std_logic_1164.all; 
use ieee.numeric_std.ALL;
use ieee.std_logic_unsigned.all; 
use work.CustomDataTypes.all;
use work.AXI_Bus_Package.all;

entity DigitalPatternGenerator is
    port(
        wrclk       :   in  std_logic;
        rdclk       :   in  std_logic;
        aresetn     :   in  std_logic;
        reset_i     :   in  std_logic;

        data_i      :   in  t_param_reg;
        valid_i     :   in  std_logic;

        start_i     :   in  std_logic;
        debug_o     :   out t_param_reg;
        data_o      :   out t_dpg
    );
end DigitalPatternGenerator;

architecture rtl of DigitalPatternGenerator is

COMPONENT BlockMemoryController is
    port(
        wrclk       :   in  std_logic;
        rdclk       :   in  std_logic;
        aresetn     :   in  std_logic;
        --Write data
        data_i      :   in  t_mem_data;
        valid_i     :   in  std_logic;
        --Read data
        bus_i       :   in  t_mem_bus_master;
        bus_o       :   out t_mem_bus_slave
    );
end COMPONENT;

type t_state_local is (ready,wait_for_delay,waiting,read_first_address);
signal state    :   t_state_local;

type t_write_state_local is (pow,freq,amp,duration);
signal mem_data_i       :   t_mem_data;
signal memCount         :   unsigned(1 downto 0);
signal memState         :   t_write_state_local;
signal valid, start     :   std_logic;

signal wrTrig           :   std_logic;

signal count            :   unsigned(DPG_TIME_WIDTH downto 0);
signal resetSync, startSync, wrSync        :   std_logic_vector(1 downto 0);

signal bus_i            :   t_mem_bus_master;
signal bus_o            :   t_mem_bus_slave;

signal dpg              :   t_dpg;

begin
debug_o(7 downto 0) <= std_logic_vector(bus_i.addr(7 downto 0));
debug_o(15 downto 8) <= std_logic_vector(bus_o.last(7 downto 0));
debug_o(23 downto 16) <= dpg.data;
--
-- Instantiate memory controller.  Reset signal is
-- routed directly to the bus reset signal
--
mem_data_i <= data_i;
wrTrig <= valid_i;
DPG_Storage: BlockMemoryController
port map(
    wrclk       =>  wrclk,
    rdclk       =>  rdclk,
    aresetn     =>  aresetn,
    data_i      =>  mem_data_i,
    valid_i     =>  wrTrig,
    bus_i       =>  bus_i,
    bus_o       =>  bus_o
);
--
-- Parses output data
--
dpg.delay       <=  unsigned(bus_o.data(DPG_TIME_WIDTH - 1 downto 0));
dpg.data        <=  bus_o.data(DPG_DATA_WIDTH + DPG_TIME_WIDTH - 1 downto DPG_TIME_WIDTH);
--
-- Main delay generator
--
signal_sync(rdclk,aresetn,start_i,startSync);
signal_sync(rdclk,aresetn,wrTrig,wrSync);
TimingProc: process(rdclk,aresetn) is
begin
    if aresetn = '0' then
        state <= ready;
        data_o <= INIT_DPG;
        bus_i <= INIT_MEM_BUS_MASTER;
        count <= (others => '0');
    elsif rising_edge(rdclk) then
        if reset_i = '1' then
            --
            -- If a reset signal is applied, reset the memory controller
            --
            bus_i.reset <= '1';
            state <= ready;
            data_o <= INIT_DPG;
            count <= (others => '0');
        else
            --
            -- Otherwise, make sure the mem_bus reset signal is low
            -- and execute the case statement
            --
            bus_i.reset <= '0';
            
            FSM: case (state) is
                when ready =>
                    if wrSync = "01" then
                        --
                        -- When new data is written, re-load the first address so that it
                        -- is always ready for execution
                        --
                        state <= read_first_address;
                        data_o.valid <= '0';
                        data_o.status <= (started => '0', running => '0', done => '0');
                        bus_i.addr <= (others => '0');
                        bus_i.trig <= '1';
                    elsif startSync = "01" then
                        --
                        -- When start trigger is received, issue new read request
                        -- and wait for the programmed delay
                        --
                        state <= wait_for_delay;
                        bus_i.addr <= (0 => '1', others => '0');
                        bus_i.trig <= '1';
                        count <= "0" & (dpg.delay - 3);
                        data_o.delay <= dpg.delay;
                        data_o.data <= dpg.data;
                        data_o.valid <= '1';
                        data_o.status <= (started => '1', running => '1', done => '0');
                    else
                        bus_i.trig <= '0';
                        data_o.valid <= '0';
                        data_o.status <= (started => '0', running => '0', done => '0');
                    end if;
                    
                
                when read_first_address =>
                    --
                    -- For for valid signal to be asserted
                    --
                    bus_i.trig <= '0';
                    if bus_o.valid = '1' then
                        count <= "0" & (dpg.delay - 3);
--                        data_o.delay <= dpg.delay;
                        data_o.data <= (others => '0');
                        data_o.valid <= '0';
                        data_o.status <= (started => '0', running => '0', done => '0');
                        state <= ready;
                    end if;
                    
                when wait_for_delay =>
                    --
                    -- Wait for the programmed delay
                    --
                    bus_i.trig <= '0';
                    data_o.valid <= '0';
                    data_o.status <= (started => '0', running => '1', done => '0');
                    if count(count'length - 1) = '0' then
                        count <= count - 1;
                    else
                        state <= waiting;
                    end if;
                    
                when waiting =>
                    if bus_o.status = idle then
                        --
                        -- When new data is ready, parse it according to the op-code
                        --
                        if dpg.delay = 0 then
                            --
                            -- A delay of 0 indicates the end-of-instructions
                            --
                            state <= read_first_address;
                            data_o.status <= (started => '0', running => '0', done => '1');
                            bus_i.addr <= (others => '0');
                            bus_i.trig <= '1';
                        else
                            data_o.delay <= dpg.delay;
                            data_o.data <= dpg.data;
                            data_o.valid <= '1';
                            data_o.status <= (started => '0', running => '1', done => '0');
                            count <= "0" & (dpg.delay - 3);
                            bus_i.addr <= bus_i.addr + 1;
                            bus_i.trig <= '1';
                            state <= wait_for_delay;
                        end if;
                    else
                        --
                        -- If new data is not ready, make sure the trigger is lowered
                        --
                        bus_i.trig <= '0';
                    end if;
            end case;
        end if;
    end if;
end process;


end rtl;