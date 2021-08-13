classdef DeviceControl < handle
    properties
        t
        data
        jumpers
    end
    
    properties(SetAccess = immutable)
        conn
        
    end
    
    properties(SetAccess = protected)
        % R/W registers
        trigReg
        topReg
    end
    
    properties(Constant)
        CLK = 125e6;
        HOST_ADDRESS = 'rp-f0919a.local';
        INIT_CIC_RATE = 1;
        DDS_WIDTH = 27;
        DAC_WIDTH = 14;
        CONV_LV = 1.1851;
        CONV_HV = 29.3570;
    end
    
    methods
        function self = DeviceControl(varargin)
            if numel(varargin)==1
                self.conn = ConnectionClient(varargin{1});
            else
                self.conn = ConnectionClient(self.HOST_ADDRESS);
            end
            
            self.jumpers = 'hv';
            
            % R/W registers
            self.trigReg = DeviceRegister('0',self.conn);
            self.topReg = DeviceRegister('4',self.conn);
            
        end
        
        function self = setDefaults(self,varargin)
            
        end
        
        function self = check(self)

        end
        
        function self = upload(self)
            self.check;
            self.topReg.write;
        end
        
        function self = fetch(self)
            %Read registers
            self.topReg.read;
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
            strwidth = 36;
            fprintf(1,'SlowAcquisition object with properties:\n');
            fprintf(1,'\t Registers\n');
            self.topReg.makeString('topReg',strwidth);
            fprintf(1,'\t ----------------------------------\n');
            fprintf(1,'\t Parameters\n');
            % fprintf(1,'\t\t%25s: %d\n','CIC Rate (log2)',self.cicRate.value);
            % fprintf(1,'\t\t%25s: %.3g\n','Freq [Hz]',self.freq.value);
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

            v = double(d)/2^(DeviceControl.DAC_WIDTH-1)*c;
        end
    end
    
end