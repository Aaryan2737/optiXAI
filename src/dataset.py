import os
import glob
import cv2
import numpy as np
import torch
from torch.utils.data import Dataset
from torchvision import transforms

def ben_graham_preprocessing(image_path, target_size=(224, 224)):
    """
    Reads an image, resizes it, applies Ben Graham's local average color
    subtraction, and applies a circular mask.
    """
    # Read the image
    img = cv2.imread(image_path)
    if img is None:
        raise ValueError(f"Could not read image from {image_path}")
    
    # Convert BGR to RGB
    img = cv2.cvtColor(img, cv2.COLOR_BGR2RGB)
    
    # Resize
    img = cv2.resize(img, target_size)
    
    # Apply Ben Graham's local average color subtraction
    sigma = target_size[0] / 30.0
    gaussian = cv2.GaussianBlur(img, (0, 0), sigma)
    img = cv2.addWeighted(img, 4, gaussian, -4, 128)
    
    # Apply a circular mask
    mask = np.zeros(img.shape, dtype=np.uint8)
    center = (img.shape[1] // 2, img.shape[0] // 2)
    radius = min(center[0], center[1])
    cv2.circle(mask, center, radius, (255, 255, 255), -1, 8, 0)
    
    # Bitwise AND to apply mask
    img = img & mask
    
    return img

class RetinalDataset(Dataset):
    def __init__(self, root_dir, target_size=(224, 224), transform=None):
        self.root_dir = root_dir
        self.target_size = target_size
        self.image_paths = []
        self.labels = []
        
        # Parse class subfolders 0/ through 4/
        for label in range(5):
            folder_path = os.path.join(root_dir, str(label))
            if os.path.exists(folder_path):
                # Match common image extensions
                for ext in ('*.jpg', '*.jpeg', '*.png', '*.tif', '*.tiff'):
                    for img_path in glob.glob(os.path.join(folder_path, ext)):
                        self.image_paths.append(img_path)
                        self.labels.append(label)
        
        # Default PyTorch augmentations
        if transform is None:
            self.transform = transforms.Compose([
                transforms.ToPILImage(),
                transforms.RandomHorizontalFlip(),
                transforms.RandomVerticalFlip(),
                transforms.RandomRotation(15),
                transforms.ToTensor(),
                transforms.Normalize(mean=[0.485, 0.456, 0.406], std=[0.229, 0.224, 0.225])
            ])
        else:
            self.transform = transform

    def __len__(self):
        return len(self.image_paths)

    def __getitem__(self, idx):
        img_path = self.image_paths[idx]
        label = self.labels[idx]
        
        # Run preprocessing
        img = ben_graham_preprocessing(img_path, target_size=self.target_size)
        
        # Apply augmentations
        if self.transform:
            img = self.transform(img)
            
        return img, label

if __name__ == "__main__":
    # Test ben_graham_preprocessing with a synthetic image
    test_img_path = "synthetic_test.jpg"
    
    # Create a dummy image using OpenCV (random noise)
    dummy_img = np.random.randint(0, 256, (300, 300, 3), dtype=np.uint8)
    cv2.imwrite(test_img_path, dummy_img)
    
    try:
        processed_img = ben_graham_preprocessing(test_img_path)
        print(f"Original synthetic image shape: (300, 300, 3)")
        print(f"Processed image shape: {processed_img.shape}")
        
        assert processed_img.shape == (224, 224, 3), f"Expected (224, 224, 3), got {processed_img.shape}"
        print("Test passed: Output shape is valid!")
        
    finally:
        # Clean up
        if os.path.exists(test_img_path):
            os.remove(test_img_path)
