classdef DataAcquisitionTDC < handle
    %DATAACQUISITIONTDC Defines a class for handling the time-to-digital
    %module
    
    properties(SetAccess = immutable)
        threshold       %Threshold value for triggering
        hysteresis      %Hysteresis value for re-arming
        edgeSelect      %Which edges to trigger on
        numSamples      %Number of samples to acquire
    end
    
    properties(SetAccess = protected)
        parent          %Parent object for the TDC module
    end
    
    properties(Constant)
        DDS_WIDTH = 27; %Width of DDS phase increment
    end
    
    methods
        function self = DataAcquisitionTDC(parent,regs)
            %DATAACQUISITIONTDC Creates an instance of the object
            %
            %   SELF = DATAACQUISITIONTDC(PARENT,REGS) creates an
            %   instance SELF with parent object PARENT and registers REGS
            
            self.parent = parent;
            
            self.threshold = DeviceParameter([0,15],regs(1))...
                .setLimits('lower',-1,'upper',1)...
                .setFunctions('to',@(x) self.parent.convert2int(x),'from',@(x) self.parent.convert2volts);
            
            self.hysteresis = DeviceParameter([16,31],regs(1))...
                .setLimits('lower',-1,'upper',1)...
                .setFunctions('to',@(x) self.parent.convert2int(x),'from',@(x) self.parent.convert2volts);
            
            self.edgeSelect = DeviceParameter([30,31],regs(2))...
                .setLimits('lower',0,'upper',3);
            
            self.numSamples = DeviceParameter([0,29],regs(2))...
                .setLimits('lower',0,'upper',2^12 - 1);

        end
        
        function self = setDefaults(self)
            %SETDEFAULTS Sets the default values for the lock-in module
            %
            %   SELF = SETDEFAULTS(SELF) sets the default values for object
            %   SELF
            
            self.threshold.set(0);
            self.hysteresis.set(50e-3);
            self.edgeSelect.set(0);
            self.numSamples.set(4000);
        end
        
        function self = get(self)
            %GET Retrieves parameter values from associated registers
            %
            %   SELF = GET(SELF) Retrieves values for parameters associated
            %   with object SELF
            self.threshold.get;
            self.hysteresis.get;
            self.edgeSelect.get;
            self.numSamples.get;
        end

        function ss = print(self,width)
            %PRINT Prints a string representing the object
            %
            %   S = PRINT(SELF,WIDTH) returns a string S representing the
            %   object SELF with label width WIDTH.  If S is not requested,
            %   prints it to the command line
            s{1} = self.threshold.print('TDC threshold',width,'%.3f');
            s{2} = self.hysteresis.print('TDC hysteresis',width,'%.3f');
            s{3} = self.edgeSelect.print('TDC edge selector',width,'%d');
            s{4} = self.numSamples.print('TDC number of samples',width,'%d');
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
            disp('DataAcquisitionTDC object with properties:');
            disp(self.print(25));
        end
        
        function s = struct(self)
            %STRUCT Creates a struct from the object
            s.threshold = self.threshold.struct;
            s.hysteresis = self.hysteresis.struct;
            s.edgeSelect = self.edgeSelect.struct;
            s.numSamples = self.numSamples.struct;
        end
        
        function self = loadstruct(self,s)
            %LOADSTRUCT Loads a struct into the object
            self.threshold.set(s.threshold.value);
            self.hysteresis.set(s.hysteresis.value);
            self.edgeSelect.set(s.edgeSelect.value);
            self.numSamples.set(s.numSamples.value);
        end
        
    end
    
end