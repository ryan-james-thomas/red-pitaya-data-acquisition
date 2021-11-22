classdef DataAcquisitionLockInControl < handle
    %DATAACQUISITIONLOCKINCONTROL Defines a class for handling the laser servo
    %lock-in detector
    
    properties(SetAccess = immutable)
        driveFreq       %Driving frequency
        demodFreq       %Demodulation frequency
        demodPhase      %Demodulation phase
        cicRate         %Log2(CIC decimation rate)
        shift           %Log2(division of filtered signals)
        driveAmp        %Driving amplitude as multiplier
    end
    
    properties(SetAccess = protected)
        parent          %Parent object for the lock-in module
    end
    
    properties(Constant)
        DDS_WIDTH = 27; %Width of DDS phase increment
    end
    
    methods
        function self = DataAcquisitionLockInControl(parent,regs)
            %DATAACQUISITIONLOCKINCONTROL Creates an instance of the object
            %
            %   SELF = DATAACQUISITIONLOCKINCONTROL(PARENT,REGS) creates an
            %   instance SELF with parent object PARENT and registers REGS
            
            self.parent = parent;
            
            self.driveFreq = DeviceParameter([0,26],regs(1))...
                .setLimits('lower',0,'upper',50e6)...
                .setFunctions('to',@(x) x/self.parent.CLK*2^(self.DDS_WIDTH),'from',@(x) x*self.parent.CLK/2^(self.DDS_WIDTH));
            
            self.demodFreq = DeviceParameter([0,26],regs(2))...
                .setLimits('lower',0,'upper',50e6)...
                .setFunctions('to',@(x) x/self.parent.CLK*2^(self.DDS_WIDTH),'from',@(x) x*self.parent.CLK/2^(self.DDS_WIDTH));
            
            self.demodPhase = DeviceParameter([0,26],regs(3))...
                .setLimits('lower',-360,'upper',360)...
                .setFunctions('to',@(x) mod(x,360)/360*2^(self.DDS_WIDTH),'from',@(x) x*360/2^(self.DDS_WIDTH));
            
            self.cicRate = DeviceParameter([8,11],regs(4))...
                .setLimits('lower',2,'upper',13);

            self.shift = DeviceParameter([12,15],regs(4))...
                .setLimits('lower',0,'upper',16);
            
            self.driveAmp = DeviceParameter([0,7],regs(4))...
                .setLimits('lower',0,'upper',1)...
                .setFunctions('to',@(x) x*255,'from',@(x) x/255);
        end
        
        function self = setDefaults(self)
            %SETDEFAULTS Sets the default values for the lock-in module
            %
            %   SELF = SETDEFAULTS(SELF) sets the default values for object
            %   SELF
            
            self.driveFreq.set(3e6);
            self.demodFreq.set(3e6);
            self.demodPhase.set(0);
            self.cicRate.set(7);
            self.shift.set(12);
            self.driveAmp.set(1);
        end
        
        function self = get(self)
            %GET Retrieves parameter values from associated registers
            %
            %   SELF = GET(SELF) Retrieves values for parameters associated
            %   with object SELF
            self.driveFreq.get;
            self.demodFreq.get;
            self.demodPhase.get;
            self.cicRate.get;
            self.shift.get;
            self.driveAmp.get;
        end

        function ss = print(self,width)
            %PRINT Prints a string representing the object
            %
            %   S = PRINT(SELF,WIDTH) returns a string S representing the
            %   object SELF with label width WIDTH.  If S is not requested,
            %   prints it to the command line
            s{1} = self.driveFreq.print('Drive frequency [Hz]',width,'%.3e');
            s{2} = self.demodFreq.print('Demod. frequency [Hz]',width,'%.3e');
            s{3} = self.demodPhase.print('Demod. phase [deg]',width,'%.3f');
            s{4} = self.cicRate.print('Log2(CIC decimation)',width,'%d');
            s{5} = self.shift.print('Log2(Div. filt. signals)',width,'%d');
            s{6} = self.driveAmp.print('Drive amplitude',width,'%.3f');
            
            ss = '';
            for nn = 1:numel(s)
                ss = [ss,s{nn}]; %#ok<*AGROW>
            end
            if nargout == 0
                fprintf(1,ss);
            end
        end
        
        function disp(self)
            %DISP Displays the object properties
            disp('DataAcquisitionLockInControl object with properties:');
            disp(self.print(25));
        end
        
        function s = struct(self)
            %STRUCT Creates a struct from the object
            s.driveFreq = self.driveFreq.struct;
            s.demodFreq = self.demodFreq.struct;
            s.demodPhase = self.demodPhase.struct;
            s.cicRate = self.cicRate.struct;
            s.shift = self.shift.struct;
            s.driveAmp = self.driveAmp.struct;
        end
        
        function self = loadstruct(self,s)
            %LOADSTRUCT Loads a struct into the object
            self.driveFreq.set(s.driveFreq.value);
            self.demodFreq.set(s.demodFreq.value);
            self.demodPhase.set(s.demodPhase.value);
            self.cicRate.set(s.cicRate.value);
            self.shift.set(s.shift.value);
            self.driveAmp.set(s.driveAmp.value);
        end
        
    end
    
end