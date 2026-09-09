import torch
import torch.nn as nn
# pyrefly: ignore [missing-import]
import timm

class MobileNetV4Ordinal(nn.Module):
    def __init__(self):
        super(MobileNetV4Ordinal, self).__init__()
        # Feature backbone: MobileNetV4 small
        # num_classes=0 replaces the classifier with the global pool
        self.backbone = timm.create_model('mobilenetv4_conv_small.e1200_r224_in1k', pretrained=True, num_classes=0)
        
        # Extract the correct feature dimension from the backbone dynamically
        with torch.no_grad():
            dummy = torch.randn(2, 3, 224, 224)
            # Switch to eval mode temporarily to avoid BatchNorm issues, though batch size 2 also helps
            self.backbone.eval()
            in_features = self.backbone(dummy).shape[1]
            self.backbone.train()
        
        # Custom ordinal head mapping to 4 binary thresholds
        self.head = nn.Sequential(
            nn.Dropout(p=0.3),
            nn.Linear(in_features, 4)
        )
        
    def forward(self, x):
        features = self.backbone(x)
        logits = self.head(features)
        # Probabilities for progression thresholds (>0, >1, >2, >3)
        probs = torch.sigmoid(logits)
        return probs

def decode_ordinal_prediction(probabilities, threshold=0.5):
    """
    Sums the threshold-exceeding columns to yield a final grade (0-4).
    probabilities shape: (batch_size, 4)
    Returns integer ICDR grade of shape: (batch_size,)
    """
    exceeds_thresh = probabilities > threshold
    return exceeds_thresh.sum(dim=1)

if __name__ == "__main__":
    print("Testing MobileNetV4Ordinal...")
    model = MobileNetV4Ordinal()
    
    # Dummy tensor shape: (batch_size, channels, height, width)
    dummy_input = torch.randn(2, 3, 224, 224)
    
    # Run the model
    output = model(dummy_input)
    print(f"Output shape: {output.shape}")
    print(f"Sample output probabilities:\n{output}")
    
    # Assertions
    assert output.shape == (2, 4), f"Shape mismatch: expected (2, 4) but got {output.shape}"
    assert torch.all(output >= 0.0) and torch.all(output <= 1.0), "Outputs not bounded between 0.0 and 1.0"
    
    # Test decoding
    decoded_grades = decode_ordinal_prediction(output)
    print(f"Decoded grades: {decoded_grades.tolist()}")
    
    print("All tests passed successfully!")
