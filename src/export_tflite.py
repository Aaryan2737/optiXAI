import os
os.environ["TF_USE_LEGACY_KERAS"] = "1"
import sys
try:
    import tf_keras
    sys.modules['keras'] = tf_keras
except ImportError:
    pass
import sys
import torch
import onnx
import onnx.helper
import types

# Patch onnx.mapping for onnx-tf compatibility with onnx>=1.14
mapping = types.ModuleType('mapping')
mapping.TENSOR_TYPE_TO_NP_TYPE = {}
mapping.NP_TYPE_TO_TENSOR_TYPE = {}
for tensor_type in onnx.helper.get_all_tensor_dtypes():
    try:
        np_type = onnx.helper.tensor_dtype_to_np_dtype(tensor_type)
        mapping.TENSOR_TYPE_TO_NP_TYPE[tensor_type] = np_type
        mapping.NP_TYPE_TO_TENSOR_TYPE[np_type] = tensor_type
    except Exception:
        pass
sys.modules['onnx.mapping'] = mapping
onnx.mapping = mapping
onnx.helper.mapping = mapping

from onnx_tf.backend import prepare
import tensorflow as tf

# Patch onnx_tf ReduceMean to support opset 18
try:
    from onnx_tf.handlers.backend.reduce_mean import ReduceMean
    @classmethod
    def version_18(cls, node, **kwargs):
        tensor_dict = kwargs.get("tensor_dict", {})
        x = tensor_dict[node.inputs[0]]
        if len(node.inputs) > 1 and node.inputs[1] != "":
            axes = tensor_dict[node.inputs[1]]
        else:
            axes = node.attrs.get("axes", None)
        keepdims = node.attrs.get("keepdims", 1) == 1
        if axes is not None:
            axes = tf.cast(axes, tf.int32)
        return [tf.reduce_mean(x, axis=axes, keepdims=keepdims)]
    ReduceMean.version_18 = version_18
except ImportError:
    pass

# Ensure src directory is in the python path for absolute imports
sys.path.append(os.path.dirname(os.path.abspath(__file__)))

from model import MobileNetV4Ordinal

def export_to_tflite():
    # Define Paths
    os.makedirs("models", exist_ok=True)
    model_path = os.path.join("models", "dr_ordinal.pth")
    onnx_path = os.path.join("models", "dr_ordinal.onnx")
    tf_saved_model_dir = os.path.join("models", "tf_dr_ordinal")
    tflite_path = os.path.join("models", "dr_ordinal_int8.tflite")
    
    # 1. Load PyTorch Model
    print("Loading PyTorch model...")
    device = torch.device("cpu")
    model = MobileNetV4Ordinal().to(device)
    
    if os.path.exists(model_path):
        model.load_state_dict(torch.load(model_path, map_location=device))
    else:
        print(f"Warning: {model_path} not found. Exporting with untrained weights.")
    
    model.eval()
    
    # 2. Export to ONNX
    print(f"Exporting to ONNX format at {onnx_path}...")
    dummy_input = torch.randn(1, 3, 224, 224, device=device)
    
    # Export using opset 14
    torch.onnx.export(
        model, 
        dummy_input, 
        onnx_path, 
        export_params=True, 
        opset_version=14, 
        do_constant_folding=True, 
        input_names=['input'], 
        output_names=['output']
    )
    print("ONNX export complete.")
    
    # 3. Convert ONNX to TensorFlow SavedModel using onnx-tf
    print(f"Converting ONNX to TensorFlow SavedModel at {tf_saved_model_dir}...")
    onnx_model = onnx.load(onnx_path)
    tf_rep = prepare(onnx_model)
    tf_rep.export_graph(tf_saved_model_dir)
    print("TensorFlow SavedModel export complete.")
    
    # 4. Convert TF SavedModel to TFLite with INT8 dynamic range quantization
    print(f"Converting to TFLite (INT8 dynamic range optimization) at {tflite_path}...")
    converter = tf.lite.TFLiteConverter.from_saved_model(tf_saved_model_dir)
    # Enable INT8 dynamic range optimization
    converter.optimizations = [tf.lite.Optimize.DEFAULT]
    
    tflite_model = converter.convert()
    
    # Serialize the TFLite binary
    with open(tflite_path, 'wb') as f:
        f.write(tflite_model)
    print("TFLite export complete.")
        
    # 5. Execute file size check and assertion
    file_size_bytes = os.path.getsize(tflite_path)
    file_size_mb = file_size_bytes / (1024 * 1024)
    print(f"Final TFLite model size: {file_size_mb:.2f} MB")
    
    assert file_size_mb < 6.0, f"Error: TFLite model size ({file_size_mb:.2f} MB) exceeds 6 MB limit!"
    print("Export pipeline completed successfully and passed size constraints.")

if __name__ == "__main__":
    export_to_tflite()
