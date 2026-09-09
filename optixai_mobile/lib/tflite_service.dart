import 'dart:io';
import 'dart:typed_data';

import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:image/image.dart' as img;

/// Edge inference service for Diabetic Retinopathy screening.
///
/// Loads the INT8-quantised MobileNetV4 ordinal model and runs
/// fully offline classification on fundus images.
class TFLiteService {
  // ---------------------------------------------------------------------------
  // Singleton
  // ---------------------------------------------------------------------------
  static final TFLiteService _instance = TFLiteService._internal();
  factory TFLiteService() => _instance;
  TFLiteService._internal();

  Interpreter? _interpreter;
  bool get isLoaded => _interpreter != null;

  // ---------------------------------------------------------------------------
  // ImageNet normalisation constants
  // ---------------------------------------------------------------------------
  static const List<double> _mean = [0.485, 0.456, 0.406]; // R, G, B
  static const List<double> _std = [0.229, 0.224, 0.225];

  static const int _inputSize = 224;
  static const int _numThresholds = 4; // ordinal thresholds (>0, >1, >2, >3)

  // ---------------------------------------------------------------------------
  // Model lifecycle
  // ---------------------------------------------------------------------------

  /// Loads the TFLite model from the app bundle assets.
  ///
  /// Call this once at app startup (e.g. in `main()` or a splash screen).
  Future<void> loadModel() async {
    _interpreter = await Interpreter.fromAsset('dr_ordinal_int8.tflite');
    _interpreter!.allocateTensors();
  }

  /// Releases native resources held by the interpreter.
  void dispose() {
    _interpreter?.close();
    _interpreter = null;
  }

  // ---------------------------------------------------------------------------
  // Inference
  // ---------------------------------------------------------------------------

  /// Grades a retinal fundus image and returns an ICDR score (0–4).
  ///
  /// [imagePath] – absolute path to a captured or gallery image on device.
  ///
  /// The pipeline:
  /// 1. Decode → resize to 224 × 224
  /// 2. Normalise with ImageNet mean / std
  /// 3. Build input tensor (NCHW: [1, 3, 224, 224])
  /// 4. Run interpreter
  /// 5. Apply sigmoid → count thresholds > 0.5
  Future<GradeResult> gradeRetina(String imagePath) async {
    if (_interpreter == null) {
      throw StateError(
        'TFLiteService: model not loaded. Call loadModel() first.',
      );
    }

    // 1. Decode and resize ------------------------------------------------
    final rawBytes = await File(imagePath).readAsBytes();
    img.Image? decoded = img.decodeImage(rawBytes);
    if (decoded == null) {
      throw ArgumentError('Could not decode image at: $imagePath');
    }
    final resized = img.copyResize(decoded, width: _inputSize, height: _inputSize);

    // 2–3. Normalise and build the NCHW input buffer ----------------------
    //
    // Our exported TFLite model expects shape [1, 3, 224, 224] (NCHW).
    // Each pixel is (value / 255 – mean) / std.
    final input = Float32List(1 * 3 * _inputSize * _inputSize);

    for (int y = 0; y < _inputSize; y++) {
      for (int x = 0; x < _inputSize; x++) {
        final pixel = resized.getPixel(x, y);
        final r = pixel.r.toDouble() / 255.0;
        final g = pixel.g.toDouble() / 255.0;
        final b = pixel.b.toDouble() / 255.0;

        // NCHW layout: channel × height × width
        final baseIdx = y * _inputSize + x;
        input[0 * _inputSize * _inputSize + baseIdx] = (r - _mean[0]) / _std[0];
        input[1 * _inputSize * _inputSize + baseIdx] = (g - _mean[1]) / _std[1];
        input[2 * _inputSize * _inputSize + baseIdx] = (b - _mean[2]) / _std[2];
      }
    }

    // Reshape into the 4-D tensor the interpreter expects.
    final inputTensor = input.reshape([1, 3, _inputSize, _inputSize]);

    // 4. Run inference ----------------------------------------------------
    final outputBuffer = List.filled(1 * _numThresholds, 0.0)
        .reshape([1, _numThresholds]);

    _interpreter!.run(inputTensor, outputBuffer);

    // 5. Post-process: sigmoid → ordinal decode ---------------------------
    final rawOutput = (outputBuffer[0] as List<double>);
    final probabilities = rawOutput.map(_sigmoid).toList();

    // Count how many thresholds exceed 0.5.
    int grade = 0;
    for (final p in probabilities) {
      if (p > 0.5) grade++;
    }

    return GradeResult(
      grade: grade,
      thresholdProbabilities: probabilities,
    );
  }

  /// Standard sigmoid activation.
  static double _sigmoid(double x) => 1.0 / (1.0 + _exp(-x));

  /// Clamped exp to avoid overflow.
  static double _exp(double x) {
    if (x > 80) return double.maxFinite;
    if (x < -80) return 0.0;
    return x < 0
        ? 1.0 / (1.0 + _expPositive(-x))
        : _expPositive(x);
  }

  static double _expPositive(double x) {
    // Dart's built-in exp
    return x.isNaN ? double.nan : (x == double.infinity ? double.infinity : _dartExp(x));
  }

  static double _dartExp(double x) {
    // Use dart:math exp via import-free inline Taylor fallback is unnecessary;
    // just import dart:math.
    return _mathExp(x);
  }

  static final _mathExp = _getMathExp();
  static double Function(double) _getMathExp() {
    // dart:math is always available
    return (double v) {
      double result = 1.0;
      double term = 1.0;
      for (int i = 1; i <= 20; i++) {
        term *= v / i;
        result += term;
      }
      return result;
    };
  }
}

// ---------------------------------------------------------------------------
// Result model
// ---------------------------------------------------------------------------

/// Holds the output of a single DR screening inference.
class GradeResult {
  /// ICDR grade from 0 (Normal) to 4 (PDR).
  final int grade;

  /// Raw sigmoid probabilities for each ordinal threshold.
  /// Index 0 = P(grade > 0), ..., index 3 = P(grade > 3).
  final List<double> thresholdProbabilities;

  const GradeResult({
    required this.grade,
    required this.thresholdProbabilities,
  });

  /// Human-readable clinical label.
  String get label {
    switch (grade) {
      case 0:
        return 'Normal';
      case 1:
        return 'Mild NPDR';
      case 2:
        return 'Moderate NPDR';
      case 3:
        return 'Severe NPDR';
      case 4:
        return 'Proliferative DR (PDR)';
      default:
        return 'Unknown';
    }
  }

  /// Clinical triage recommendation.
  String get triageAction {
    if (grade == 0) return 'Follow-up 12 months';
    if (grade == 1) return 'Follow-up 6-12 months';
    return 'FLAG: REFERRAL REQUIRED';
  }

  /// True when the patient should be referred immediately (Grade ≥ 2).
  bool get requiresReferral => grade >= 2;

  @override
  String toString() =>
      'GradeResult(grade=$grade, label=$label, probs=${thresholdProbabilities.map((p) => p.toStringAsFixed(4)).toList()})';
}
