% 02_Segmentation.m
% Extracts clinically relevant structures (vessels, optic disc, etc.)

function [vessels, opticDisc] = segmentRetinalStructures(enhancedImage)
    % Extract green channel (provides best contrast for blood vessels)
    greenChannel = enhancedImage(:,:,2);
    
    % 1. Blood Vessel Segmentation using Frangi Filter / Morphological Top-Hat
    % Subtract background illumination
    background = imopen(greenChannel, strel('disk', 15));
    I2 = imsubtract(greenChannel, background);
    
    % Enhance vessels
    I3 = adapthisteq(I2);
    
    % Binarize vessels
    level = graythresh(I3);
    vessels = imbinarize(I3, level);
    vessels = bwareaopen(vessels, 50); % Remove small noise
    
    % 2. Optic Disc Localization
    % The optic disc is typically the brightest region in the fundus
    redChannel = enhancedImage(:,:,1);
    [~, maxIdx] = max(redChannel(:));
    [y, x] = ind2sub(size(redChannel), maxIdx);
    
    % Create a mask for the optic disc
    opticDisc = false(size(redChannel));
    opticDisc = insertShape(double(opticDisc), 'FilledCircle', [x y 40], 'Color', 'white');
    opticDisc = opticDisc(:,:,1) > 0;
    
    disp('Segmentation completed successfully.');
end
