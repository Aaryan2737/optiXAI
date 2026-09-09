import os
import sys
import torch
import torch.nn as nn
import torch.optim as optim
from torch.utils.data import DataLoader

# Ensure src directory is in the python path for absolute imports
sys.path.append(os.path.dirname(os.path.abspath(__file__)))

from dataset import RetinalDataset
from model import MobileNetV4Ordinal

def check_data_dir(data_dir):
    """
    Checks if the data directory exists and is not empty.
    Raises an error with instructions if missing.
    """
    if not os.path.exists(data_dir) or not os.listdir(data_dir):
        raise FileNotFoundError(
            f"\nThe directory '{data_dir}' is missing or empty.\n"
            "Please run 'python src/download_data.py' first to download the dataset before training."
        )

def get_ordinal_labels(labels, num_classes=5):
    """
    Converts integer labels (0 to 4) to ordinal multi-hot targets.
    Shape: (batch_size, 4)
    Example:
        Label 0 -> [0, 0, 0, 0]
        Label 1 -> [1, 0, 0, 0]
        Label 2 -> [1, 1, 0, 0]
        Label 3 -> [1, 1, 1, 0]
        Label 4 -> [1, 1, 1, 1]
    """
    batch_size = labels.size(0)
    ordinal_labels = torch.zeros(batch_size, num_classes - 1, dtype=torch.float32)
    for i in range(num_classes - 1):
        ordinal_labels[:, i] = (labels > i).float()
    return ordinal_labels

def train():
    data_dir = os.path.join("data", "raw", "train")
    
    # 1. Defensive error handling
    check_data_dir(data_dir)
    
    # Setup Device
    device = torch.device("cuda" if torch.cuda.is_available() else "cpu")
    print(f"Using device: {device}")
    
    # 2. Setup Dataset and DataLoader
    print("Initializing dataset and dataloader...")
    train_dataset = RetinalDataset(root_dir=data_dir)
    
    if len(train_dataset) == 0:
        raise ValueError(f"No images found in {data_dir}. Check your data source.")
        
    train_loader = DataLoader(train_dataset, batch_size=32, shuffle=True, num_workers=0)
    
    # 3. Initialize Model
    print("Initializing model...")
    model = MobileNetV4Ordinal().to(device)
    
    # 4. Setup Loss and Optimizer
    criterion = nn.BCELoss()
    optimizer = optim.AdamW(model.parameters(), lr=1e-3, weight_decay=1e-4)
    
    epochs = 10
    
    # 5. Training Loop
    print("Starting training...")
    for epoch in range(epochs):
        model.train()
        running_loss = 0.0
        
        for batch_idx, (images, labels) in enumerate(train_loader):
            images = images.to(device)
            labels = labels.to(device)
            
            # Construct ground-truth binary ordinal vectors
            ordinal_targets = get_ordinal_labels(labels).to(device)
            
            # Forward pass
            outputs = model(images)
            loss = criterion(outputs, ordinal_targets)
            
            # Backward pass and optimize
            optimizer.zero_grad()
            loss.backward()
            optimizer.step()
            
            running_loss += loss.item()
            
        epoch_loss = running_loss / len(train_loader)
        print(f"Epoch [{epoch+1}/{epochs}] - Loss: {epoch_loss:.4f}")
        
    # 6. Save the trained checkpoint
    os.makedirs("models", exist_ok=True)
    save_path = os.path.join("models", "dr_ordinal.pth")
    torch.save(model.state_dict(), save_path)
    print(f"Training complete. Model saved to {save_path}")

if __name__ == "__main__":
    train()
