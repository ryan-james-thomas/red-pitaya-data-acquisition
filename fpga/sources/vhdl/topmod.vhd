library IEEE;
use ieee.std_logic_1164.all; 
use ieee.numeric_std.ALL;
use ieee.std_logic_unsigned.all; 
use work.CustomDataTypes.all;
use work.AXI_Bus_Package.all;

--
-- Example top-level module for parsing simple AXI instructions
--
entity topmod is
    port (
        --
        -- Clocks and reset
        --
        sysClk          :   in  std_logic;
        adcClk          :   in  std_logic;
        aresetn         :   in  std_logic;
        --
        -- AXI-super-lite signals
        --      
        addr_i          :   in  unsigned(AXI_ADDR_WIDTH-1 downto 0);            --Address out
        writeData_i     :   in  std_logic_vector(AXI_DATA_WIDTH-1 downto 0);    --Data to write
        dataValid_i     :   in  std_logic_vector(1 downto 0);                   --Data valid out signal
        readData_o      :   out std_logic_vector(AXI_DATA_WIDTH-1 downto 0);    --Data to read
        resp_o          :   out std_logic_vector(1 downto 0);                   --Response in
        --
        -- External I/O
        --
        ext_i           :   in  std_logic_vector(7 downto 0);
        ext_o           :   out std_logic_vector(7 downto 0);
        --
        -- ADC data
        --
        adcData_i       :   in  std_logic_vector(31 downto 0);
        --
        -- DAC data
        --
        m_axis_tdata    :   out std_logic_vector(31 downto 0);
        m_axis_tvalid   :   out std_logic
    );
end topmod;


architecture Behavioural of topmod is

ATTRIBUTE X_INTERFACE_INFO : STRING;
ATTRIBUTE X_INTERFACE_INFO of m_axis_tdata: SIGNAL is "xilinx.com:interface:axis:1.0 m_axis TDATA";
ATTRIBUTE X_INTERFACE_INFO of m_axis_tvalid: SIGNAL is "xilinx.com:interface:axis:1.0 m_axis TVALID";
ATTRIBUTE X_INTERFACE_PARAMETER : STRING;
ATTRIBUTE X_INTERFACE_PARAMETER of m_axis_tdata: SIGNAL is "CLK_DOMAIN system_processing_system7_0_0_FCLK_CLK0,FREQ_HZ 125000000";
ATTRIBUTE X_INTERFACE_PARAMETER of m_axis_tvalid: SIGNAL is "CLK_DOMAIN system_processing_system7_0_0_FCLK_CLK0,FREQ_HZ 125000000";


component QuickAvg is
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
end component;

component FIFOHandler is
    port(
        wr_clk      :   in  std_logic;
        rd_clk      :   in  std_logic;
        aresetn     :   in  std_logic;
        
        data_i      :   in  std_logic_vector(FIFO_WIDTH-1 downto 0);
        valid_i     :   in  std_logic;
        
        fifoReset   :   in  std_logic;
        bus_m       :   in  t_fifo_bus_master;
        bus_s       :   out t_fifo_bus_slave
    );
end component;

component SaveADCData is
    port(
        readClk     :   in  std_logic;          --Clock for reading data
        writeClk    :   in  std_logic;          --Clock for writing data
        aresetn     :   in  std_logic;          --Asynchronous reset
        
        data_i      :   in  std_logic_vector;   --Input data, maximum length of 32 bits
        valid_i     :   in  std_logic;          --High for one clock cycle when data_i is valid
        
        bus_m       :   in  t_mem_bus_master;   --Master memory bus
        bus_s       :   out t_mem_bus_slave     --Slave memory bus
    );
end component;

--
-- AXI communication signals
--
signal comState             :   t_status                        :=  idle;
signal bus_m                :   t_axi_bus_master                :=  INIT_AXI_BUS_MASTER;
signal bus_s                :   t_axi_bus_slave                 :=  INIT_AXI_BUS_SLAVE;
signal reset                :   std_logic;
--
-- Registers
--
signal triggers             :   t_param_reg;
signal topReg               :   t_param_reg;
signal dac_o                :   t_param_reg;
signal fastFiltReg          :   t_param_reg;
signal slowFiltReg          :   t_param_reg;

--
-- ADC signals
--
signal adc_i            :   t_adc_array;
signal adc_f            :   t_adc_array;
signal adc_s            :   t_adc_array;
signal valid_f, valid_s :   std_logic;
--
-- Memory signals
--
signal mem_bus_m    :   t_mem_bus_master;
signal mem_bus_s    :   t_mem_bus_slave;
signal memReset     :   std_logic;
signal saveData_i   :   std_logic_vector(31 downto 0);
signal saveValid_i  :   std_logic;
--
-- Trigger signals
--
signal trigEdge     :   std_logic;
signal trig_i       :   std_logic;
signal trigSync     :   std_logic_vector(1 downto 0);
signal delay        :   unsigned(31 downto 0);
signal delayCount   :   unsigned(31 downto 0);
signal delayState   :   unsigned(3 downto 0);
signal enableSave   :   std_logic;
signal numSamples   :   t_mem_addr;
signal trigHoldOff  :   unsigned(31 downto 0);
--
-- FIFO signals
--
signal fifoReg      :   t_param_reg;
signal fifoReset    :   std_logic;
signal fifo_m       :   t_fifo_bus_master;
signal fifo_s       :   t_fifo_bus_slave;
signal fifo_i       :   std_logic_vector(FIFO_WIDTH - 1 downto 0);
signal validFifo_i  :   std_logic;
signal enableSlow   :   std_logic;

begin
--
-- DAC Outputs
--
m_axis_tdata <= dac_o;
m_axis_tvalid <= '1';
ext_o <= (others => '0');
--
-- Create ADC data
--
adc_i(0) <= signed(adcData_i(15 downto 0));
adc_i(1) <= signed(adcData_i(31 downto 16));
--
-- Detects trigger edges
--
trigEdge <= topReg(0);
trig_i <= ext_i(7);
TrigSyncProcess: process(adcclk,aresetn) is
begin
    if aresetn = '0' then
        trigSync <= "00";
    elsif rising_edge(adcclk) then
        trigSync <= trigSync(0) & trig_i;
    end if;
end process;
--
-- Delay of acquisition
--
DelayProcess: process(adcClk,aresetn) is
begin
    if aresetn = '0' then
        delayCount <= (others => '0');
        delayState <= X"0";
        enableSave <= '0';
        memReset <= '0';
    elsif rising_edge(adcClk) then
        DelayCase: case delayState is
            when X"0" =>
                delayCount <= to_unsigned(1,delayCount'length);
                enableSave <= '0';
                if (trigEdge = '0' and trigSync = "10") or (trigEdge = '1' and trigSync = "01") or triggers(0) = '1' then
                    delayState <= X"1";
                    memReset <= '1';
                elsif reset = '1' then
                    memReset <= '1';
                else
                    memReset <= '0';
                end if;
                
            when X"1" =>
                memReset <= '0';
                if delayCount < delay then
                    delayCount <= delayCount + 1;
                    enableSave <= '0';
                else
                    enableSave <= '1';
                    delayState <= X"2";
                end if;
                
            when X"2" =>
                if mem_bus_s.last >= numSamples then
                    delayState <= X"3";
                    enableSave <= '0';
                    delayCount <= (others => '0');
                end if;
                
            when X"3" => 
                enableSave <= '0';
                if delayCount < trigHoldOff then
                    delayCount <= delayCount + 1;
                else
                    delayState <= X"0";
                end if;
            
            when others => null;
        end case;           
    end if;
end process;
--
-- Average data
--
FastAvg: QuickAvg
port map(
    clk         =>  adcClk,
    aresetn     =>  aresetn,
    reg_i       =>  fastFiltReg,
    enable_i    =>  enableSave,
    adc_i       =>  adc_i,
    valid_i     =>  '1',
    adc_o       =>  adc_f,
    valid_o     =>  valid_f
);
--
-- Save data
--
saveData_i <= std_logic_vector(adc_f(1)) & std_logic_vector(adc_f(0));
mem_bus_m.reset <= memReset;
SaveData: SaveADCData
port map(
    readClk     =>  sysClk,
    writeClk    =>  adcClk,
    aresetn     =>  aresetn,
    data_i      =>  saveData_i,
    valid_i     =>  valid_f,
    bus_m       =>  mem_bus_m,
    bus_s       =>  mem_bus_s
);
--
-- Filter data for slow acquisition using FIFO
--
enableSlow <= fifoReg(0);
SlowAvg: QuickAvg
port map(
    clk         =>  adcClk,
    aresetn     =>  aresetn,
    reg_i       =>  slowFiltReg,
    enable_i    =>  enableSlow,
    adc_i       =>  adc_i,
    valid_i     =>  '1',
    adc_o       =>  adc_s,
    valid_o     =>  valid_s
);
--
-- Save data into FIFO
--
fifo_i <= std_logic_vector(adc_s(1)) & std_logic_vector(adc_s(0));
fifoReset <= fifoReg(1);
SlowFIFO: FIFOHandler
port map(
    wr_clk      =>  adcClk,
    rd_clk      =>  sysClk,
    aresetn     =>  aresetn,
    data_i      =>  fifo_i,
    valid_i     =>  valid_s,
    fifoReset   =>  fifoReset,
    bus_m       =>  fifo_m,
    bus_s       =>  fifo_s
);
--
-- AXI communication routing - connects bus objects to std_logic signals
--
bus_m.addr <= addr_i;
bus_m.valid <= dataValid_i;
bus_m.data <= writeData_i;
readData_o <= bus_s.data;
resp_o <= bus_s.resp;

Parse: process(sysClk,aresetn) is
begin
    if aresetn = '0' then
        comState <= idle;
        reset <= '0';
        bus_s <= INIT_AXI_BUS_SLAVE;
        triggers <= (others => '0');
        topReg <= (others => '0');
        dac_o <= (others => '0');
        delay <= (others => '0');
        numSamples <= (0 => '1', others => '0');
        fastFiltReg <= (others => '0');
        slowFiltReg <= (others => '0');
        fifo_m <= INIT_FIFO_BUS_MASTER;
        fifoReg <= (others => '0');
        mem_bus_m.trig <= '0';
        mem_bus_m.addr <= (others => '0');
        mem_bus_m.status <= idle;
        
        trigHoldOff <= (others => '0');
        
    elsif rising_edge(sysClk) then
        FSM: case(comState) is
            when idle =>
                triggers <= (others => '0');
                reset <= '0';
                bus_s.resp <= "00";
                if bus_m.valid(0) = '1' then
                    comState <= processing;
                end if;

            when processing =>
                AddrCase: case(bus_m.addr(31 downto 24)) is
                    --
                    -- Parameter parsing
                    --
                    when X"00" =>
                        ParamCase: case(bus_m.addr(23 downto 0)) is
                            --
                            -- This issues a reset signal to the memories and writes data to
                            -- the trigger registers
                            --
                            when X"000000" => 
                                rw(bus_m,bus_s,comState,triggers);
                                reset <= '1';
                                
                            when X"000004" => rw(bus_m,bus_s,comState,topReg);
                            when X"000008" => rw(bus_m,bus_s,comState,fastFiltReg);
                            when X"00000C" => rw(bus_m,bus_s,comState,delay);
                            when X"000010" => rw(bus_m,bus_s,comState,numSamples);
                            when X"000014" => rw(bus_m,bus_s,comState,slowFiltReg);
                            when X"000018" => rw(bus_m,bus_s,comState,dac_o);
                            --
                            -- FIFO data
                            --
                            when X"00001C" => rw(bus_m,bus_s,comState,fifoReg);
                            when X"000020" => fifoRead(bus_m,bus_s,comState,fifo_m,fifo_s);
                            --
                            -- Read-only cases
                            --
                            when X"000024" => readOnly(bus_m,bus_s,comState,mem_bus_s.last);
                            when X"000028" => rw(bus_m,bus_s,comState,trigHoldOff);
                            
                            when others => 
                                comState <= finishing;
                                bus_s.resp <= "11";
                        end case;
                    --
                    -- Read only cases
                    --
--                    when X"01" =>
--                        ParamCaseReadOnly: case(bus_m.addr(23 downto 0)) is
--                            when X"000000" => readOnly(bus_m,bus_s,comState,mem_bus_s.last);
--                            when others => 
--                                comState <= finishing;
--                                bus_s.resp <= "11";
--                        end case;
                    --
                    -- Memory reading
                    --
                    when X"02" =>  
                        if bus_m.valid(1) = '0' then
                            bus_s.resp <= "11";
                            comState <= finishing;
                            mem_bus_m.trig <= '0';
                            mem_bus_m.status <= idle;
                        elsif mem_bus_s.valid = '1' then
                            bus_s.data <= mem_bus_s.data;
                            comState <= finishing;
                            bus_s.resp <= "01";
                            mem_bus_m.status <= idle;
                            mem_bus_m.trig <= '0';
                        elsif mem_bus_s.status = idle then
                            mem_bus_m.addr <= bus_m.addr(MEM_ADDR_WIDTH+1 downto 2);
                            mem_bus_m.status <= waiting;
                            mem_bus_m.trig <= '1';
                         else
                            mem_bus_m.trig <= '0';
                        end if;
                    
                    when others => 
                        comState <= finishing;
                        bus_s.resp <= "11";
                end case;
            when finishing =>
--                triggers <= (others => '0');
--                reset <= '0';
                comState <= idle;

            when others => comState <= idle;
        end case;
    end if;
end process;

    
end architecture Behavioural;