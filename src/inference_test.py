"""
Isolated TFLite Inference Verification Script
==============================================
Validates that the DR screening model runs entirely offline using only:
  - numpy
  - opencv-python
  - tensorflow.lite.Interpreter

No PyTorch, no cloud APIs, no network calls.
"""

import os
import sys
import time
import numpy as np
import cv2


# ---------------------------------------------------------------------------
# 1. Ben Graham Preprocessing (pure OpenCV + NumPy, no PyTorch dependency)
# ---------------------------------------------------------------------------
def ben_graham_preprocessing(image_path: str, target_size: tuple = (224, 224)) -> np.ndarray:
    """
    Applies Ben Graham's local average color subtraction to a fundus image.
    Returns a uint8 BGR image of shape (target_size[0], target_size[1], 3).
    """
    img = cv2.imread(image_path)
    if img is None:
        raise FileNotFoundError(f"Could not read image: {image_path}")

    # Resize to target dimensions
    img = cv2.resize(img, target_size)

    # Gaussian blur with sigma = target_size[0] / 30
    sigma = target_size[0] / 30.0
    ksize = int(sigma * 6) | 1  # ensure odd kernel size
    gaussian = cv2.GaussianBlur(img, (ksize, ksize), sigma)

    # Ben Graham's local average color subtraction
    img = cv2.addWeighted(img, 4, gaussian, -4, 128)

    # Apply circular mask to strip variable black borders
    h, w = img.shape[:2]
    mask = np.zeros((h, w), dtype=np.uint8)
    center = (w // 2, h // 2)
    radius = min(h, w) // 2
    cv2.circle(mask, center, radius, 255, -1)
    img = cv2.bitwise_and(img, img, mask=mask)

    return img


# ---------------------------------------------------------------------------
# 2. ImageNet normalization (pure NumPy)
# ---------------------------------------------------------------------------
def imagenet_normalize(img_bgr: np.ndarray) -> np.ndarray:
    """
    Converts a uint8 BGR image to a float32 RGB array normalized with
    ImageNet mean/std, shaped (1, H, W, 3) for TFLite NHWC input.
    """
    img_rgb = cv2.cvtColor(img_bgr, cv2.COLOR_BGR2RGB).astype(np.float32) / 255.0
    mean = np.array([0.485, 0.456, 0.406], dtype=np.float32)
    std = np.array([0.229, 0.224, 0.225], dtype=np.float32)
    img_rgb = (img_rgb - mean) / std
    return np.expand_dims(img_rgb, axis=0)  # (1, 224, 224, 3)


# ---------------------------------------------------------------------------
# 3. Ordinal decoding (pure Python)
# ---------------------------------------------------------------------------
def decode_ordinal_prediction(probabilities: np.ndarray, threshold: float = 0.5) -> int:
    """
    Sums binary ordinal thresholds to produce an ICDR grade 0-4.
    probabilities: array of shape (4,) with values in [0, 1].
    """
    return int(np.sum(probabilities >= threshold))


# ---------------------------------------------------------------------------
# 4. Clinical triage formatting
# ---------------------------------------------------------------------------
TRIAGE_TABLE = {
    0: ("Normal",                     "Follow-up 12 mo"),
    1: ("Mild NPDR",                  "Follow-up 6-12 mo"),
    2: ("Moderate NPDR",              "FLAG: REFERRAL REQUIRED"),
    3: ("Severe NPDR",                "FLAG: REFERRAL REQUIRED"),
    4: ("Proliferative DR (PDR)",     "FLAG: REFERRAL REQUIRED"),
}


def format_triage(grade: int, probs: np.ndarray, latency_ms: float) -> str:
    """Formats a clean clinical triage log entry."""
    label, action = TRIAGE_TABLE.get(grade, ("Unknown", "Manual review"))
    lines = [
        "=" * 60,
        "  DIABETIC RETINOPATHY SCREENING — EDGE INFERENCE REPORT",
        "=" * 60,
        f"  Predicted ICDR Grade : {grade}  ({label})",
        f"  Clinical Action      : {action}",
        "-" * 60,
        "  Ordinal Threshold Probabilities:",
        f"    P(grade > 0) = {probs[0]:.4f}",
        f"    P(grade > 1) = {probs[1]:.4f}",
        f"    P(grade > 2) = {probs[2]:.4f}",
        f"    P(grade > 3) = {probs[3]:.4f}",
        "-" * 60,
        f"  Inference Latency    : {latency_ms:.2f} ms",
        f"  Runtime              : TFLite INT8 (CPU-only, offline)",
        "=" * 60,
    ]
    return "\n".join(lines)


# ---------------------------------------------------------------------------
# 5. Main inference pipeline
# ---------------------------------------------------------------------------
def main():
    # --- Paths ---
    model_path = os.path.join("models", "dr_ordinal_int8.tflite")
    
    # Accept an image path as CLI argument, or generate a synthetic test image
    if len(sys.argv) > 1:
        image_path = sys.argv[1]
    else:
        # Generate a synthetic 224x224 fundus-like test image for benchmarking
        image_path = os.path.join("models", "_synthetic_test_input.png")
        synthetic = np.random.randint(0, 256, (224, 224, 3), dtype=np.uint8)
        # Draw a bright circle to simulate a fundus
        cv2.circle(synthetic, (112, 112), 100, (30, 80, 180), -1)
        cv2.imwrite(image_path, synthetic)
        print(f"[INFO] No image argument provided. Using synthetic test image: {image_path}")

    # --- Validate paths ---
    if not os.path.isfile(model_path):
        print(f"[ERROR] TFLite model not found at: {model_path}")
        print("        Run src/export_tflite.py first to generate the model.")
        sys.exit(1)
    if not os.path.isfile(image_path):
        print(f"[ERROR] Input image not found at: {image_path}")
        sys.exit(1)

    # --- Load TFLite interpreter ---
    import tensorflow as tf
    interpreter = tf.lite.Interpreter(model_path=model_path)
    interpreter.allocate_tensors()

    input_details = interpreter.get_input_details()
    output_details = interpreter.get_output_details()

    print(f"[INFO] Model loaded: {model_path}")
    print(f"[INFO] Input  : {input_details[0]['shape']}  dtype={input_details[0]['dtype']}")
    print(f"[INFO] Output : {output_details[0]['shape']}  dtype={output_details[0]['dtype']}")

    # --- Preprocess ---
    img_preprocessed = ben_graham_preprocessing(image_path)
    input_buffer = imagenet_normalize(img_preprocessed)

    # TFLite models exported via ONNX->TF may expect NCHW; check and transpose
    expected_shape = tuple(input_details[0]['shape'])
    if expected_shape == (1, 3, 224, 224):
        # Model expects NCHW
        input_buffer = np.transpose(input_buffer, (0, 3, 1, 2))
    
    input_buffer = input_buffer.astype(input_details[0]['dtype'])

    # --- Inference with latency measurement ---
    interpreter.set_tensor(input_details[0]['index'], input_buffer)

    # Warm-up run
    interpreter.invoke()

    # Timed run
    t_start = time.perf_counter()
    interpreter.invoke()
    t_end = time.perf_counter()
    latency_ms = (t_end - t_start) * 1000.0

    # --- Read output ---
    raw_output = interpreter.get_tensor(output_details[0]['index'])[0]  # shape (4,)
    probs = 1.0 / (1.0 + np.exp(-raw_output))  # sigmoid if model outputs logits
    # If values are already in [0,1] from the model's sigmoid, use them directly
    if np.all(raw_output >= 0.0) and np.all(raw_output <= 1.0):
        probs = raw_output

    grade = decode_ordinal_prediction(probs)

    # --- Output ---
    report = format_triage(grade, probs, latency_ms)
    print(report)

    # Cleanup synthetic image
    if len(sys.argv) <= 1 and os.path.exists(image_path):
        os.remove(image_path)


if __name__ == "__main__":
    main()
