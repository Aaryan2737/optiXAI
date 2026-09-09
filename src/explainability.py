import os
import sys
import argparse
import cv2
import numpy as np
import torch
from torchvision import transforms
from pytorch_grad_cam import GradCAMPlusPlus
from pytorch_grad_cam.utils.image import show_cam_on_image
from pytorch_grad_cam.utils.model_targets import ClassifierOutputTarget

# Ensure src directory is in the python path for absolute imports
sys.path.append(os.path.dirname(os.path.abspath(__file__)))

from model import MobileNetV4Ordinal, decode_ordinal_prediction
from dataset import ben_graham_preprocessing

def get_normalized_tensor(img_rgb):
    """
    Transforms the preprocessed RGB numpy image into a normalized PyTorch tensor.
    """
    transform = transforms.Compose([
        transforms.ToTensor(),
        transforms.Normalize(mean=[0.485, 0.456, 0.406], std=[0.229, 0.224, 0.225])
    ])
    input_tensor = transform(img_rgb).unsqueeze(0)
    return input_tensor

def explain(image_path, output_vis_path):
    device = torch.device("cuda" if torch.cuda.is_available() else "cpu")
    
    # 1. Load Model
    model = MobileNetV4Ordinal().to(device)
    model_path = os.path.join("models", "dr_ordinal.pth")
    if os.path.exists(model_path):
        # We handle untrained weights gracefully for the CLI test
        model.load_state_dict(torch.load(model_path, map_location=device))
    else:
        print(f"Warning: {model_path} not found. Using untrained weights for testing.")
        
    model.eval()
    
    # 2. Target Layer
    # Using the final convolutional block of MobileNetV4
    try:
        target_layers = [model.backbone.conv_head]
    except AttributeError:
        print("Warning: model.backbone.conv_head not found. Attempting fallback...")
        target_layers = [list(model.backbone.children())[-1]]

    # 3. Preprocess Image
    img_rgb = ben_graham_preprocessing(image_path)
    input_tensor = get_normalized_tensor(img_rgb).to(device)
    
    # 4. Forward Pass to get predictions
    with torch.no_grad():
        probs = model(input_tensor)
        grade_tensor = decode_ordinal_prediction(probs)
        predicted_grade = int(grade_tensor.item())
        threshold_probs = probs[0].cpu().numpy().tolist()
        
    # 5. Target the highest triggered threshold index
    # (predicted_grade - 1), clamped at 0
    target_idx = max(0, predicted_grade - 1)
    targets = [ClassifierOutputTarget(target_idx)]
    
    # 6. Generate activation map using GradCAMPlusPlus
    # Note: grad-cam hooks into the forward pass, so no torch.no_grad() here
    with GradCAMPlusPlus(model=model, target_layers=target_layers) as cam:
        grayscale_cam = cam(input_tensor=input_tensor, targets=targets)[0, :]
        
    # 7. Blend the grayscale CAM over the normalized image
    # show_cam_on_image expects the base image to be float32 in [0, 1] range
    img_normalized = img_rgb.astype(np.float32) / 255.0
    visualization = show_cam_on_image(img_normalized, grayscale_cam, use_rgb=True)
    
    # Save the output visualization image in BGR format for OpenCV
    visualization_bgr = cv2.cvtColor(visualization, cv2.COLOR_RGB2BGR)
    cv2.imwrite(output_vis_path, visualization_bgr)
    
    return {
        'predicted_grade': predicted_grade,
        'threshold_probs': threshold_probs,
        'saliency_path': output_vis_path
    }

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Generate XAI overlays using GradCAMPlusPlus")
    parser.add_argument("--image", type=str, default=os.path.join("tests", "test_dummy.jpg"), help="Path to input image")
    parser.add_argument("--output", type=str, default=os.path.join("tests", "xai_output.jpg"), help="Path to save visualization")
    args = parser.parse_args()
    
    # Mock a synthetic dummy image if the user hasn't downloaded dataset
    if not os.path.exists(args.image):
        print(f"Creating dummy image at {args.image} to test the pipeline...")
        os.makedirs(os.path.dirname(args.image), exist_ok=True)
        # Random noise dummy image
        dummy_img = np.random.randint(0, 256, (300, 300, 3), dtype=np.uint8)
        cv2.imwrite(args.image, dummy_img)
        
    print(f"Running XAI explainability on {args.image}...")
    diagnostic_info = explain(args.image, args.output)
    
    print("\n--- Diagnostic Results ---")
    print(f"Predicted Grade (0-4): {diagnostic_info['predicted_grade']}")
    probs_formatted = [f"{p:.4f}" for p in diagnostic_info['threshold_probs']]
    print(f"Threshold Probabilities (P>0, P>1, P>2, P>3): {probs_formatted}")
    print(f"Saliency Map saved to: {diagnostic_info['saliency_path']}")
    print("Execution complete.")
