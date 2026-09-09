import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:camera/camera.dart';
import 'package:uuid/uuid.dart';

import 'database_helper.dart';
import 'tflite_service.dart';
import 'sync_service.dart';

const Color bruteGray = Color(0xFFE5E7EB);
const Color bruteBlack = Color(0xFF111827);
const Color bruteCyan = Color(0xFF00F0FF);
const Color bruteRed = Color(0xFFFF3B30);

List<CameraDescription> cameras = [];

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);

  try {
    cameras = await availableCameras();
  } catch (e) {
    debugPrint('Error getting cameras: $e');
  }

  try {
    await TFLiteService().loadModel();
  } catch (e) {
    debugPrint('Error loading TFLite model: $e');
  }

  await DatabaseHelper().database;
  SyncService().initialize(); // Start background sync listener

  runApp(const OptixApp());
}

class OptixApp extends StatelessWidget {
  const OptixApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'OptixAI Mobile',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        scaffoldBackgroundColor: bruteGray,
        fontFamily: 'Courier',
        textTheme: const TextTheme(
          bodyMedium: TextStyle(fontWeight: FontWeight.w700, color: bruteBlack),
          titleLarge: TextStyle(fontWeight: FontWeight.w900, color: bruteBlack, letterSpacing: -0.5),
        ),
      ),
      home: const RegistrationScreen(),
    );
  }
}

// ---------------------------------------------------------------------------
// Brute UI Components
// ---------------------------------------------------------------------------
class BruteCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color color;

  const BruteCard({super.key, required this.child, this.padding = const EdgeInsets.all(16), this.color = bruteGray});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: color,
        border: Border.all(color: bruteBlack, width: 3),
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [
          BoxShadow(color: bruteBlack, offset: Offset(5, 5), blurRadius: 0),
        ],
      ),
      child: child,
    );
  }
}

class BruteButton extends StatefulWidget {
  final String label;
  final VoidCallback onPressed;
  final Color backgroundColor;

  const BruteButton({super.key, required this.label, required this.onPressed, this.backgroundColor = bruteCyan});

  @override
  State<BruteButton> createState() => _BruteButtonState();
}

class _BruteButtonState extends State<BruteButton> {
  bool _isPressed = false;
  void _handleTapDown(_) => setState(() => _isPressed = true);
  void _handleTapUp(_) { setState(() => _isPressed = false); widget.onPressed(); }
  void _handleTapCancel() => setState(() => _isPressed = false);

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: _handleTapDown,
      onTapUp: _handleTapUp,
      onTapCancel: _handleTapCancel,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 50),
        height: 60,
        transform: Matrix4.translationValues(_isPressed ? 4.0 : 0.0, _isPressed ? 4.0 : 0.0, 0.0),
        decoration: BoxDecoration(
          color: widget.backgroundColor,
          border: Border.all(color: bruteBlack, width: 3),
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(color: bruteBlack, offset: _isPressed ? const Offset(1, 1) : const Offset(5, 5), blurRadius: 0),
          ],
        ),
        child: Center(
          child: Text(widget.label.toUpperCase(), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: bruteBlack)),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 1. Patient Registration
// ---------------------------------------------------------------------------
class RegistrationScreen extends StatefulWidget {
  const RegistrationScreen({super.key});
  @override
  State<RegistrationScreen> createState() => _RegistrationScreenState();
}

class _RegistrationScreenState extends State<RegistrationScreen> {
  final _nameCtrl = TextEditingController();
  final _ageCtrl = TextEditingController();
  final _genderCtrl = TextEditingController();
  final _diabetesCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();

  void _startScreening() {
    final patientId = const Uuid().v4();
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => DualEyeScreeningScreen(
          patientData: {
            'patient_id': patientId,
            'patient_name': _nameCtrl.text.isEmpty ? 'Unknown' : _nameCtrl.text,
            'age': int.tryParse(_ageCtrl.text) ?? 0,
            'gender': _genderCtrl.text,
            'diabetes_details': _diabetesCtrl.text,
            'phone': _phoneCtrl.text,
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('PATIENT REGISTRATION', style: TextStyle(fontWeight: FontWeight.w900)), backgroundColor: bruteGray, elevation: 0, foregroundColor: bruteBlack),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          BruteCard(
            child: Column(
              children: [
                TextField(controller: _nameCtrl, decoration: const InputDecoration(labelText: 'Patient Name', border: OutlineInputBorder())),
                const SizedBox(height: 16),
                TextField(controller: _ageCtrl, decoration: const InputDecoration(labelText: 'Age', border: OutlineInputBorder()), keyboardType: TextInputType.number),
                const SizedBox(height: 16),
                TextField(controller: _genderCtrl, decoration: const InputDecoration(labelText: 'Gender', border: OutlineInputBorder())),
                const SizedBox(height: 16),
                TextField(controller: _diabetesCtrl, decoration: const InputDecoration(labelText: 'Diabetes Details (e.g. Type 2, 5 yrs)', border: OutlineInputBorder())),
                const SizedBox(height: 16),
                TextField(controller: _phoneCtrl, decoration: const InputDecoration(labelText: 'Phone', border: OutlineInputBorder()), keyboardType: TextInputType.phone),
              ],
            ),
          ),
          const SizedBox(height: 32),
          BruteButton(label: 'BEGIN SCREENING', onPressed: _startScreening),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 2. Dual-Eye Capture & Quality Gate
// ---------------------------------------------------------------------------
enum ScreeningState { captureLeft, processingLeft, captureRight, processingRight, finalProcessing }

class DualEyeScreeningScreen extends StatefulWidget {
  final Map<String, dynamic> patientData;
  const DualEyeScreeningScreen({super.key, required this.patientData});
  @override
  State<DualEyeScreeningScreen> createState() => _DualEyeScreeningScreenState();
}

class _DualEyeScreeningScreenState extends State<DualEyeScreeningScreen> {
  CameraController? _controller;
  ScreeningState _state = ScreeningState.captureLeft;
  String? _leftImagePath;
  String? _rightImagePath;

  @override
  void initState() {
    super.initState();
    _initCamera();
  }

  Future<void> _initCamera() async {
    if (cameras.isEmpty) return;
    _controller = CameraController(cameras[0], ResolutionPreset.high, enableAudio: false);
    await _controller!.initialize();
    if (mounted) setState(() {});
  }

  Future<void> _captureAndCheckQuality() async {
    if (_controller == null || !_controller!.value.isInitialized) return;

    try {
      if (_state == ScreeningState.captureLeft) {
        setState(() => _state = ScreeningState.processingLeft);
      } else {
        setState(() => _state = ScreeningState.processingRight);
      }

      final file = await _controller!.takePicture();
      
      // Local Quality Gate
      final qualityError = await TFLiteService().assessQuality(file.path);
      if (!mounted) return;

      if (qualityError != null) {
        // Quality Failed
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('IMAGE REJECTED: $qualityError. Please retake.'), backgroundColor: bruteRed));
        setState(() {
          _state = _state == ScreeningState.processingLeft ? ScreeningState.captureLeft : ScreeningState.captureRight;
        });
        return;
      }

      // Quality Passed
      if (_state == ScreeningState.processingLeft) {
        _leftImagePath = file.path;
        setState(() => _state = ScreeningState.captureRight);
      } else {
        _rightImagePath = file.path;
        setState(() => _state = ScreeningState.finalProcessing);
        _runEdgeInference();
      }
    } catch (e) {
      debugPrint('Error: $e');
    }
  }

  Future<void> _runEdgeInference() async {
    try {
      final leftResult = await TFLiteService().gradeRetina(_leftImagePath!);
      final rightResult = await TFLiteService().gradeRetina(_rightImagePath!);

      bool referable = leftResult.requiresReferral || rightResult.requiresReferral;

      // Save to SQLite Queue
      final record = Map<String, dynamic>.from(widget.patientData);
      record['left_eye_path'] = _leftImagePath;
      record['right_eye_path'] = _rightImagePath;
      record['left_dr_grade'] = leftResult.grade;
      record['right_dr_grade'] = rightResult.grade;
      record['requires_referral'] = referable ? 1 : 0;

      await DatabaseHelper().insertRecord(record);

      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => ResultDashboard(
            leftResult: leftResult,
            rightResult: rightResult,
            patientName: widget.patientData['patient_name'],
          ),
        ),
      );
    } catch (e) {
      debugPrint('Inference Error: $e');
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_controller == null || !_controller!.value.isInitialized) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    bool isProcessing = _state == ScreeningState.processingLeft || _state == ScreeningState.processingRight || _state == ScreeningState.finalProcessing;
    String eyeTarget = (_state == ScreeningState.captureLeft || _state == ScreeningState.processingLeft) ? "LEFT EYE" : "RIGHT EYE";

    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(child: CameraPreview(_controller!)),
          // Brute Neomorphic Guide Overlay
          Positioned.fill(
            child: CustomPaint(
              painter: GuideOverlayPainter(),
            ),
          ),
          Positioned(
            top: 60,
            left: 20,
            right: 20,
            child: BruteCard(
              color: Colors.white.withValues(alpha: 0.9),
              child: Text(
                'ALIGN PATIENT\'S $eyeTarget',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
              ),
            ),
          ),
          if (isProcessing)
            Positioned.fill(
              child: Container(color: Colors.black54, child: const Center(child: CircularProgressIndicator(color: bruteCyan))),
            ),
          if (!isProcessing)
            Positioned(
              bottom: 40,
              left: 20,
              right: 20,
              child: BruteButton(
                label: 'CAPTURE $eyeTarget',
                onPressed: _captureAndCheckQuality,
              ),
            ),
        ],
      ),
    );
  }
}

class GuideOverlayPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.black54
      ..style = PaintingStyle.fill;
    
    final path = Path()..addRect(Rect.fromLTWH(0, 0, size.width, size.height));
    final ovalPath = Path()..addOval(Rect.fromCenter(center: Offset(size.width / 2, size.height / 2), width: 250, height: 250));
    
    final result = Path.combine(PathOperation.difference, path, ovalPath);
    canvas.drawPath(result, paint);

    final borderPaint = Paint()
      ..color = bruteCyan
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4;
    canvas.drawOval(Rect.fromCenter(center: Offset(size.width / 2, size.height / 2), width: 250, height: 250), borderPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ---------------------------------------------------------------------------
// 3. Model Output & Result Dashboard
// ---------------------------------------------------------------------------
class ResultDashboard extends StatelessWidget {
  final GradeResult leftResult;
  final GradeResult rightResult;
  final String patientName;

  const ResultDashboard({super.key, required this.leftResult, required this.rightResult, required this.patientName});

  @override
  Widget build(BuildContext context) {
    bool referable = leftResult.requiresReferral || rightResult.requiresReferral;

    return Scaffold(
      appBar: AppBar(title: const Text('DIAGNOSTIC PRINTOUT', style: TextStyle(fontWeight: FontWeight.w900)), backgroundColor: bruteGray, foregroundColor: bruteBlack, automaticallyImplyLeading: false),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          BruteCard(
            color: referable ? bruteRed : bruteCyan,
            child: Column(
              children: [
                Text(patientName.toUpperCase(), style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900)),
                const SizedBox(height: 8),
                Text(referable ? 'FLAG: REFERABLE DR (Level 2+)' : 'ROUTINE FOLLOW-UP', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
              ],
            ),
          ),
          const SizedBox(height: 24),
          _buildEyeResult('LEFT EYE', leftResult),
          const SizedBox(height: 16),
          _buildEyeResult('RIGHT EYE', rightResult),
          const SizedBox(height: 32),
          BruteButton(
            label: 'SCREEN NEXT PATIENT',
            backgroundColor: bruteGray,
            onPressed: () => Navigator.popUntil(context, (route) => route.isFirst),
          ),
        ],
      ),
    );
  }

  Widget _buildEyeResult(String eye, GradeResult result) {
    return BruteCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(eye, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, decoration: TextDecoration.underline)),
          const SizedBox(height: 8),
          Text('GRADE: \${result.grade} (\${result.label})', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          Text('CONFIDENCE: \${result.confidenceScore.toStringAsFixed(1)}%'),
          const SizedBox(height: 8),
          const Text('LESION EVIDENCE:', style: TextStyle(fontWeight: FontWeight.w900)),
          for (var ev in result.lesionEvidence) Text('- $ev'),
          const SizedBox(height: 16),
          // Simulated Grad-CAM Map Area
          Container(
            height: 100,
            decoration: BoxDecoration(
              border: Border.all(color: bruteBlack, width: 2),
              gradient: const RadialGradient(colors: [Colors.redAccent, Colors.transparent], radius: 0.8),
            ),
            child: const Center(child: Text('GRAD-CAM++ HEATMAP', style: TextStyle(fontWeight: FontWeight.w900))),
          ),
        ],
      ),
    );
  }
}
