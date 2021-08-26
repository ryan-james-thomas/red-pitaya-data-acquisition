classdef DeviceControl < handle
    properties
        t
        data
        jumpers
    end
    
    properties(SetAccess = immutable)
        conn
        dac
    end
    
    properties(SetAccess = protected)
        % R/W registers
        trigReg
        topReg
        dacReg
    end
    
    properties(Constant)
        CLK = 125e6;
        HOST_ADDRESS = 'rp-f0919a.local';
        INIT_CIC_RATE = 1;
        DDS_WIDTH = 27;
        DAC_WIDTH = 14;
        ADC_WIDTH = 14;
        CONV_LV = 1.1851/2^(DeviceControl.DAC_WIDTH - 1);
        CONV_HV = 29.3570/2^(DeviceControl.DAC_WIDTH - 1);
    end
    
    methods
        function self = DeviceControl(varargin)
            if numel(varargin)==1
                self.conn = ConnectionClient(varargin{1});
            else
                self.conn = ConnectionClient(self.HOST_ADDRESS);
            end
            
            self.jumpers = 'lv';
            
            % R/W registers
            self.trigReg = DeviceRegister('0',self.conn);
            self.topReg = DeviceRegister('4',self.conn);
            self.dacReg = DeviceRegister('8',self.conn);
            
            
            self.dac = DeviceParameter([0,15],self.dacReg,'int16')...
                .setLimits('lower',-1,'upper',1)...
                .setFunctions('to',@(x) self.convert2int(x),'from',@(x) self.convert2volts(x));
            
            self.dac(2) = DeviceParameter([16,31],self.dacReg,'int16')...
                .setLimits('lower',-1,'upper',1)...
                .setFunctions('to',@(x) self.convert2int(x),'from',@(x) self.convert2volts(x));
        end
        
        function self = setDefaults(self,varargin)
            self.dac(1).set(0);
            self.dac(2).set(0);
        end
        
        function self = check(self)

        end
        
        function self = upload(self)
            self.check;
            self.topReg.write;
            self.dacReg.write;
        end
        
        function self = fetch(self)
            %Read registers
            self.topReg.read;
            self.dacReg.read;
            
            for nn = 1:numel(self.dac)
                self.dac(nn).get;
            end
        end
        
        function r = convert2volts(self,x)
            if strcmpi(self.jumpers,'hv')
                c = self.CONV_HV;
            elseif strcmpi(self.jumpers,'lv')
                c = self.CONV_LV;
            end
            r = x*c;
        end
        
        function r = convert2int(self,x)
            if strcmpi(self.jumpers,'hv')
                c = self.CONV_HV;
            elseif strcmpi(self.jumpers,'lv')
                c = self.CONV_LV;
            end
            r = x/c;
        end
        
        function self = getData(self,numSamples)
            self.conn.write(0,'mode','get data','numSamples',numSamples);
            raw = typecast(self.conn.recvMessage,'uint8');
            if strcmpi(self.jumpers,'hv')
                c = self.CONV_HV;
            elseif strcmpi(self.jumpers,'lv')
                c = self.CONV_LV;
            end
            d = self.convertData(raw,c);
            self.data = d;
            self.t = 1/self.CLK*self.INIT_CIC_RATE*2^self.cicRate.value*(0:(numSamples-1));
        end
        
        function disp(self)
            strwidth = 20;
            fprintf(1,'DeviceControl object with properties:\n');
            fprintf(1,'\t Registers\n');
            self.topReg.makeString('topReg',strwidth);
            fprintf(1,'\t ----------------------------------\n');
            fprintf(1,'\t Parameters\n');
            self.dac(1).print('DAC 1',strwidth,'%.3f');
            self.dac(2).print('DAC 2',strwidth,'%.3f');
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
            
            d.v = DeviceControl.convertData(x,c);
            d.t = dt*(0:(size(d.v,1)-1));
        end
        
        function v = convertData(raw,c)
            Nraw = numel(raw);
            d = zeros(Nraw/4,2,'int16');
            
            mm = 1;
            for nn = 1:4:Nraw
                d(mm,1) = typecast(uint8(raw(nn+(0:1))),'int16');
                d(mm,2) = typecast(uint8(raw(nn+(2:3))),'int16');
                mm = mm + 1;
            end

            v = double(d)*c;
        end
    end
    
end