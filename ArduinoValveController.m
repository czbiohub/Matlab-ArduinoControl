classdef ArduinoValveController < handle
    % ArduinoValveController
    % Creates object to handle solenoid control through a Wago controller
    % and initializes communication with the controller.
    % The opbject should be created only once (i.e. the wago function should
    % be called just once).
    %
    % a = ArduinoValveController(com_port, board, polarity,...
    %            virtual)
    %
    % com_port = String of the com port to use to commuicate with the
    %            Arduino
    % board = String with the type of board (see MATLAB arduino docs)
    % polarity = Vector with the polarity for each valve
    %            polarity(j) = 0 --> (j-1)th valve is normally open
    %            polarity(j) = 1 --> (j-1)th valve is normally closed
    %            Valve numbers start at 0.
    % virtual = Optional boolean parameter that when true makes the valve
    %           controller not connect to the Wago, but it still accepts all
    %           commands.  Defaults to false when absent.
    %
    %
    % Methods:
    % --------
    % pol = a.getPolarity()
    %   pol = Logical vector with polarities (1 = normally closed,
    %         0 = normally open)
    % a.setValves(numbers, values)
    %   Set the valves specified by numbers to the states specified in
    %   values (0 = open or 1 = closed).  Valve numbers start at 0.
    %
    % values = a.getValves(numbers)
    %   Get the valve values specified by numbers (0 = open or 1 = closed).
    %   Valve numbers start at 0.
    %
    %
    % a.close()
    %   Close communication with the Wago controller.
    %   If the object won't be used again, must clear w after closing.
    %
    % [error, description] = a.getError()
    %   Returns the error code and description produced by the last method called.
    %
    %
    % K. Yamauchi  11/8/18


    properties (Access = private)
        arduino
        valves
        virtual = false;
        com_port = '';
        board = '';
        polarity = logical([]);
        totalValves = 0;
        currValues = logical([]);
        valveError
    end
    
    %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
    %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
    properties (Constant, Access = protected)
        myTag = 'ArduinoValveControl';
    end
    
    
    %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
    %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
    methods (Access= public)
        %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
        % Constructor
        function this = ArduinoValveController(com_port, board,...
                polarity, virtual)
            
            if ~exist('virtual', 'var')
                virtual = false;
            end
            
            this.com_port = com_port;
            this.board = board;
            this.polarity = polarity;
            this.virtual = virtual;
            this.totalValves = this.polarity.Count;
            
            this.valves = cell2mat(keys(this.polarity));

            if ~virtual
                this.open();
                
                this.setValves(this.valves, zeros(this.totalValves, 1));

            else
                this.com_port = 'Virtual';
                this.currValues = zeros(this.totalValves);
            end
        end
        
        %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
        % Close communication
        function close(this)
            if ~this.virtual
                try
                    this.arduino.delete();
                    
                catch ME

                end
            end
        end %close
        
        %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
        % Reset communication
        function reset(this, ~)
            this.close();
            this.open();
        end %reset
        
        %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
        % Return error code
        function [err, descr] = getError(this)

            if this.valveError < 0
                err = 2^31 + this.valveError;
                if err == hex2dec('80000000')
                    err = 0;
                end
            end
            switch this.valveError
                case 0
                    descr = 'No error';
                case 1
                    descr = 'Lengths of numbers and values vectors do not match';
                case 2
                    descr = 'An element in the valves vector is out of bounds';
                case 10
                    descr = 'Invalid non-volatile memory offset value';
                case 11
                    descr = 'Vector to write/read to/from non-volatile memory is out of bounds';
                case 999
                    descr = 'Unknown error';
                otherwise
                    descr = 'DLL error';
            end
            err = this.valveError;
        end %getError
        
        %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
        % Returns vector with polarities of all active valves
        function pol = getPolarity(this)
            pol = this.polarity;
        end
        
        %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
        % Returns string with the com port
        function com = getCom(this)
            com = this.com_port;
        end
        
        %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
        % Returns number of valves
        function nv = getNumValves(this)
            nv = this.totalValves;
        end
        
        %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
        % Test 8 channel DO modules
        function test(this)
            pause(1);

        end
        
        %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
        % Set state of one or more valves
        function setValves(this, valves, values)
            % Set the valves secified in vector numbers to the states
            % specified in vector values (0 = open or 1 = closed).
 
            if ~this.virtual
                if length(valves) ~= length(values)
                    this.valveError = 1;
                elseif ~all(ismember(valves, this.valves))
                    this.valveError = 2;
                else
                    % Make sure values are 0 or 1
                    values = (values > 0);
                    
                    % Update valves that must be changed
                    writeValues = zeros(length(values), 1);
                    
                    for i=1:length(values)
                        writeValues(i) = ~xor(values(i),...
                            this.polarity(valves(i)));
                        
                    end
                    
                    
                    
                    % Write new values to the Arduino
                    try
                        for i = 1:length(valves)
                           pinName = strcat('D', num2str(valves(i)));
                           
                           writeDigitalPin(this.arduino, pinName,...
                               writeValues(i)); 
                            
                        end
                        
                        this.valveError = 0;
                    catch ME
                        this.valveError = 999;
                    end
                    
                    if ~this.valveError
                        this.currValues(valves) = values;
                    end
                end
                java.lang.Thread.sleep(10);
            else
                this.setValvesVirtual(numbers, values);
            end
        end %setValves
        
        %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
        % Get state of one or more valves
        function values = getValves(this, valves)
            % Get the states of the valves specified in vector numbers
            % (0 = open or 1 = closed).

            if ~this.virtual
                values = zeros(length(valves), 1);
                if ~all(ismember(valves, this.valves))
                    this.valveError = 2;
                else
                    % Loop through all of the valves and get the relevant
                    % value
                    try
                        for i=1:length(valves)                     
                            pinName = strcat('D', num2str(valves(i)));
                            values(i) = readDigitalPin(this.arduino,...
                                pinName);
                            
                        end
                        
                    catch ME
                        this.valveError = 999;
                    end
                    
                end
            else
                values = this.getValvesVirtual(numbers);
            end
        end %getValves
        
        
    end
    
    
    %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
    %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
    methods (Access = private)
        %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
        % Open communication
        function open(this)
            
            if isempty(this.arduino)
                try
                    this.arduino = arduino(this.com_port, this.board);

                catch ME
                    this.valveError = 999;
                end
            end
        end %open
        
        %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
        % Set virtual state of one or more valves
        function setValvesVirtual(this, valves, values)
            % Set the virtual valves secified in vector numbers to the states
            % specified in vector values (0 = open or 1 = closed).

            
            if length(valves) ~= length(values)
                this.valveError = 1;
            elseif ~all(ismember(valves, this.valves))
                this.valveError = 2;
            else
                % Make sure values are 0 or 1
                values = (values > 0);
                % Update valves that must be changed
                newValues = this.currValues;
                newValues(valves + 1) = values;
                this.valveError = 0;
                this.currValues = newValues;
            end
        end %setValvesVirtual
        
        %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
        % Get state of one or more virtual valves
        function values = getValvesVirtual(this, valves)
            % Get the states of the virtual valves specified in vector numbers
            % (0 = open or 1 = closed).

            
            values = [];
            if ~all(ismember(valves, this.valves))
                this.valveError = 2;
            else
                values = this.currValues(valves + 1);
                this.valveError = 0;
            end
        end %getValvesVirtual
        
        
        
    end
end
