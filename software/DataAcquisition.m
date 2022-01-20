classdef DataAcquisition < handle
    properties
        t
        data
        jumpers
    end
    
    properties(SetAccess = immutable)
        conn            %Connection client object
        trigEdge        %Edge for triggering fast acquisition
        trigEnable      %Enable external triggering
        inputSelect     %Input selector for lock-in detection
        outputSelect    %Output selector for manual or lock-in output routed to DACs
        enableGating    %Enables gating of signal acquisition
        log2AvgsFast    %Log2(#avgs) for fast acquisition
        shiftFast       %Additional shift left for averaged signals on fast acquisition
        delay           %Delay between trigger and start of fast acquistion
        numSamples      %Number of samples for fast acquisition
        log2AvgsSlow    %Log2(#avgs) for slow acquisition
        shiftSlow       %Additional shift left for averaged signals on slow acquisition
        holdOff         %Trigger hold off
        dac             %DAC outputs (2 element array)
        lockin          %Lock-in control
        ext_o           %External output control
    end
    
    properties(SetAccess = protected)
        trigReg         %Trigger register
        topReg          %Top-level register
        fastFiltReg     %Fast-filtering register
        delayReg        %Delay register
        numSamplesReg   %Number of samples register for fast acquisition
        slowFiltReg     %Slow-filtering register
        dacReg          %DAC output register
        lastSample      %Last sample registers, 2 elements
        holdOffReg      %Tigger hold off register
        adcReg          %ADC register
        debugReg        %Debug register
        lockInRegs      %4-element lock-in registers
        extReg          %External digital output register
        dpgReg          %Register for writing DPG data
        auxReg          %Auxiliary register
    end
    
    properties(Constant)
        CLK = 125e6;                    %Clock frequency of the board
        DEFAULT_HOST = '';              %Default socket server address
        DEFAULT_PORT = 6666;            %Default port of socket server
        ADC_WIDTH = 14;                 %Bit width of ADC values
        DAC_WIDTH = 14;                 %Bit width of DAC values
        %
        % Conversion values going from integer values to volts
        %
        CONV_ADC_LV = 1.1851/2^(DataAcquisition.ADC_WIDTH - 1);
        CONV_ADC_HV = 27.5/2^(DataAcquisition.ADC_WIDTH - 1);
        CONV_DAC = 1.079/2^(DataAcquisition.ADC_WIDTH - 1);
    end
    
    methods
        function self = DataAcquisition(host,port)
            %DataAcquisition Creates an instance of a DataAcquisition object.
            %Sets up the registers and parameters as instances of the
            %correct classes with the necessary
            %addressses/registers/limits/functions
            %
            %   SELF = DataAcquisition() creates an instance with default
            %   host and port
            %
            %   SELF = DataAcquisition(HOST) creates an instance with socket
            %   server host address HOST
            %
            %   SELF = DataAcquisition(HOST,PORT) creates an instance with
            %   socket server host address HOST and port PORT
            
            if nargin == 0
                self.conn = ConnectionClient(self.DEFAULT_HOST,self.DEFAULT_PORT);
            elseif nargin == 1
                self.conn = ConnectionClient(host,self.DEFAULT_PORT);
            else
                self.conn = ConnectionClient(host,port);
            end
            %
            % Set jumper values
            %
            self.jumpers = 'lv';
            %
            % R/W registers
            %
            self.trigReg = DeviceRegister('0',self.conn);
            self.topReg = DeviceRegister('4',self.conn);
            self.fastFiltReg = DeviceRegister('8',self.conn);
            self.delayReg = DeviceRegister('C',self.conn);
            self.numSamplesReg = DeviceRegister('10',self.conn);
            self.slowFiltReg = DeviceRegister('14',self.conn);
            self.dacReg = DeviceRegister('18',self.conn);
            self.lastSample = DeviceRegister('24',self.conn);
            self.lastSample(2) = DeviceRegister('28',self.conn);
            self.holdOffReg = DeviceRegister('2C',self.conn);
            self.adcReg = DeviceRegister('30',self.conn);
            self.debugReg = DeviceRegister('34',self.conn);
            self.lockInRegs = DeviceRegister.empty;
            for nn = 0:3
                self.lockInRegs(nn + 1) = DeviceRegister(hex2dec('40') + nn*4,self.conn);
            end
            self.extReg = DeviceRegister('50',self.conn);
            self.dpgReg = DeviceRegister('60',self.conn);
            self.auxReg = DeviceRegister('70',self.conn);
            %
            % Fast-filtering parameters
            %
            self.trigEdge = DeviceParameter([0,0],self.topReg)...
                .setLimits('lower',0,'upper',1);
            self.inputSelect = DeviceParameter([1,1],self.topReg)...
                .setLimits('lower',0,'upper',1);
            self.outputSelect = DeviceParameter([2,3],self.topReg)...
                .setLimits('lower',0,'upper',3);
            self.trigEnable = DeviceParameter([4,4],self.topReg)...
                .setLimits('lower',0,'upper',1);
            self.enableGating = DeviceParameter([5,7],self.topReg)...
                .setLimits('lower',0,'upper',2^3-1);
            self.log2AvgsFast = DeviceParameter([0,4],self.fastFiltReg)...
                .setLimits('lower',0,'upper',31);
            self.shiftFast = DeviceParameter([5,10],self.fastFiltReg)...
                .setLimits('lower',0,'upper',10);
            self.delay = DeviceParameter([0,31],self.delayReg)...
                .setLimits('lower',64e-9,'upper',(2^32-1)/self.CLK)...
                .setFunctions('to',@(x) x*self.CLK,'from',@(x) x/self.CLK);
            self.numSamples = DeviceParameter([0,31],self.numSamplesReg)...
                .setLimits('lower',0,'upper',16384);
            self.holdOff = DeviceParameter([0,31],self.holdOffReg)...
                .setLimits('lower',0,'upper',(2^32-1)/self.CLK)...
                .setFunctions('to',@(x) x*self.CLK,'from',@(x) x/self.CLK);
            %
            % Slow filtering parameters
            %
            self.log2AvgsSlow = DeviceParameter([0,4],self.slowFiltReg)...
                .setLimits('lower',0,'upper',31);
            self.shiftSlow = DeviceParameter([5,10],self.slowFiltReg)...
                .setLimits('lower',0,'upper',10);
            %
            % DAC output
            %
            self.dac = DeviceParameter([0,15],self.dacReg,'int16')...
                .setLimits('lower',-1,'upper',1)...
                .setFunctions('to',@(x) x/self.CONV_DAC,'from',@(x) x*self.CONV_DAC);    
            self.dac(2) = DeviceParameter([16,31],self.dacReg,'int16')...
                .setLimits('lower',-1,'upper',1)...
                .setFunctions('to',@(x) x/self.CONV_DAC,'from',@(x) x*self.CONV_DAC); 
            %
            % Lock-in control
            %
            self.lockin = DataAcquisitionLockInControl(self,self.lockInRegs);
            %
            % External outputs
            %
            self.ext_o = DeviceParameter([0,7],self.extReg);
        end
        
        function self = setDefaults(self,varargin)
            %SETDEFAULTS Sets parameter values to their defaults
            %
            %   SELF = SETDEFAULTS(SELF) sets default values for SELF
            self.trigEdge.set(1);
            self.trigEnable.set(1);
            self.inputSelect.set(0);
            self.outputSelect.set(0);
            self.enableGating.set(0);
            self.log2AvgsFast.set(0);
            self.shiftFast.set(0);
            self.delay.set(100e-9);
            self.numSamples.set(100);
            self.holdOff.set(10e-3);
            self.log2AvgsSlow.set(10);
            self.shiftSlow.set(0);
            self.dac(1).set(0);
            self.dac(2).set(0);
            self.lockin.setDefaults;
            self.ext_o.set(0);
        end
        
        function self = check(self)
            %CHECK Checks parameter values and makes sure that they are
            %within acceptable ranges.  Throws errors if they are not
        end
        
        function self = upload(self)
            %UPLOAD Uploads register values to the device
            %
            %   SELF = UPLOAD(SELF) uploads register values associated with
            %   object SELF
            
            %
            % Check parameters
            %
            self.check;
            %
            % Write data
            %
            self.conn.keepAlive = true;
            self.topReg.write;
            self.fastFiltReg.write;
            self.delayReg.write;
            self.numSamplesReg.write;
            self.holdOffReg.write;
            self.slowFiltReg.write;
            self.dacReg.write;
            self.conn.keepAlive = false;
            self.lockInRegs.write;
            self.extReg.write;
        end
        
        function self = fetch(self)
            %FETCH Retrieves parameter values from the device
            %
            %   SELF = FETCH(SELF) retrieves values and stores them in
            %   object SELF
            
            %
            % Fetch register data
            %
            self.conn.keepAlive = true;
            self.topReg.read;
            self.fastFiltReg.read;
            self.delayReg.read;
            self.numSamplesReg.read;
            self.holdOffReg.read;
            self.slowFiltReg.read;
            self.dacReg.read;
            self.adcReg.read;
            self.debugReg.read;
            self.lockInRegs.read;
            self.extReg.read;
            self.conn.keepAlive = false;
            self.lastSample.read;
            %
            % Get parameter data from registers
            %
            self.trigEdge.get;
            self.trigEnable.get;
            self.inputSelect.get;
            self.outputSelect.get;
            self.enableGating.get;
            self.log2AvgsFast.get;
            self.shiftFast.get;
            self.delay.get;
            self.numSamples.get;
            self.holdOff.get;
            self.log2AvgsSlow.get;
            self.shiftSlow.get;
            for nn = 1:numel(self.dac)
                self.dac(nn).get;
            end
            self.lockin.get;
            self.ext_o.get;
        end
        
        function self = start(self)
            %START starts fast acquisition
            %
            %   SELF = START(SELF) starts acquisition on object SELF
            
            self.trigReg.set(1,[0,0]).write;
            self.trigReg.set(0,[0,0]);
        end
        
        function self = reset(self)
            %RESET resets the FIFO
            %
            %   SELF = RESET(SELF) resets the slow acquisition FIFO
            
            self.trigReg.set(1,[1,1]).write;
            self.trigReg.set(0,[1,1]);
        end
        
        function self = dpgReset(self)
            %DPGRESET resets the DPG
            %
            %   SELF = DPGRESET resets the DPG
            self.trigReg.set(1,[2,2]).write;
            self.trigReg.set(0,[2,2]);
        end
        
        function self = memoryReset(self)
            %MEMORYRESET Resets the two block memories
            
            self.auxReg.write;
        end
        
        function r = convert2volts(self,x)
            %CONVERT2VOLTS Converts an ADC value to volts
            %
            %   R = CONVERT2VOLTS(SELF,X) converts value X to volts R
            if strcmpi(self.jumpers,'hv')
                c = self.CONV_ADC_HV;
            elseif strcmpi(self.jumpers,'lv')
                c = self.CONV_ADC_LV;
            end
            r = x*c;
        end
        
        function r = convert2int(self,x)
            %CONVERT2INT Converts an ADC voltage to integer values
            %
            %   R = CONVERT2INT(SELF,X) converts voltage X to integer R
            if strcmpi(self.jumpers,'hv')
                c = self.CONV_ADC_HV;
            elseif strcmpi(self.jumpers,'lv')
                c = self.CONV_ADC_LV;
            end
            r = x/c;
        end
        
        function r = readADC(self)
            %READADC Reads and returns the current ADC voltage
            %
            %   V = READADC(SELF) Reads the current ADC voltages V for
            %   device SELF
            self.adcReg.read;
            tmp = typecast(self.adcReg.value,'uint8');
            x(1) = typecast(tmp(1:2),'int16');
            x(2) = typecast(tmp(3:4),'int16');
            x = double(x);
            if strcmpi(self.jumpers,'lv')
                r = x*self.CONV_ADC_LV;
            elseif strcmpi(self.jumpers,'hv')
                r = x*self.CONV_ADC_HV;
            end
        end
        
        function self = getRAM(self,numSamples)
            %GETRAM Fetches recorded in block memory from the device
            %
            %   SELF = GETRAM(SELF) Retrieves current number of recorded
            %   samples from the device SELF
            %
            %   SELF = GETRAM(SELF,N) Retrieves N samples from device
            
            if nargin < 2
                self.conn.keepAlive = true;
                self.lastSample(1).read;
                self.conn.keepAlive = false;
                numSamples = self.lastSample(1).value;
            end
            self.conn.write(0,'mode','command','cmd',...
                {'./fetchRAM',sprintf('%d',round(numSamples))},...
                'return_mode','file');
            raw = typecast(self.conn.recvMessage,'uint8');
            if strcmpi(self.jumpers,'hv')
                c = self.CONV_ADC_HV;
            elseif strcmpi(self.jumpers,'lv')
                c = self.CONV_ADC_LV;
            end
            d = self.convertData(raw,c);
            self.data = d;
            dt = self.CLK^-1 * 2^(self.log2AvgsFast.value);
            self.t = dt*(0:(size(self.data,1)-1));
        end
        
        function self = getIQ(self,numSamples)
            %GETIQ Fetches recorded in block memory from the device
            %corresponding to the I/Q data from the lock-in detector
            %
            %   SELF = GETIQ(SELF) Retrieves current number of recorded
            %   samples from the device SELF
            %
            %   SELF = GETIQ(SELF,N) Retrieves N samples from device
            
            if nargin < 2
                self.conn.keepAlive = true;
                self.lastSample(2).read;
                self.conn.keepAlive = false;
                numSamples = self.lastSample(2).value;
            end
            self.conn.write(0,'mode','command','cmd',...
                {'./fetchIQ',sprintf('%d',round(numSamples))},...
                'return_mode','file');
            raw = typecast(self.conn.recvMessage,'uint8');
            if strcmpi(self.jumpers,'hv')
                c = self.CONV_ADC_HV;
            elseif strcmpi(self.jumpers,'lv')
                c = self.CONV_ADC_LV;
            end
            d = self.convertData(raw,c);
            self.data = d;
            dt = self.CLK^-1 * 2^(self.lockin.cicRate.value);
            self.t = dt*(0:(size(self.data,1)-1));
        end
        
        function self = getFIFO(self,numSamples)
            %GETFIFO Saves data continuously into FIFO
            %
            %   SELF = GETFIFO(SELF,N) Retrieves N samples from device

            self.conn.write(0,'mode','command','cmd',...
                {'./fetchRAM','-t',sprintf('%d',round(numSamples)),'-t',num2str(1)},...
                'return_mode','file');
            raw = typecast(self.conn.recvMessage,'uint8');
            if strcmpi(self.jumpers,'hv')
                c = self.CONV_ADC_HV;
            elseif strcmpi(self.jumpers,'lv')
                c = self.CONV_ADC_LV;
            end
            d = self.convertData(raw,c);
            self.data = d;
            dt = self.CLK^-1 * 2^(self.log2AvgsSlow.value);
            self.t = dt*(0:(size(self.data,1)-1));
        end
        
        function writeDPG(self,t,v)
            %WRITEDPG Writes data to the DPG
            %
            %   WRITEDPG(T,V) Writes data V at times T.  T should be an Nx1
            %   array of times in seconds, and V should be an NxM array
            %   where M < 8 comprised of 0's and 1's
            if numel(t) ~= size(v,1)
                error('Number of data points must be the same as the number of times!');
            elseif size(v,2) > 8
                error('Only 8 channels can be provided');
            elseif size(v,2) > 1 && (~all((v(:) == 0) | (v(:) == 1)))
                error('Values can only be 0 or 1');
            end
            
            dt = uint32([round(diff(t(:))*self.CLK);1000]);
            if any(dt > (2^24-1))
                error('Time steps must be less than %.3f',(2^24-1)/self.CLK);
            end
            v = uint32(sum(v.*2.^(0:(size(v,2)-1)),2));
            dt(end + 1) = 0;
            v(end + 1) = 0;
            d = zeros(numel(dt) + 1,1,'uint32');
            d(1) = uint32(self.dpgReg.addr);
            d(2:end) = dt + bitshift(v,24);
            self.dpgReset;
            self.conn.write(d,'mode','command','cmd',...
                {'./writeFile',sprintf('%d',round(numel(d) - 1))});
        end
        
        function disp(self)
            strwidth = 25;
            fprintf(1,'DataAcquisition object with properties:\n');
            fprintf(1,'\t Registers\n');
            self.topReg.print('topReg',strwidth);
            self.fastFiltReg.print('fastFiltReg',strwidth);
            self.delayReg.print('delayReg',strwidth);
            self.numSamplesReg.print('numSamplesReg',strwidth);
            self.slowFiltReg.print('slowFiltReg',strwidth);
            self.dacReg.print('dacReg',strwidth);
            fprintf(1,'\t ----------------------------------\n');
            fprintf(1,'\t Parameters\n');
            self.trigEdge.print('Trigger edge',strwidth,'%d');
            self.trigEnable.print('Trigger enable',strwidth,'%d');
            self.inputSelect.print('Input select',strwidth,'%d');
            self.outputSelect.print('Output select',strwidth','%d');
            self.enableGating.print('Enable gating',strwidth,'%d');
            self.log2AvgsFast.print('Log 2 # Avgs (Fast)',strwidth,'%d');
            self.shiftFast.print('Fast shift left',strwidth,'%d');
            self.delay.print('Delay',strwidth,'%.3e','s');
            self.numSamples.print('Number of samples',strwidth,'%d');
            self.log2AvgsSlow.print('Log 2 # Avgs (Slow)',strwidth,'%d');
            self.shiftSlow.print('Slow shift left',strwidth,'%d');
            self.dac(1).print('DAC 1',strwidth,'%.3f','V');
            self.dac(2).print('DAC 2',strwidth,'%.3f','V');
            self.lockin.print(strwidth);
            self.ext_o.print('Digital outputs',strwidth,'%02x');
        end
        
        function r = rotate(self,ph,v)
            if nargin == 2
                v = self.data;
            end
            ph = -ph;
            r(:,1) = cosd(ph)*v(:,1) + sind(ph)*v(:,2);
            r(:,2) = -sind(ph)*v(:,1) + cosd(ph)*v(:,2);
        end
        
        function r = getOptimumPhase(self,v,subtract_mean)
            if nargin == 1
                v = self.data;
                subtract_mean = true;
            elseif nargin == 2
                subtract_mean = true;
            elseif nargin == 3
                if isempty(v)
                    v = self.data;
                end
            end
            if subtract_mean
                I = v(:,1) - mean(v(1:1e2,1));
                Q = v(:,2) - mean(v(1:1e2,2));
            else
                I = v(:,1);
                Q = v(:,2);
            end
            f = @(ph) -sum((cosd(ph)*I - sind(ph)*Q).^2);
            r = fminbnd(f,0,360);
        end
        
        
    end
    
    methods(Static)
        function d = loadData(filename,dt,c)
            if nargin == 0 || isempty(filename)
                filename = 'SavedData.bin';
            end
            
            %Load data
            fid = fopen(filename,'r');
            fseek(fid,0,'eof');
            fsize = ftell(fid);
            frewind(fid);
            x = fread(fid,fsize,'uint8');
            fclose(fid);
            
            d.v = DataAcquisition.convertData(x,c);
            d.t = dt*(0:(size(d.v,1)-1));
        end
        
        function v = convertData(raw,c)
            %CONVERTDATA Converts raw data into proper int16/double format
            %
            %   V = CONVERTDATA(RAW) Unpacks raw data from uint8 values to
            %   a pair of double values for each measurement
            %
            %   V = CONVERTDATA(RAW,C) uses conversion factor C in the
            %   conversion
            
            if nargin < 2
                c = 1;
            end
            
            Nraw = numel(raw);
            d = zeros(Nraw/4,2,'int16');
            
            mm = 1;
            for nn = 1:4:Nraw
                d(mm,1) = typecast(uint8(raw(nn + (0:1))),'int16');
                d(mm,2) = typecast(uint8(raw(nn + (2:3))),'int16');
                mm = mm + 1;
            end
            
            v = double(d)*c;
        end
    end
    
end