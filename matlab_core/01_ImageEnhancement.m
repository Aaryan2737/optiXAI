% 01_ImageEnhancement.m
% Implements Image Quality Assessment and Enhancement for Diabetic Retinopathy screening

function [enhancedImage, isGradeable] = enhanceRetinalImage(imagePath)
    % Read the fundus image
    img = imread(imagePath);
    
    % Convert to LAB color space for luminance analysis
    labImg = rgb2lab(img);
    L = labImg(:,:,1);
    
    % Quality Assessment: Check for focus/blur using variance of Laplacian
    laplacianFilter = fspecial('laplacian', 0.2);
    lapImg = imfilter(L, laplacianFilter, 'replicate');
    focusScore = var(lapImg(:));
    
    % Quality Assessment: Illumination check
    meanLuminance = mean(L(:));
    
    % Thresholds for ungradeable images
    isGradeable = true;
    if focusScore < 50 || meanLuminance < 10 || meanLuminance > 95
        isGradeable = false;
        disp('Image rejected: Ungradeable due to poor focus or illumination.');
        enhancedImage = img;
        return;
    end
    
    % Adaptive Enhancement: Apply CLAHE on the L channel
    enhancedL = adapthisteq(L/100, 'NumTiles', [8 8], 'ClipLimit', 0.01) * 100;
    labImg(:,:,1) = enhancedL;
    
    % Convert back to RGB
    enhancedImage = lab2rgb(labImg);
    
    % Denoising using median filtering on each channel
    for i = 1:3
        enhancedImage(:,:,i) = medfilt2(enhancedImage(:,:,i), [3 3]);
    end
    
    disp('Image successfully enhanced.');
end
