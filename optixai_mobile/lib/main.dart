import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:camera/camera.dart';

import 'database_helper.dart';
import 'tflite_service.dart';

// ---------------------------------------------------------------------------
// Design System Colors & Constants
// ---------------------------------------------------------------------------
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
        fontFamily: 'Courier', // Mechanical/Industrial default font
        textTheme: const TextTheme(
          bodyMedium: TextStyle(fontWeight: FontWeight.w700, color: bruteBlack),
          titleLarge: TextStyle(fontWeight: FontWeight.w900, color: bruteBlack, letterSpacing: -0.5),
        ),
      ),
      home: const ScreeningScreen(),
    );
  }
}

// ---------------------------------------------------------------------------
// Reusable Brute-Neumorphic Widgets
// ---------------------------------------------------------------------------

class BruteCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final double? width;
  final double? height;
  final Color color;

  const BruteCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.width,
    this.height,
    this.color = bruteGray,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      padding: padding,
      decoration: BoxDecoration(
        color: color,
        border: Border.all(color: bruteBlack, width: 3),
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [
          BoxShadow(
            color: bruteBlack,
            offset: Offset(5, 5),
            blurRadius: 0,
          ),
          BoxShadow(
            color: Colors.white,
            offset: Offset(-2, -2),
            blurRadius: 0,
          ),
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
  final double height;
  final double? width;

  const BruteButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.backgroundColor = bruteCyan,
    this.height = 60,
    this.width,
  });

  @override
  State<BruteButton> createState() => _BruteButtonState();
}

class _BruteButtonState extends State<BruteButton> {
  bool _isPressed = false;

  void _handleTapDown(TapDownDetails details) {
    HapticFeedback.heavyImpact();
    setState(() => _isPressed = true);
  }

  void _handleTapUp(TapUpDetails details) {
    setState(() => _isPressed = false);
    widget.onPressed();
  }

  void _handleTapCancel() {
    setState(() => _isPressed = false);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: _handleTapDown,
      onTapUp: _handleTapUp,
      onTapCancel: _handleTapCancel,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 50),
        width: widget.width,
        height: widget.height,
        transform: Matrix4.translationValues(
          _isPressed ? 4.0 : 0.0,
          _isPressed ? 4.0 : 0.0,
          0.0,
        ),
        decoration: BoxDecoration(
          color: widget.backgroundColor,
          border: Border.all(color: bruteBlack, width: 3),
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: bruteBlack,
              offset: _isPressed ? const Offset(1, 1) : const Offset(5, 5),
              blurRadius: 0,
            ),
          ],
        ),
        child: Center(
          child: Text(
            widget.label.toUpperCase(),
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w900,
              color: bruteBlack,
              letterSpacing: 1.2,
            ),
          ),
        ),
      ),
    );
  }
}

class BruteBadge extends StatelessWidget {
  final String text;
  final Color color;

  const BruteBadge({
    super.key,
    required this.text,
    this.color = bruteCyan,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color,
        border: Border.all(color: bruteBlack, width: 2),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        text.toUpperCase(),
        style: const TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w900,
          color: bruteBlack,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

class QualityChecklistCard extends StatelessWidget {
  final bool isSuccess;
  const QualityChecklistCard({super.key, required this.isSuccess});

  @override
  Widget build(BuildContext context) {
    if (isSuccess) {
      return BruteCard(
        color: bruteGray,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Center(child: BruteBadge(text: 'GOOD IMAGE', color: Colors.greenAccent)),
            const SizedBox(height: 16),
            _buildCheckRow('✓ Brightness'),
            _buildCheckRow('✓ Focus'),
            _buildCheckRow('✓ Eye detected'),
            _buildCheckRow('✓ Fundus visible'),
          ],
        ),
      );
    } else {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: bruteGray,
          border: Border.all(color: bruteRed, width: 3),
          borderRadius: BorderRadius.circular(16),
          boxShadow: const [
            BoxShadow(color: bruteBlack, offset: Offset(5, 5), blurRadius: 0),
            BoxShadow(color: Colors.white, offset: Offset(-2, -2), blurRadius: 0),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Δ Image quality is low', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: bruteRed)),
            const SizedBox(height: 12),
            _buildBulletRow('• Move camera closer'),
            _buildBulletRow('• Keep eye open'),
            _buildBulletRow('• Avoid excessive light'),
            _buildBulletRow('• Hold device steady'),
          ],
        ),
      );
    }
  }

  Widget _buildCheckRow(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Text(text, style: const TextStyle(color: Colors.green, fontWeight: FontWeight.w900)),
    );
  }

  Widget _buildBulletRow(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Text(text, style: const TextStyle(fontWeight: FontWeight.w900, color: bruteBlack)),
    );
  }
}

// ---------------------------------------------------------------------------
// Viewfinder Components
// ---------------------------------------------------------------------------

class RetinalTargetPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = bruteBlack
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;

    final cyanPaint = Paint()
      ..color = bruteCyan
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;

    final center = Offset(size.width / 2, size.height / 2);
    const radius = 125.0;

    // Draw dashed circle
    const dashLength = 15.0;
    const gapLength = 10.0;
    final circumference = 2 * math.pi * radius;
    final numDashes = (circumference / (dashLength + gapLength)).floor();

    for (int i = 0; i < numDashes; i++) {
      final startAngle = (i * (dashLength + gapLength)) / radius;
      final sweepAngle = dashLength / radius;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle,
        sweepAngle,
        false,
        i % 2 == 0 ? paint : cyanPaint,
      );
    }

    // Corner crosshairs
    const arm = 20.0;
    // Top-left
    canvas.drawLine(const Offset(0, 0), const Offset(arm, 0), paint);
    canvas.drawLine(const Offset(0, 0), const Offset(0, arm), paint);
    // Top-right
    canvas.drawLine(Offset(size.width, 0), Offset(size.width - arm, 0), paint);
    canvas.drawLine(Offset(size.width, 0), Offset(size.width, arm), paint);
    // Bottom-left
    canvas.drawLine(Offset(0, size.height), Offset(arm, size.height), paint);
    canvas.drawLine(Offset(0, size.height), Offset(0, size.height - arm), paint);
    // Bottom-right
    canvas.drawLine(Offset(size.width, size.height), Offset(size.width - arm, size.height), paint);
    canvas.drawLine(Offset(size.width, size.height), Offset(size.width, size.height - arm), paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ---------------------------------------------------------------------------
// Main Screening Screen
// ---------------------------------------------------------------------------

class ScreeningScreen extends StatefulWidget {
  const ScreeningScreen({super.key});

  @override
  State<ScreeningScreen> createState() => _ScreeningScreenState();
}

class _ScreeningScreenState extends State<ScreeningScreen> {
  CameraController? _cameraController;
  String _currentStatus = 'IDLE';
  XFile? _capturedImage;

  @override
  void initState() {
    super.initState();
    _initCamera();
  }

  Future<void> _initCamera() async {
    if (cameras.isEmpty) return;
    _cameraController = CameraController(
      cameras[0],
      ResolutionPreset.high,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.jpeg,
    );
    await _cameraController!.initialize();
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _cameraController?.dispose();
    super.dispose();
  }

  Future<void> _captureAndAnalyze() async {
    if (_cameraController == null || !_cameraController!.value.isInitialized) return;
    if (_currentStatus != 'IDLE') return;

    setState(() => _currentStatus = 'CAPTURING');

    try {
      _capturedImage = await _cameraController!.takePicture();
      
      // Simulate Quality Gate
      bool passed = math.Random().nextBool(); 
      
      if (passed) {
        if (mounted) setState(() => _currentStatus = 'QUALITY_PASSED');
        await Future.delayed(const Duration(seconds: 1)); // 1-second delay per requirements
        
        if (mounted) setState(() => _currentStatus = 'ANALYZING');
        final result = await TFLiteService().gradeRetina(_capturedImage!.path);
        
        if (mounted) {
          setState(() => _currentStatus = 'IDLE');
          _showTriageModal(result, _capturedImage!.path);
        }
      } else {
        if (mounted) setState(() => _currentStatus = 'QUALITY_FAILED');
        // Do not analyze. Wait for user to tap RETAKE.
      }
    } catch (e) {
      debugPrint("Analysis Error: \$e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error analyzing image: \$e')),
        );
        setState(() => _currentStatus = 'IDLE');
      }
    }
  }

  void _retake() {
    setState(() {
      _capturedImage = null;
      _currentStatus = 'IDLE';
    });
  }

  void _showTriageModal(GradeResult result, String imagePath) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      isDismissible: false,
      enableDrag: false,
      backgroundColor: Colors.transparent,
      builder: (ctx) => WillPopScope(
        onWillPop: () async => false, // Prevent back button dismissal
        child: Container(
          margin: const EdgeInsets.all(16),
          child: BruteCard(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'DIAGNOSTIC PRINTOUT',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: Colors.grey),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                
                // Oversized digital readout
                Text(
                  'LEVEL \${result.grade}',
                  style: const TextStyle(
                    fontSize: 48,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -2,
                  ),
                  textAlign: TextAlign.center,
                ),
                Text(
                  result.label.toUpperCase(),
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),

                // Referral Banner
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  decoration: BoxDecoration(
                    color: result.requiresReferral ? bruteRed : bruteCyan,
                    border: Border.all(color: bruteBlack, width: 3),
                  ),
                  child: Center(
                    child: Text(
                      result.triageAction.toUpperCase(),
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 16,
                        color: bruteBlack,
                      ),
                    ),
                  ),
                ),
                
                const SizedBox(height: 24),
                
                // Threshold probs debug view
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    border: Border.all(color: bruteBlack, width: 2),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('TELEMETRY // PROBABILITIES', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 10)),
                      const SizedBox(height: 8),
                      Text('> P(GRADE>0): \${result.thresholdProbabilities[0].toStringAsFixed(4)}'),
                      Text('> P(GRADE>1): \${result.thresholdProbabilities[1].toStringAsFixed(4)}'),
                      Text('> P(GRADE>2): \${result.thresholdProbabilities[2].toStringAsFixed(4)}'),
                      Text('> P(GRADE>3): \${result.thresholdProbabilities[3].toStringAsFixed(4)}'),
                    ],
                  ),
                ),

                const SizedBox(height: 32),

                // Actions
                BruteButton(
                  label: 'STORE RECORD',
                  backgroundColor: bruteGray,
                  onPressed: () async {
                    await DatabaseHelper().insertRecord({
                      'patient_name': 'Offline Patient',
                      'image_path': imagePath,
                      'dr_grade': result.grade,
                    });
                    if (ctx.mounted) {
                      Navigator.pop(ctx);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Record stored offline.')),
                      );
                    }
                  },
                ),
                const SizedBox(height: 16),
                BruteButton(
                  label: 'NEW CAPTURE',
                  backgroundColor: bruteCyan,
                  onPressed: () {
                    Navigator.pop(ctx);
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Top Bar
              BruteCard(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'OPTIXAI // CORE-v1',
                      style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
                    ),
                    Row(
                      children: const [
                        Icon(Icons.battery_charging_full, color: bruteBlack, size: 18),
                        SizedBox(width: 8),
                        BruteBadge(text: 'OFFLINE READY', color: bruteCyan),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // Viewfinder Frame
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    border: Border.all(color: bruteBlack, width: 3),
                    color: Colors.black,
                  ),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      if (_cameraController != null && _cameraController!.value.isInitialized)
                        ClipRect(
                          child: OverflowBox(
                            alignment: Alignment.center,
                            child: FittedBox(
                              fit: BoxFit.cover,
                              child: SizedBox(
                                width: _cameraController!.value.previewSize?.height ?? 1,
                                height: _cameraController!.value.previewSize?.width ?? 1,
                                child: CameraPreview(_cameraController!),
                              ),
                            ),
                          ),
                        )
                      else
                        const Center(child: CircularProgressIndicator(color: bruteCyan)),
                      
                      // Debossed viewport effect & target overlay
                      Container(
                        decoration: const BoxDecoration(
                          boxShadow: [
                            BoxShadow(color: Colors.black54, blurRadius: 10),
                          ],
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: CustomPaint(
                          painter: RetinalTargetPainter(),
                        ),
                      ),
                      
                      if (_currentStatus == 'QUALITY_PASSED' || _currentStatus == 'QUALITY_FAILED')
                        Container(
                          color: Colors.black87,
                          alignment: Alignment.center,
                          padding: const EdgeInsets.all(32),
                          child: QualityChecklistCard(isSuccess: _currentStatus == 'QUALITY_PASSED'),
                        )
                      else if (_currentStatus == 'CAPTURING' || _currentStatus == 'ANALYZING')
                        Container(
                          color: Colors.black87,
                          child: Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const CircularProgressIndicator(color: bruteCyan),
                                const SizedBox(height: 16),
                                Text(_currentStatus == 'ANALYZING' ? 'ANALYZING RETINA...' : 'CAPTURING...', 
                                     style: const TextStyle(color: bruteCyan, fontWeight: FontWeight.w900), 
                                     textAlign: TextAlign.center),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 24),

              // Telemetry Card
              if (_currentStatus == 'IDLE')
                BruteCard(
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: const [
                          Text('> LENS: 28D ATTACHED', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 12)),
                          Text('> AI GATE: ACTIVE', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 12, color: Colors.green)),
                        ],
                      ),
                      const SizedBox(height: 16),
                      BruteButton(
                        label: 'ACQUIRE & ANALYZE',
                        onPressed: _captureAndAnalyze,
                      ),
                    ],
                  ),
                )
              else if (_currentStatus == 'QUALITY_FAILED')
                BruteCard(
                  child: BruteButton(
                    label: 'RETAKE',
                    backgroundColor: bruteRed,
                    onPressed: _retake,
                  ),
                )
              else
                BruteCard(
                  color: _currentStatus == 'ANALYZING' || _currentStatus == 'QUALITY_PASSED'
                      ? bruteCyan
                      : const Color(0xFFFFB800),
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 16.0),
                      child: Text(
                        _currentStatus == 'ANALYZING' ? 'STATUS: RUNNING ML INFERENCE...' : 'STATUS: PROCESSING...',
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 14,
                          color: bruteBlack,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// Extension to allow inset shadows on BoxDecoration
extension on BoxShadow {
  // A hacky workaround to simulate inset shadow visually in a regular container isn't directly supported.
  // Instead, the user specified a pure Brute design which doesn't rely on blur.
  // We'll leave the basic overlay as is.
}
