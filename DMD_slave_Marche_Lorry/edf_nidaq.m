classdef edf_nidaq < handle
    
    properties (Constant = true)
        ID = "Dev1"; % ID of the hardware NIDAQ : do not change
        AnalogChannelID="ao0"; %  analogoutput hardware cable & ID
        %DigitalChannelID="port0/line0";  % digitaloutput hardware cable
        DigitalChannelID="port0/line0";  % digitaloutput hardware cable
        Rate=5000; % value of samples per second. 
        AnalogChannelID2="ao1";
        
    end
    
    properties (GetAccess = public, SetAccess = public)
        d; %hardware device
        
        %output properties
        TRamp = 100 ; % Time expressed in ms given to the lens to explore whole the FP range ;
        TSave= 20 ; % Time expressed in ms given to the camera for saving data ;
        ElementarySizeO; %meaning that output total size = NumberSpeckles*ElementarySize
        ZMin=0 ; % given by the the user, expressed in um default = 0
        ZMax=10 ;% given by the the user, expressed in um default = 10
        MinZMin=0;% in um, Piezo-min
        MaxZMax=100% in um, Piezo-max
        MaxUMax=10%; V max voltage for piezo analog input
        MinUMin=0;%V min voltage for piezo analog input
        AOTable; % data table 
        AO; %analog output ( => piezo)
        DO; % digital output ( trigger =>DMD) 0 or 5V
        ATO; % analog trigger output => camera 0 or 3.3V
        DOTable;
        NumberSpeckles=200;
        ATOTable ;
        AOTableStairs;

        %Digital Output
        
    end
    
    methods 
        
        function obj=edf_nidaq()
            obj.d=daq("ni");
            SetRate(obj);
            %analog output
            SetElementarySizeO(obj);
            obj.AO=addoutput(obj.d,obj.ID,obj.AnalogChannelID,"Voltage");
            obj.DO=addoutput(obj.d,obj.ID,obj.DigitalChannelID,"Digital");
            obj.ATO=addoutput(obj.d,obj.ID,obj.AnalogChannelID2,"Voltage");
            SetAOTable(obj);
            SetDOTable(obj);
            SetATOTable(obj);
            SetAOTableStairs(obj);
                
        end
        
        %Rate
        
        function SetRate(obj)
            obj.d.Rate=obj.Rate;
        end
        
        %TRamp
        function GetTRamp(obj)
            disp(obj.TRamp)
        end
        
        function SetTRamp(obj,Value)
            obj.TRamp=Value; % changes the value of TRamp ( Value must be in ms )
            SetElementarySizeO(obj); % updates the AO size;
        end
        
        %TSave
        function GetTSave(obj)
            disp(obj.TSave)
        end
        
        function SetTSave(obj,Value)
            obj.TSave=Value; % changes the value of TRamp ( Value must be in ms )
            SetElementarySizeO(obj); % updates the AO size;
        end
        
        %AO
        function GetElementarySizeO(obj)
            disp(obj.ElementarySizeO);
        end
        
        function SetElementarySizeO(obj)
            obj.ElementarySizeO= obj.Rate*(obj.TRamp + obj.TSave)/1000 ; % Toutput (s) = Sizeoutput/Rate
            SetAOTable(obj);
            SetDOTable(obj);
            SetATOTable(obj);
            SetAOTableStairs(obj);
        end
        
        function SetAOTableStairs(obj,ZRange)
            if nargin <2
                ZRange=0.1; %um
            end
            obj.AOTableStairs=obj.ZMin:ZRange:obj.ZMax; %list of z
            obj.AOTableStairs=(obj.AOTableStairs-obj.MinZMin)/(obj.MaxZMax-obj.MinZMin); % converts between 0,1
            obj.AOTableStairs=obj.AOTableStairs*(obj.MaxUMax-obj.MinUMin)+obj.MinUMin; %converts between MinUMin and MaxUMax
            %Size=ExTime*obj.Rate/1000;
        end
     
        
        function SetAOTable(obj)
            UMin=(obj.ZMin-obj.MinZMin)/(obj.MaxZMax-obj.MinZMin); % converts between 0,1
            UMin=UMin*(obj.MaxUMax-obj.MinUMin)+obj.MinUMin;%converts between MinUMin and MaxUMax
            UMax=(obj.ZMax-obj.MinZMin)/(obj.MaxZMax-obj.MinZMin); % converts between 0,1
            UMax=UMax*(obj.MaxUMax-obj.MinUMin)+obj.MinUMin; %converts between MinUMin and MaxUMax
            NAO=obj.ElementarySizeO;
            tr=obj.TRamp/(obj.TRamp+obj.TSave);
            obj.AOTable=[linspace(UMin,UMax,floor(tr*NAO))';ones(floor((1-tr)*NAO)+1,1)*UMin];
            obj.AOTable=repmat(obj.AOTable,obj.NumberSpeckles,1);
        end
        
        function SetDOTable(obj)
            NAO=obj.ElementarySizeO;
            tr=obj.TRamp/(obj.TRamp+obj.TSave);
            %obj.DOTable=[zeros(floor(tr*NAO),1);ones(floor((1-tr)*NAO)+1,1)]; % changed in order to solve the perfect desync
            obj.DOTable=[ones(floor(tr*NAO),1);zeros(floor((1-tr)*NAO)+1,1)];
            obj.DOTable=repmat(obj.DOTable,obj.NumberSpeckles,1);
        end
        
        function SetATOTable(obj)
            NAO=obj.ElementarySizeO;
            tr=obj.TRamp/(obj.TRamp+obj.TSave);
            obj.ATOTable=[zeros(floor(tr*NAO),1);3.3*ones(floor((1-tr)*NAO)+1,1)];
            obj.ATOTable=repmat(obj.ATOTable,obj.NumberSpeckles,1);
        end

        %ScanRange:
        function GetScanRange(obj)
            disp(obj.ZMin);
            disp(obj.ZMax);
        end
        
        function SetZMin(obj,Value)
            obj.ZMin=Value;
            SetAOTable(obj);  % updates the AO data;
            SetAOTableStairs(obj);
        end
        
       function SetZMax(obj,Value)
            obj.ZMax=Value;
            SetAOTable(obj);  % updates the AO data;
            SetAOTableStairs(obj);
        end
        %NumberOfSpeckle
        
        function SetNumberSpeckles(obj,Value)
            obj.NumberSpeckles=Value;
            SetAOTable(obj);
            SetDOTable(obj);
            SetATOTable(obj);
            SetAOTableStairs(obj);
        end
        
        %Generation of analog signal
        
        function GenerateOutput(obj)
           write(obj.d,[obj.AOTable, obj.DOTable, obj.ATOTable]);
        end
         
        function SetAnalogFocus(obj,Value,ExTime)
            if nargin <3
                ExTime=obj.TRamp;
            end
            if Value<obj.MinZMin  | Value>obj.MaxZMax
                disp("z is not correct")
            else
            Value=(Value-obj.MinZMin)/(obj.MaxZMax-obj.MinZMin); % converts between 0,1
            Value=Value*(obj.MaxUMax-obj.MinUMin)+obj.MinUMin; %converts between MinUMin and MaxUMax
            Size=ExTime*obj.Rate/1000;
            Data=Value*ones(Size,1);
            write(obj.d,[Data, zeros(Size,1), zeros(Size,1)]);
            %disp(Value);
            end
        end
        
        
        function Start(obj)
            start(obj.d)
        end
        function Stop(obj)
            stop(obj.d)
        end
        
%         function SafetyCheck(obj)
%         end
    end  
end
    

