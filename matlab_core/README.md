# OptiXAI - MATLAB AI Pipeline
As per MathWorks SIH Problem Statement 26038, this directory contains the core MATLAB-based retinal image analysis pipeline.

## Prerequisites
- MATLAB R2023b or newer
- Image Processing Toolbox
- Computer Vision Toolbox
- Deep Learning Toolbox
- Simulink

## Execution
1. Run `01_ImageEnhancement.m` to test the CLAHE implementation and image quality checks.
2. Run `02_Segmentation.m` to observe vessel extraction and optic disc localization.
3. Run `03_SeverityGrading.m` and `04_Explainability.m` for the CNN inference and Grad-CAM outputs.
4. Run `05_SimulinkBuilder.m` to dynamically generate the `Telemedicine_Workflow.slx` Simulink model.
