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

component LockInDetector is
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
end component;

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
        
        trigEdge    :   in  std_logic;          --'0' for falling edge, '1' for rising edge
        delay       :   in  unsigned;           --Acquisition delay
        numSamples  :   in  t_mem_addr;         --Number of samples to save
        trig_i      :   in  std_logic;          --Start trigger
        
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
signal dacReg               :   t_param_reg;
signal fastFiltReg          :   t_param_reg;
signal slowFiltReg          :   t_param_reg;
--
-- Lock in signals
--
signal dds_reset        :   std_logic;
signal lockinRegs       :   t_param_reg_array(3 downto 0);
signal lockin_dac_o     :   t_dac;
signal lockin_data_i    :   t_adc;
signal lockin_data_o    :   t_adc_array;
signal lockin_valid_o   :   std_logic_vector(1 downto 0);
signal saveLockIn_i     :   std_logic_vector(31 downto 0);

signal inputSelect      :   std_logic;
signal outputSelect     :   std_logic_vector(1 downto 0);
signal dac_o            :   t_dac_array;

--
-- ADC signals
--
signal adc_i            :   t_adc_array;
signal adc_filt_i       :   t_adc_array;
signal adc_f            :   t_adc_array;
signal adc_s            :   t_adc_array;
signal valid_f, valid_s :   std_logic;
--
-- Memory signals
--
signal mem_bus      :   t_mem_bus_array(1 downto 0);
signal mem_bus_m    :   t_mem_bus_master;
signal mem_bus_s    :   t_mem_bus_slave;
signal memReset     :   std_logic;
signal saveData_i   :   std_logic_vector(31 downto 0);
signal saveValid_i  :   std_logic;
signal memTrig      :   std_logic;
--
-- Trigger signals
--
signal trigEdge     :   std_logic;
signal trigEnable   :   std_logic;
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
--
-- Additional signals
--
signal extReg       :   t_param_reg;

begin
--
-- Parse top-level signals
--
trigEdge <= topReg(0);
inputSelect <= topReg(1);
outputSelect <= topReg(3 downto 2);
trigEnable <= topReg(4);
--
-- Create ADC data
--
adc_i(0) <= signed(adcData_i(15 downto 0));
adc_i(1) <= signed(adcData_i(31 downto 16));
--
-- Lock-in detection
--
lockin_data_i <= adc_i(0) when inputSelect = '0' else adc_i(1);
dds_reset <= triggers(1);
LockIn: LockInDetector
port map(
    clk         =>  adcClk,
    aresetn     =>  aresetn,
    reset_i     =>  dds_reset,
    regs_i      =>  lockinRegs,
    dac_o       =>  lockin_dac_o,
    data_i      =>  lockin_data_i,
    valid_i     =>  '1',
    data_o      =>  lockin_data_o,
    valid_o     =>  lockin_valid_o
);

saveLockIn_i <= adc_to_slv(lockin_data_o);

SaveDataLockin: SaveADCData
port map(
    readClk     =>  sysClk,
    writeClk    =>  adcClk,
    aresetn     =>  aresetn,
    data_i      =>  saveLockIn_i,
    valid_i     =>  lockin_valid_o(0),
    trigEdge    =>  trigEdge,
    delay       =>  delay,
    numSamples  =>  numSamples,
    trig_i      =>  memTrig,
    bus_m       =>  mem_bus(1).m,
    bus_s       =>  mem_bus(1).s
);

--
-- DAC Outputs
--
dac_o(0) <= signed(dacReg(15 downto 0)) when outputSelect(0) = '0' else lockin_dac_o;
dac_o(1) <= signed(dacReg(31 downto 16)) when outputSelect(1) = '0' else lockin_dac_o;
m_axis_tdata <= dac_to_slv(dac_o);
m_axis_tvalid <= '1';
--ext_o <= (others => '0');
ext_o <= extReg(7 downto 0);
--
-- Average data
--
FastAvg: QuickAvg
port map(
    clk         =>  adcClk,
    aresetn     =>  aresetn,
    reg_i       =>  fastFiltReg,
    enable_i    =>  '1',
    adc_i       =>  adc_i,
    valid_i     =>  '1',
    adc_o       =>  adc_f,
    valid_o     =>  valid_f
);
--
-- Save data
--
saveData_i <= adc_to_slv(adc_f);
memTrig <= (ext_i(7) and trigEnable) or triggers(0);
SaveData: SaveADCData
port map(
    readClk     =>  sysClk,
    writeClk    =>  adcClk,
    aresetn     =>  aresetn,
    data_i      =>  saveData_i,
    valid_i     =>  valid_f,
    trigEdge    =>  trigEdge,
    delay       =>  delay,
    numSamples  =>  numSamples,
    trig_i      =>  memTrig,
    bus_m       =>  mem_bus(0).m,
    bus_s       =>  mem_bus(0).s
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
fifo_i <= adc_to_slv(adc_s);
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
        dacReg <= (others => '0');
        delay <= (others => '0');
        numSamples <= (0 => '1', others => '0');
        fastFiltReg <= (others => '0');
        slowFiltReg <= (others => '0');
        fifo_m <= INIT_FIFO_BUS_MASTER;
        fifoReg <= (others => '0');
        lockInRegs <= (others => (others => '0'));
        mem_bus(0).m <= INIT_MEM_BUS_MASTER;
        mem_bus(1).m <= INIT_MEM_BUS_MASTER;
--        mem_bus(0).m.trig <= '0';
--        mem_bus(0).m.addr <= (others => '0');
--        mem_bus(0).m.status <= idle;
        
--        mem_bus(1).m.trig <= '0';
--        mem_bus(1).m.addr <= (others => '0');
--        mem_bus(1).m.status <= idle;
        
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
                            when X"000018" => rw(bus_m,bus_s,comState,dacReg);
                            --
                            -- FIFO data
                            --
                            when X"00001C" => rw(bus_m,bus_s,comState,fifoReg);
                            when X"000020" => fifoRead(bus_m,bus_s,comState,fifo_m,fifo_s);
                            --
                            -- Read-only cases
                            --
                            when X"000024" => readOnly(bus_m,bus_s,comState,mem_bus(0).s.last);
                            when X"000028" => readOnly(bus_m,bus_s,comState,mem_bus(1).s.last);
                            when X"00002C" => rw(bus_m,bus_s,comState,trigHoldOff);
                            --
                            -- Auxiliary data
                            --
                            when X"000030" => readOnly(bus_m,bus_s,comState,adcData_i);
                            --
                            -- Lock-in data
                            --
                            when X"000040" => rw(bus_m,bus_s,comState,lockinRegs(0));
                            when X"000044" => rw(bus_m,bus_s,comState,lockinRegs(1));
                            when X"000048" => rw(bus_m,bus_s,comState,lockinRegs(2));
                            when X"00004C" => rw(bus_m,bus_s,comState,lockinRegs(3));
                            --
                            -- External outputs
                            --
                            when X"000050" => rw(bus_m,bus_s,comState,extReg);
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
                    -- Memory reading of normal memory
                    --
                    when X"02" =>  
                        if bus_m.valid(1) = '0' then
                            bus_s.resp <= "11";
                            comState <= finishing;
                            mem_bus(0).m.trig <= '0';
                            mem_bus(0).m.status <= idle;
                        elsif mem_bus(0).s.valid = '1' then
                            bus_s.data <= mem_bus(0).s.data;
                            comState <= finishing;
                            bus_s.resp <= "01";
                            mem_bus(0).m.status <= idle;
                            mem_bus(0).m.trig <= '0';
                        elsif mem_bus(0).s.status = idle then
                            mem_bus(0).m.addr <= bus_m.addr(MEM_ADDR_WIDTH+1 downto 2);
                            mem_bus(0).m.status <= waiting;
                            mem_bus(0).m.trig <= '1';
                         else
                            mem_bus(0).m.trig <= '0';
                        end if;
                        
                    
                    --
                    -- Memory reading of lock-in detection
                    --
                    when X"03" =>  
                        if bus_m.valid(1) = '0' then
                            bus_s.resp <= "11";
                            comState <= finishing;
                            mem_bus(1).m.trig <= '0';
                            mem_bus(1).m.status <= idle;
                        elsif mem_bus(1).s.valid = '1' then
                            bus_s.data <= mem_bus(1).s.data;
                            comState <= finishing;
                            bus_s.resp <= "01";
                            mem_bus(1).m.status <= idle;
                            mem_bus(1).m.trig <= '0';
                        elsif mem_bus(1).s.status = idle then
                            mem_bus(1).m.addr <= bus_m.addr(MEM_ADDR_WIDTH+1 downto 2);
                            mem_bus(1).m.status <= waiting;
                            mem_bus(1).m.trig <= '1';
                         else
                            mem_bus(1).m.trig <= '0';
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