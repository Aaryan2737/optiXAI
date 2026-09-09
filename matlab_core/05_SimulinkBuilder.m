% 05_SimulinkBuilder.m
% Programmatically generates the Telemedicine Simulink model

function buildSimulinkModel()
    modelName = 'Telemedicine_Workflow';
    
    % Check if model exists, close and delete if so
    if bdIsLoaded(modelName)
        close_system(modelName, 0);
    end
    
    % Create new system
    new_system(modelName);
    open_system(modelName);
    
    % Add Blocks to simulate the workflow
    % 1. Image Acquisition Rate (Step/Pulse Generator)
    add_block('simulink/Sources/Pulse Generator', [modelName, '/ImageAcquisition']);
    set_param([modelName, '/ImageAcquisition'], 'Period', '60'); % 1 image per minute
    
    % 2. Bandwidth Constraint (Rate Limiter)
    add_block('simulink/Discrete/Rate Limiter', [modelName, '/BandwidthConstraint']);
    
    % 3. Cloud Processing Throughput (Transfer Fcn / Delay)
    add_block('simulink/Discrete/Integer Delay', [modelName, '/CloudProcessing']);
    
    % 4. Ophthalmologist Review Queue (Scope / To Workspace)
    add_block('simulink/Sinks/Scope', [modelName, '/ReviewQueue']);
    
    % Connect the blocks
    add_line(modelName, 'ImageAcquisition/1', 'BandwidthConstraint/1');
    add_line(modelName, 'BandwidthConstraint/1', 'CloudProcessing/1');
    add_line(modelName, 'CloudProcessing/1', 'ReviewQueue/1');
    
    % Position blocks neatly
    set_param([modelName, '/ImageAcquisition'], 'Position', [50, 100, 90, 140]);
    set_param([modelName, '/BandwidthConstraint'], 'Position', [150, 100, 190, 140]);
    set_param([modelName, '/CloudProcessing'], 'Position', [250, 100, 290, 140]);
    set_param([modelName, '/ReviewQueue'], 'Position', [350, 100, 390, 140]);
    
    disp('Simulink Telemedicine Workflow model generated successfully.');
    save_system(modelName);
end
