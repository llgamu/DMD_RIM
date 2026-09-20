%%%
%%% Class to handle the DMD.
%%%
%%% Set in BINARY_UNINTERRUPTED mode, and by default in MASTER mode.
%%% % new lorry : normal mode instead of uninterrupted !!!!!!!
%%% Able to display a sequence once or in continuous mode.
%%%
%%%
%%% About ROI : only taken into account when loading a sequence on DMD RAM ; after that, 
%%% if you change the ROI and try to run the old sequence, the new ROI won't be applied

classdef DMD < handle & matlab.mixin.CustomDisplay
    properties (Constant)
        lib_path = 'D:\SMARTSCAN\lib\lib_DMD\' % Path to library
        height_DMD = 1200
        width_DMD = 1920
        % parameters of DMD execution
    end
    
    properties (SetObservable, AbortSet)
        mode = 'master' % BE CAREFUL ! NOT FULLY IMPLEMENTED YET
        %mode = 'slave' % BE CAREFUL ! NOT FULLY IMPLEMENTED YET
        
        %default_bin_mode = 'normal'
        default_bin_mode = 'uninterrupted'
        
        bin_storage_mode = 'on'
        
        period = 31.1 % in ms. = picture_time.
        
        display_time = 21 % in ms. = pictime in bin_unitterrupted mode, = illum_time in bin normal
        synch_pulse_width = 1 % in ms. equal to half inttime in uninterrupted mode
        synch_delay = 0 % in ms. NOT VALIDATE HERE Note : is ignored in this code for the uninterrupted mode. Note 2: micromirrors have a ~50us mechanical relax time  
        %TriggerInDelay=10.8;%ms new, used for slave mode
        
        ROI = [0 0 1920 1200]
        ROI_mask = true(1200,1920);
        
    end

    properties (SetAccess = private) % only methods of the class can modify these
        alp_return_value % ALP return code

        device_id = uint32(0) % Device ID
        device_sn = int32(0)
        
        proj_info = table
        
        pic_left_memory
        
        current_seq_id % Current sequence's ID
                
        inverted = 'no'
        
        figure_handle % interface figure handle
        
    end
    
    
    properties (SetAccess = private, SetObservable, AbortSet)
        status = 'Idle'
        seq_list = struct('Name',[],'ID',[],'Size',[])
        seq_disp = 'oneshot' % Sequence display mode ; default, 'oneshot', 'repeat' vs 'loop'
    end

    properties (SetAccess = private, Dependent = true)
       seq_table   
    end
    
    properties (SetAccess = private)
        last_status_check
        last_proj_info_check
    end
   
    methods 
        function obj = DMD(m_or_s) % Class constructor

            % load library before using commands
            if ~libisloaded('alp4395')
                loadlibrary([obj.lib_path,'alp4395.dll'],[obj.lib_path,'alp.h']);
            end

            % Initialize connection to DMD
            [obj.alp_return_value, obj.device_id] = calllib('alp4395','AlpDevAlloc',...
                int32(0), int32(0), uint32(0));%ALP_DEFAULT=0

            
            try % to save close DMD properly in case
                [obj.alp_return_value, obj.device_sn] = calllib('alp4395','AlpDevInquire',...
                    int32(obj.device_id), int32(2000), int32(0));% ALP_DEVICE_NUMBER

                if obj.alp_return_value ~= 0
                    str = ['Failed to initialize connection. ALP return value : ', num2str(obj.alp_return_value)];
                    error(str);
                end

                % Setting the SYNCH OUT 1
                %obj.set_gate(1,1,ones(1,16));
                              
                % AlpProjControl...projection parameters
                if nargin == 0
                    m_or_s = 'master';
                end

                obj.mode = m_or_s;

                % Set and start timer to refresh info periodically
                timestamp = datetime;
                obj.last_status_check = timestamp;
                obj.last_proj_info_check = timestamp;

                %%% Load reference arrays
                % Get rid of the empty entry
                obj.seq_list(1) = [];

                % All white
                obj.loadSequence(true(obj.height_DMD,obj.width_DMD), 'All white');

                % Checkerboard
                n_checker = 64;
                checkerboard_temp = checkerboard(n_checker,ceil(obj.height_DMD/(2*n_checker)),ceil(obj.width_DMD/(2*n_checker))) > 0.5;
                obj.loadSequence(checkerboard_temp(1:obj.height_DMD,1:obj.width_DMD),['checkerboard-',num2str(n_checker)]);
                
            catch ME
                obj.alp_return_value = calllib('alp4395','AlpDevFree', obj.device_id);
                unloadlibrary('alp4395');
                rethrow(ME);
            end
        end
% Farris version        
%         function set_gate(obj, polarity, period, seq)
%             if ismember(polarity,[1,0])
%                 Gated.Polarity = uint8(polarity);
%                 if isreal(period) && period >= 1
%                     Gated.Period = uint8(period); % no need for a property, right ?
%                     
%                     if numel(seq) < 17
%                         seq_temp = ones(1,16);
%                         seq_temp(1:numel(seq)) = seq;
%                         %seq_temp=[0,1];seq_temp=repmat(seq_temp,1,8); % test lorry
%                         Gated.Gate = uint8(seq_temp); %farrus
%                         %Gated.Gate=uint8([1,1,0,1]);
% 
%                         Gated_ptr = libpointer('tAlpDynSynchOutGate', Gated);
%                         obj.alp_return_value = calllib('alp4395','AlpDevControlEx',...
%                             obj.device_id, int32(2023), Gated_ptr ); %ALP_DEV_DYN_SYNCH_OUT1_GATE = 2023
%                         clear Gated_ptr
%                     else
%                         error('Entered seq is not a valid value.');
%                     end
%                 else
%                     error('Entered period is not a valid value.');
%                 end
%                 
%             else
%                 error('Entered polarity is not a valid value.');
%             end
%                 
%         end

%lorry version
        function set_gate(obj, polarity, seq,output_channel)
            if ismember(output_channel,[1,2,3])
                [~,index]=ismember(output_channel,[1,2,3]);
                output_list=[2023,2024,2025];
                if ismember(polarity,[1,0])
                    Gated.Polarity = uint8(polarity);
                    if length(seq) >= 1
                        Gated.Period = uint8(length(seq)); % no need for a property, right ?

                        if numel(seq) < 17
                            %seq_temp = ones(1,16);
                            %seq_temp(1:numel(seq)) = seq;
                            %seq_temp=[0,1];seq_temp=repmat(seq_temp,1,8); % test lorry
                            %Gated.Gate = uint8(seq_temp); %farrus
                            Gated.Gate=uint8(seq);

                            Gated_ptr = libpointer('tAlpDynSynchOutGate', Gated);
                            obj.alp_return_value = calllib('alp4395','AlpDevControlEx',...
                                obj.device_id, int32(output_list(index)), Gated_ptr ); %ALP_DEV_DYN_SYNCH_OUT1_GATE = 2023
                            clear Gated_ptr
                        else
                            error('Entered seq is not a valid value.');
                        end
                    else
                        error('Entered period is not a valid value.');
                    end

                else
                    error('Entered polarity is not a valid value.');
                end
            else 
                 error('channel should belong to [1,2,3]')
            end
                
        end
        
        function varargout = loadSequence(obj, array, seq_name, bit_depth_0) 
            
            % chek if ok with ROI
            array_dims = size(array);
            if ~isequal(array_dims(1:2),obj.ROI(4:-1:3))
                warning('The size of the pattern to be loaded is not consistent with the ROI...! Be careful.');
                ROI_eff = [0,0,array_dims(2),array_dims(1)];
            else
                ROI_eff = obj.ROI;
            end
                      
            if ~islogical(array)
                warning('Non binary array passed. Converting to binary...');
            end
%             test = logical(array) & repmat(obj.ROI_mask,[1 1 size(array,3)]);
            test = logical(array);
            test = test & repmat(obj.ROI_mask,[1 1 size(array,3)]);
            array_transformed = ROI2im(test,ROI_eff,[obj.height_DMD,obj.width_DMD]);
                        
            if nargin < 4
                bit_depth = int32(1); % parameter, should be changeable if we want grey
            else
                bit_depth = int32(bit_depth_0) + ~strcmp(obj.bin_storage_mode,'on')*int32(1); % should validate though...
            end

            picnum = double(strcmp(obj.bin_storage_mode,'on'))*(size(array,3)/bit_depth) + double(~strcmp(obj.bin_storage_mode,'on'))*(size(array,3));
            
            % AlpSeqAlloc... allocate memory for a sequence of images to be shown
            [obj.alp_return_value, seq_id_out] = calllib('alp4395','AlpSeqAlloc', obj.device_id, bit_depth, picnum, uint32(0));
            
            ALP_MEMORY_FULL = 1007;
            if obj.alp_return_value == ALP_MEMORY_FULL
                error('DMD memory full !');
            end
            
            obj.current_seq_id = seq_id_out; % gets the id of the sequence of images in a class variable
            varargout{1} = seq_id_out;
            
            obj.alp_return_value = calllib('alp4395','AlpSeqControl',...
                obj.device_id, obj.current_seq_id, int32(2103), bit_depth); % ALP_BITNUM (bitdepth)
            
            if strcmp(obj.bin_storage_mode,'on')
                array_transformed = obj.bitplaneReshaper(array_transformed);
                obj.alp_return_value = calllib('alp4395','AlpSeqControl',...
                    obj.device_id, obj.current_seq_id, int32(2110), int32(2)); % ALP_DATA_FORMAT -> BINARY_TOPDOWN
            else
                array_transformed = 255*uint8(permute(array_transformed,[2 1 3]));
                 obj.alp_return_value = calllib('alp4395','AlpSeqControl',...
                    obj.device_id, obj.current_seq_id, int32(2110), int32(0)); % ALP_DATA_FORMAT -> MSB_ALIGN
            end     
                      
            % AlpSeqPut.. upload the sequence of images
%             array_ptr = libpointer('voidPtr', array_transformed);
%             picoffset = int32(0);
%             picload = int32(picnum)*(int32(~strcmp(obj.bin_storage_mode,'on'))+int32(bit_depth)*int32(strcmp(obj.bin_storage_mode,'on')));
%             obj.alp_return_value = calllib('alp4395','AlpSeqPut',...
%                 obj.device_id, obj.current_seq_id, picoffset, picload, array_ptr);

            picoffset = int32(0);
            picload = int32(picnum)*(int32(~strcmp(obj.bin_storage_mode,'on'))+int32(bit_depth)*int32(strcmp(obj.bin_storage_mode,'on')));
            obj.alp_return_value = calllib('alp4395','AlpSeqPut',...
                obj.device_id, obj.current_seq_id, picoffset, picload, array_transformed);
            
            if nargin < 3
                seq_info.Name = ['Sequence ',num2str(obj.current_seq_id)];
            else
                seq_info.Name = seq_name;
            end

            seq_info.ID = obj.current_seq_id;
            seq_info.Size = size(array);
            obj.seq_list = [obj.seq_list,seq_info];
        end
               
        function infos = getSeqInfo(obj, seq_ref)

            % Sequence Inquire and Control Types (AlpSeqControl, AlpSeqInquire)
            inquire_codes_w_coded_outputs = {...
             'ALP_BIN_MODE',  2104;    
             'ALP_DATA_FORMAT',  2110;
             'ALP_FLUT_MODE',  2118;
             'ALP_PWM_MODE',  2107;
             'ALP_DMD_MASK_SELECT',  2134};
         
            inquire_codes_w_valued_outputs = {...
             'ALP_BITPLANES',  2200;
             'ALP_BITNUM',  2103;
             'ALP_PICNUM',  2201;
             'ALP_SEQ_REPEAT',  2100;
             'ALP_FIRSTFRAME',  2101;
             'ALP_LASTFRAME',  2102;
             'ALP_FIRSTLINE',  2111;
             'ALP_LASTLINE',  2112;
             'ALP_LINE_INC',  2113;
             'ALP_SCROLL_FROM_ROW',  2123;
             'ALP_SCROLL_TO_ROW',  2124;
             'ALP_PICTURE_TIME',  2203;
             'ALP_MIN_PICTURE_TIME',  2211;
             'ALP_MAX_PICTURE_TIME',  2213;
             'ALP_ILLUMINATE_TIME',  2204;
             'ALP_MIN_ILLUMINATE_TIME',  2212;
             'ALP_ON_TIME',  2214;
             'ALP_OFF_TIME',  2215;
             'ALP_SYNCH_DELAY',  2205;
             'ALP_MAX_SYNCH_DELAY',  2209;
             'ALP_SYNCH_PULSEWIDTH',  2206;
             'ALP_TRIGGER_IN_DELAY',  2207;
             'ALP_MAX_TRIGGER_IN_DELAY',  2210;
             'ALP_SEQ_PUT_LOCK',  2119;
             'ALP_FLUT_ENTRIES9',  2120;
             'ALP_FLUT_OFFSET9',  2122};
         
         return_codes = {...
             {'ALP_BIN_NORMAL',  2105;
             'ALP_BIN_UNINTERRUPTED',  2106};
             {'ALP_DATA_MSB_ALIGN',  0;
             'ALP_DATA_LSB_ALIGN',  1;
             'ALP_DATA_BINARY_TOPDOWN',  2;
             'ALP_DATA_BINARY_BOTTOMUP',  3};
             {'ALP_FLUT_NONE',  0;
             'ALP_FLUT_9BIT',  1;
             'ALP_FLUT_18BIT',  2};
             {'ALP_DEFAULT',  0;
             'ALP_FLEX_PWM',  3};
             {'ALP_DEFAULT',  0;
             'ALP_DMD_MASK_16X16',  1;
             'ALP_DMD_MASK_16X8',  2}};
             
            index = obj.findSeqRef(seq_ref);
            seq_id = obj.seq_list(index).ID;
            
            infos = [inquire_codes_w_coded_outputs;inquire_codes_w_valued_outputs];
            
            for i=1:size(inquire_codes_w_coded_outputs,1) 
                [obj.alp_return_value, info] = calllib('alp4395','AlpSeqInquire',obj.device_id, int32(seq_id), int32(inquire_codes_w_coded_outputs{i,2}), int32(0));
                infos{i,2} = return_codes{i}{[return_codes{i}{:,2}]==info,1};
            end
            
            for j=1:size(inquire_codes_w_valued_outputs,1) 
                [obj.alp_return_value, info] = calllib('alp4395','AlpSeqInquire',obj.device_id, int32(seq_id), int32(inquire_codes_w_valued_outputs{j,2}), int32(0));
                infos{i+j,2} = info;
            end
        end

        function remove(obj, seq_ref)
            % to rewrite
            if strcmp('all',seq_ref)
                nb_seq = size(obj.seq_list,2);
                for i = nb_seq:-1:3
                    seq_id = obj.seq_list(i).ID;
                    obj.alp_return_value = calllib('alp4395','AlpSeqFree',obj.device_id, seq_id);
                    obj.seq_list(i) = [];
                end
            else
                index = obj.findSeqRef(seq_ref);
                seq_id = obj.seq_list(index).ID;

                obj.seq_list(index) = [];

                if seq_id == obj.current_seq_id
                    if ~isempty(obj.seq_list(1).ID)
                        obj.current_seq_id = obj.seq_list(1).ID;
                    else
                        obj.current_seq_id =[];
                    end
                end

                obj.alp_return_value = calllib('alp4395','AlpSeqFree',obj.device_id, seq_id);
            end
        end

        
        function run(obj, varargin) % should implement to pass a non default bin mode

%               Expected inputs : seq_ref, seq_disp, n_repeat
            seq_disp = 'oneshot';
            seq_ref = obj.current_seq_id;

            switch nargin
                case 4
                    seq_ref = varargin{1}; 
                    seq_disp = varargin{2};
                    n_repeat = varargin{3};
                
                case 3
                    if strcmp(varargin{1},'repeat')
                        seq_disp = varargin{1};
                        n_repeat = varargin{2};
                    else
                        seq_ref = varargin{1};
                        seq_disp = varargin{2};
                    end
                case 2
                    if ischar(varargin{1}) && any(ismember({'oneshot','loop'}, varargin{1}))
                        seq_disp = varargin{1};
                    else
                        seq_ref = varargin{1};
                    end
            end

            index = obj.findSeqRef(seq_ref);
            obj.current_seq_id = obj.seq_list(index).ID;
            
            % chek if ok with ROI
            array_dims = obj.seq_list(index).Size;
            if ~isequal(array_dims(1:2),obj.ROI(4:-1:3))
                warning('The size of the pattern to be displayed is not consistent with the ROI...! Be careful.');
            end

            % Should check if it's busy, to stop it before running something else...
            if strcmp(obj.status,'Active')
%                 disp('before');
                return_value = calllib('alp4395','AlpProjWait',obj.device_id); % ALP_PROJ_WAIT : wait for the completion of the seq to give back handle
                if (return_value == 1005) % -> ALP_INVALID_PARAM
                    error('Infinite loop active.');
                end
                
%                 else
%                     disp('Waiting for queue to finish to start displaying this sequence... Otherwise stop the display.');
%                     
%                 end
            end
    
            % Timings
            if strcmp(obj.default_bin_mode,'normal')
                bin_mode_code = int32(2105);
                if (obj.period - obj.display_time + obj.synch_delay + 0.002 < 0) % cf datasheet
                    error('Bad timing ; picture time should be bigger than illumination time + synch delay + 2us.');
                end
                synch_delay_eff = obj.synch_delay;
            else 
                bin_mode_code = int32(2106);
                obj.period = obj.display_time;
                obj.synch_pulse_width = obj.period/2;
                synch_delay_eff = 0;
            end
            
            % Check timings here ! if (
            
            %%old but good 
            obj.alp_return_value = calllib('alp4395','AlpSeqTiming',...
            obj.device_id, obj.current_seq_id, int32(obj.display_time*1000), int32(obj.period*1000), int32(synch_delay_eff*1000), int32(obj.synch_pulse_width*1000), int32(0)); % period (pictime in reality) to send in us
            
            %new for edf timing check
            %obj.alp_return_value = calllib('alp4395','AlpSeqTiming',...
            %obj.device_id, obj.current_seq_id, int32(obj.display_time*1000), int32(obj.period*1000), int32(synch_delay_eff*1000), int32(0), int32(0)); % period (pictime in reality) to send in us
        
 
            obj.alp_return_value = calllib('alp4395','AlpSeqControl',...
                obj.device_id, obj.current_seq_id, int32(2104), bin_mode_code); % ALP_BIN_MODE
            
            % Run sequence

            start_type = 'AlpProjStart';
            switch seq_disp
                case 'loop' % If set to continuous
                    obj.seq_disp = 'loop';
                    start_type = [start_type, 'Cont'];
                case 'oneshot' % If normal 'oneshot' mode
                    obj.seq_disp = 'oneshot';
                case 'repeat' % if 'repeat' mode
                    obj.alp_return_value = calllib('alp4395','AlpSeqControl',...
                        obj.device_id, obj.current_seq_id, int32(2100), int32(n_repeat)); % ALP_SEQ_REPEAT
            end
            
            % Start
            obj.alp_return_value = calllib('alp4395',start_type, obj.device_id, obj.current_seq_id);
        end
        
        function applyMask(obj,seq_ref)
                index = obj.findSeqRef(seq_ref);
                seq_id = obj.seq_list(index).ID;
                ALP_DMD_MASK_SELECT = int32(2134);
                obj.alp_return_value = calllib('alp4395','AlpSeqControl', obj.device_id, seq_id, ALP_DMD_MASK_SELECT, int32(1));
        end
        
        
        function loadMask(obj,mask)
           
            if isequal(size(mask),[75 120])
                if islogical(mask)
                    warning('Non-binary array-passed ; converting to binary.');
                end
                
                % Formatting mask
                mask_eff = reshape(flip(logical(mask')),8,[]);
                pow = 2.^(7:-1:0);
                mask_eff = uint8(pow*mask_eff);
                
                % Sending mask
                mask2send.nRowOffset = int32(0);
                mask2send.nRowCount = int32(75);
                mask2send.Bitmap = padarray(mask_eff,[0 2048-length(mask_eff)],0,'post');
                
                mask2send_ptr = libpointer('tAlpDmdMask', mask2send);
                
                ALP_DMD_MASK_WRITE = int32(2339);
                obj.alp_return_value = calllib('alp4395','AlpProjControlEx', obj.device_id, ALP_DMD_MASK_WRITE, mask2send_ptr);
            else
                error('Wrong mask size ; should be 75x120.');
            end           
        end

        function invert(obj)
            %% NEEDS DMD HALTED TO WORK
            alp_proj_controltype = int32(2306); % ALP_PROJ_INVERSION

            if strcmp(obj.inverted,'no') 
                alp_control_value = int32(1);
                inverted = 'yes';
            else
                alp_control_value = int32(0);
                inverted = 'no';
            end

            obj.alp_return_value = calllib('alp4395','AlpProjControl',obj.device_id, alp_proj_controltype, int32(0));
        
            if obj.alp_return_value == 0
                obj.inverted = inverted;
            end
        end
        
        function test(obj, array)
           % To test an array
           
           obj.loadSequence(array);
           obj.run('loop');          
        end
        
        interface(obj, p_control)
        
        function pause(obj)
            % in continuous mode, it'll finish the current iteration and then pause

            % Halt sequence
            obj.alp_return_value = calllib('alp4395','AlpProjHalt',...
            obj.device_id);
        end
        
                
        % Find sequence by reference
        
        function index = findSeqRef(obj,seq_ref)
            % Note : not good... ismember might already return an array
            % CAREFUL : RETURN ONLY ONE ELEMENT CORRESPONDING TO THE SEARCH
            % : the LAST ONE in ID.
            
            if isnumeric(seq_ref) && rem(seq_ref,1)==0
                index = find(arrayfun(@(s) ismember(seq_ref, s.ID), obj.seq_list));
                if isempty(index)
                    error('Wrong sequence ID.');
                end
            elseif ischar(seq_ref)
                % case insensitive
                index = find(strcmpi({obj.seq_list.Name}, seq_ref)==1);
                if isempty(index)
                    error('Wrong sequence name.');
                end
            else
                error('Wrong ref type.');
            end
            
            index = index(end);
        end
        
        % Get methods
        
        function status_out = get.status(obj)
            timestamp = datetime;
            if milliseconds(timestamp - obj.last_status_check) > 40
                ALP_PROJ_STATE = int32(2400);
                
                [obj.alp_return_value,state] = calllib('alp4395','AlpProjInquire',obj.device_id, ALP_PROJ_STATE, int32(0));

                if state == 1200
                    obj.status = 'Active';
                    status_out = 'Active';
                else
                    obj.status = 'Idle';
                    status_out = 'Idle';
                end
                
                obj.last_status_check = timestamp;
            else
                status_out = obj.status;
            end
        end
        
        function proj_info_out = get.proj_info(obj)
            timestamp = datetime;
            if milliseconds(timestamp - obj.last_status_check) > 40
                ALP_PROJ_PROGRESS = int32(2318);
            
                proj_info_ptr = libpointer('tAlpProjProgress', struct());
                obj.alp_return_value = calllib('alp4395','AlpProjInquireEx',obj.device_id, ALP_PROJ_PROGRESS, proj_info_ptr);
                new_proj_info = struct2table(proj_info_ptr.Value);

                obj.proj_info = new_proj_info;
                proj_info_out = new_proj_info;
                
                obj.last_status_check = timestamp;
            else
                proj_info_out = obj.proj_info;
            end
        end
        
        function nb_out = get.pic_left_memory(obj)
            % Give back the available memory as a number of binary frames
            
            ALP_AVAIL_MEMORY = int32(2003);
            [obj.alp_return_value, nb_out] = calllib('alp4395','AlpDevInquire',obj.device_id, ALP_AVAIL_MEMORY, int32(0));
            
        end
        
        
        
        function value = get.seq_table(obj)
            value = struct2table(obj.seq_list);
        end
        
        
        % Set methods
        
        function set.mode(obj, mode)
            alp_proj_mode = int32(2300);

            %% Defines working mode : master or slave (external trigger)
            if (strcmp(mode,'slave'))

                % Set SLAVE mode
                obj.alp_return_value = calllib('alp4395','AlpProjControl',...
                obj.device_id, alp_proj_mode, int32(2302)); % ALP_SLAVE

                % Rising edge trigger
                alp_TRIGGER_EDGE = int32(2005);
                obj.alp_return_value = calllib('alp4395','AlpDevControl',...
                obj.device_id, alp_TRIGGER_EDGE, int32(2009)); % ALP_EDGE_RISING
            
            elseif (strcmp(mode,'master'))
                % Set MASTER mode
                alp_proj_mode = int32(2300);
                obj.alp_return_value = calllib('alp4395','AlpProjControl',obj.device_id, alp_proj_mode, int32(2301)); % ALP_MASTER
            else
                error('Wrong mode parameter.');
            end
            
        end
        
        function set.ROI(obj,ROI)
            % Define ROI settings
            
            if (isequal(size(ROI),[1,4]) || isequal(size(ROI),[4,1])) && isnumeric(ROI)
	            ROI_temp = ROI(:)';
	            
	            conditions = any(ROI_temp(1:2) >= 0) && any(ROI_temp(1:2)-[obj.width_DMD,obj.height_DMD] < 0);
	            conditions = conditions && any((ROI_temp(3:4) > 0).*(ROI_temp(3:4)-[obj.width_DMD,obj.height_DMD] <= 0));

	            conditions = conditions && (ROI_temp(1)+ROI_temp(3) > 1 && ROI_temp(1)+ROI_temp(3) <= obj.width_DMD);
	            conditions = conditions && (ROI_temp(2)+ROI_temp(4) > 1 && ROI_temp(2)+ROI_temp(4) <= obj.height_DMD);

	            if conditions
                    ROI_mask_temp = im2ROI(ROI2im(obj.ROI_mask,obj.ROI,[obj.height_DMD,obj.width_DMD]),ROI_temp);
                    obj.ROI = ROI_temp;
                    obj.ROI_mask = ROI_mask_temp;
		        else
            	    error('Wrong ROI values : part of the region is outside the boundaries.');
            	end
            else
            	error('ROI must be a integer array of length 4.');
            end
            
        end
        
        function set.ROI_mask(obj,ROI_mask)
            % Define ROI settings
            
            if (isequal(size(ROI_mask),obj.ROI([4 3])))
                obj.ROI_mask = ROI_mask;
            else
            	error('ROI mask must have the size specified by the ROI property.');
            end
        end

        function set.default_bin_mode(obj,bin_mode)
            if ~any(strcmp({'normal','uninterrupted'},bin_mode))
                warning('Not a bin mode.');
            else
                obj.default_bin_mode = bin_mode;
            end
        end
        

        % Stop and delete
        
        function stop(obj)
%             % Halt sequence
%             obj.alp_return_value = calllib('alp4395','AlpProjHalt',...
%             obj.device_id);
            
            obj.alp_return_value = calllib('alp4395','AlpDevHalt',...
            obj.device_id);
        end

        function delete(obj)
            if libisloaded('alp4395')
                % Release the device and unload library before deleting the object
                obj.alp_return_value = calllib('alp4395','AlpDevFree', obj.device_id);
                unloadlibrary('alp4395');
            end
        end

    end
    
%     methods (Access = protected)
%         function propgrp = getPropertyGroups(obj)
%           if ~isscalar(obj)
%              propgrp = getPropertyGroups@matlab.mixin.CustomDisplay(obj);
%           else
%              propList = struct('device_id', obj.device_id,...
%                                'alp_return_value', obj.alp_return_value,...
%                                'mode', obj.mode, ...
%                                'proj_info', obj.proj_info, ...
%                                'period', [num2str(obj.period), ' ms'],...
%                                'ROI', obj.ROI,...
%                                'current_seq_id', obj.current_seq_id,...
%                                'seq_disp', obj.seq_disp,...
%                                'seq_table', obj.seq_table,...
%                                'inverted', obj.inverted);
%                                
%              propgrp = matlab.mixin.util.PropertyGroup(propList);
%           end
%         end
%     end
   
    methods (Static)
        
        function out = bitplaneReshaper(array)
            nb_rows = size(array,1);
            nb_strides = size(array,2)/8;
            nb_frames = size(array,3);
            
            array_temp = uint8(reshape(array, [nb_rows, 8, nb_strides, nb_frames]));

            out = uint8(2.^(0:7));
            out = repmat(out, nb_rows, 1, nb_strides, nb_frames); 
            
            out = sum(out.*array_temp,2,'native'); % slover in uitn8...
           
            
            out = permute(out, [3 1 4 2]);
            out = flip(out);

            out = reshape(out,[1,nb_rows*nb_strides,nb_frames]); % to send in a line, with high row first (see BOTTOMUP)
        end
        

    end
end
