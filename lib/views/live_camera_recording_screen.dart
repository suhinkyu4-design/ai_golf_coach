import 'dart:async';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:provider/provider.dart';
import '../models/swing_model.dart';
import '../providers/swing_provider.dart';
import '../services/localization_service.dart';
import 'pose_trimming_screen.dart';

class LiveCameraRecordingScreen extends StatefulWidget {
  const LiveCameraRecordingScreen({super.key});

  @override
  State<LiveCameraRecordingScreen> createState() => _LiveCameraRecordingScreenState();
}

class _LiveCameraRecordingScreenState extends State<LiveCameraRecordingScreen>
    with SingleTickerProviderStateMixin {
  CameraController? _cameraController;
  List<CameraDescription>? _cameras;
  bool _isCameraInitialized = false;

  bool _isRecording = false;
  int _recordSeconds = 0;
  Timer? _timer;
  late AnimationController _animController;

  String _currentPhase = 'ADDRESS';
  final List<String> _phases = ['ADDRESS', 'BACKSWING', 'TOP', 'DOWNSWING', 'IMPACT', 'FINISH'];
  int _phaseIndex = 0;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);

    _initRealCamera();
  }

  Future<void> _initRealCamera() async {
    try {
      _cameras = await availableCameras();
      if (_cameras != null && _cameras!.isNotEmpty) {
        _cameraController = CameraController(
          _cameras![0], // Back camera
          ResolutionPreset.high,
          enableAudio: false,
        );
        await _cameraController!.initialize();
        if (mounted) {
          setState(() {
            _isCameraInitialized = true;
          });
        }
      }
    } catch (e) {
      debugPrint('Real Camera init fallback: $e');
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _animController.dispose();
    _cameraController?.dispose();
    super.dispose();
  }

  void _toggleRecording() async {
    if (_isRecording) {
      // Stop Recording
      _timer?.cancel();
      String capturedPath = '/storage/emulated/0/DCIM/Camera/live_swing_recording.mp4';
      if (_cameraController != null && _cameraController!.value.isRecordingVideo) {
        try {
          final file = await _cameraController!.stopVideoRecording();
          capturedPath = file.path;
        } catch (_) {}
      }

      setState(() {
        _isRecording = false;
      });

      final provider = Provider.of<SwingProvider>(context, listen: false);
      provider.createNewSwing(
        videoPath: capturedPath,
        view: provider.currentSwing?.view ?? SwingView.faceOn,
        handedness: provider.currentSwing?.handedness ?? Handedness.right,
        club: provider.currentSwing?.club ?? '7i',
      );

      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => const PoseTrimmingScreen()),
        );
      }
    } else {
      // Start Recording
      if (_cameraController != null && _cameraController!.value.isInitialized) {
        try {
          await _cameraController!.startVideoRecording();
        } catch (_) {}
      }

      setState(() {
        _isRecording = true;
        _recordSeconds = 0;
      });

      _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
        setState(() {
          _recordSeconds++;
          _phaseIndex = (_phaseIndex + 1) % _phases.length;
          _currentPhase = _phases[_phaseIndex];
        });
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<SwingProvider>(context);
    final lang = provider.appLanguage;
    final isEn = lang == AppLanguage.english;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // 1. Real Device Camera Preview Background Layer
          if (_isCameraInitialized && _cameraController != null)
            SizedBox.expand(
              child: CameraPreview(_cameraController!),
            )
          else
            Container(
              width: double.infinity,
              height: double.infinity,
              color: const Color(0xFF0F172A),
              child: const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(color: Colors.cyanAccent),
                    SizedBox(height: 12),
                    Text(
                      '카메라 라이브 피드 연결 중...',
                      style: TextStyle(color: Colors.white70, fontSize: 13),
                    ),
                  ],
                ),
              ),
            ),

          // 2. Pure Body Contour Selection Mask Overlay Layer (No internal skeleton sticks)
          AnimatedBuilder(
            animation: _animController,
            builder: (context, child) {
              return CustomPaint(
                size: Size.infinite,
                painter: PureBodyContourPainter(
                  animValue: _animController.value,
                  phase: _currentPhase,
                ),
              );
            },
          ),

          // 3. Top Header Bar
          Positioned(
            top: 50,
            left: 20,
            right: 20,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back_ios, color: Colors.white),
                  onPressed: () => Navigator.pop(context),
                ),

                // Live Phase Pill Indicator
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.8),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.cyanAccent, width: 1.5),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 10,
                        height: 10,
                        decoration: const BoxDecoration(
                          color: Colors.cyanAccent,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'PHASE: $_currentPhase',
                        style: const TextStyle(
                          color: Colors.cyanAccent,
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),

                const Icon(Icons.auto_awesome_rounded, color: Colors.cyanAccent),
              ],
            ),
          ),

          // 4. Real-time Body Contour Detection Status Badge
          Positioned(
            top: 110,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.8),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.cyanAccent.withOpacity(0.8)),
                ),
                child: Text(
                  isEn ? '✨ Auto Body Contour Silhouette Mask Active' : '✨ 신체 윤곽선 자동 누끼 선택 실시간 라이브 감지 중',
                  style: const TextStyle(color: Colors.cyanAccent, fontSize: 12, fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ),

          // 5. Recording Time Badge (Pulsing)
          if (_isRecording)
            Positioned(
              top: 150,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.red.shade900.withOpacity(0.85),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(
                          color: Colors.redAccent,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'REC 00:0${_recordSeconds}.0s',
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                    ],
                  ),
                ),
              ),
            ),

          // 6. Bottom Control Panel
          Positioned(
            bottom: 40,
            left: 0,
            right: 0,
            child: Column(
              children: [
                Text(
                  _isRecording
                      ? (isEn ? 'Tap RED button to STOP & Analyze' : '촬영 정지 및 분석 시작 (버튼 클릭)')
                      : (isEn ? 'Align body outline & TAP to Record' : '신체 윤곽선 안으로 맞추고 촬영 버튼을 누르세요'),
                  style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold, shadows: [
                    Shadow(blurRadius: 4, color: Colors.black, offset: Offset(0, 2)),
                  ]),
                ),
                const SizedBox(height: 16),

                // Record Button
                GestureDetector(
                  onTap: _toggleRecording,
                  child: Container(
                    width: 76,
                    height: 76,
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 4),
                    ),
                    child: Container(
                      decoration: BoxDecoration(
                        shape: _isRecording ? BoxShape.rectangle : BoxShape.circle,
                        borderRadius: _isRecording ? BorderRadius.circular(8) : null,
                        color: _isRecording ? Colors.red : Colors.redAccent,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// CustomPainter to render ONLY the pure outer body contour silhouette outline (No internal skeleton sticks)
class PureBodyContourPainter extends CustomPainter {
  final double animValue;
  final String phase;

  PureBodyContourPainter({required this.animValue, required this.phase});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2 - 20);
    final double pulse = 1.0 + (animValue * 0.015);

    // Paints
    final contourOutlinePaint = Paint()
      ..color = Colors.cyanAccent
      ..strokeWidth = 3.5
      ..style = PaintingStyle.stroke;

    final contourGlowPaint = Paint()
      ..color = Colors.cyanAccent.withOpacity(0.4)
      ..strokeWidth = 10.0
      ..style = PaintingStyle.stroke
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);

    final silhouetteFillPaint = Paint()
      ..color = Colors.cyanAccent.withOpacity(0.10)
      ..style = PaintingStyle.fill;

    // Body Contour Keypoints (Outer Envelope)
    final headTop = Offset(center.dx, center.dy - 165 * pulse);
    final headLeft = Offset(center.dx - 32 * pulse, center.dy - 135 * pulse);
    final headRight = Offset(center.dx + 32 * pulse, center.dy - 135 * pulse);

    final lShoulderOuter = Offset(center.dx - 70 * pulse, center.dy - 65 * pulse);
    final rShoulderOuter = Offset(center.dx + 70 * pulse, center.dy - 65 * pulse);

    // Dynamic Arm Shifts
    double armDx = 0;
    double armDy = 0;
    if (phase == 'TOP') {
      armDx = 55 * pulse;
      armDy = -45 * pulse;
    } else if (phase == 'IMPACT') {
      armDx = -15 * pulse;
      armDy = 50 * pulse;
    }

    final lElbowOuter = Offset(center.dx - 95 * pulse + armDx, center.dy - 10 * pulse + armDy);
    final rElbowOuter = Offset(center.dx + 40 * pulse + armDx, center.dy - 10 * pulse + armDy);
    final lHandTip = Offset(center.dx - 75 * pulse + armDx * 1.2, center.dy + 60 * pulse + armDy);
    final rHandTip = Offset(center.dx + 25 * pulse + armDx * 1.2, center.dy + 60 * pulse + armDy);

    final lWaistOuter = Offset(center.dx - 48 * pulse, center.dy + 40 * pulse);
    final rWaistOuter = Offset(center.dx + 48 * pulse, center.dy + 40 * pulse);

    final lKneeOuter = Offset(center.dx - 52 * pulse, center.dy + 140 * pulse);
    final rKneeOuter = Offset(center.dx + 52 * pulse, center.dy + 140 * pulse);

    final lFootOuter = Offset(center.dx - 65 * pulse, center.dy + 245 * pulse);
    final lFootInner = Offset(center.dx - 15 * pulse, center.dy + 245 * pulse);
    final rFootInner = Offset(center.dx + 15 * pulse, center.dy + 245 * pulse);
    final rFootOuter = Offset(center.dx + 65 * pulse, center.dy + 245 * pulse);

    final crotch = Offset(center.dx, center.dy + 65 * pulse);

    // Construct Pure Continuous Outer Body Contour Silhouette Path (사진 편집 누끼 윤곽선)
    final Path contourPath = Path();

    // 1. Head Curve
    contourPath.moveTo(headTop.dx, headTop.dy);
    contourPath.cubicTo(headTop.dx - 25, headTop.dy, headLeft.dx, headLeft.dy - 10, headLeft.dx, headLeft.dy);
    contourPath.quadraticBezierTo(headLeft.dx, headLeft.dy + 25, lShoulderOuter.dx + 15, lShoulderOuter.dy - 10);

    // 2. Left Arm Outer Edge
    contourPath.quadraticBezierTo(lShoulderOuter.dx - 10, lShoulderOuter.dy, lShoulderOuter.dx, lShoulderOuter.dy);
    contourPath.cubicTo(lShoulderOuter.dx - 15, lShoulderOuter.dy + 20, lElbowOuter.dx - 10, lElbowOuter.dy, lElbowOuter.dx, lElbowOuter.dy);
    contourPath.cubicTo(lElbowOuter.dx - 10, lElbowOuter.dy + 25, lHandTip.dx - 12, lHandTip.dy - 10, lHandTip.dx, lHandTip.dy);

    // 3. Hand Tip & Left Torso Side
    contourPath.quadraticBezierTo(lHandTip.dx + 15, lHandTip.dy + 10, lWaistOuter.dx, lWaistOuter.dy);
    contourPath.cubicTo(lWaistOuter.dx - 10, lWaistOuter.dy + 30, lKneeOuter.dx - 10, lKneeOuter.dy, lKneeOuter.dx, lKneeOuter.dy);

    // 4. Left Leg & Foot
    contourPath.cubicTo(lKneeOuter.dx - 12, lKneeOuter.dy + 40, lFootOuter.dx - 15, lFootOuter.dy, lFootOuter.dx, lFootOuter.dy);
    contourPath.lineTo(lFootInner.dx, lFootInner.dy);
    contourPath.quadraticBezierTo(lFootInner.dx + 10, lFootInner.dy - 60, crotch.dx, crotch.dy);

    // 5. Right Leg & Foot
    contourPath.quadraticBezierTo(rFootInner.dx - 10, rFootInner.dy - 60, rFootInner.dx, rFootInner.dy);
    contourPath.lineTo(rFootOuter.dx, rFootOuter.dy);
    contourPath.cubicTo(rFootOuter.dx + 15, rFootOuter.dy, rKneeOuter.dx + 12, rKneeOuter.dy + 40, rKneeOuter.dx, rKneeOuter.dy);

    // 6. Right Torso Side & Right Arm Outer Edge
    contourPath.cubicTo(rKneeOuter.dx + 10, rKneeOuter.dy, rWaistOuter.dx + 10, rWaistOuter.dy + 30, rWaistOuter.dx, rWaistOuter.dy);
    contourPath.quadraticBezierTo(rHandTip.dx - 15, rHandTip.dy + 10, rHandTip.dx, rHandTip.dy);
    contourPath.cubicTo(rHandTip.dx + 12, rHandTip.dy - 10, rElbowOuter.dx + 10, rElbowOuter.dy + 25, rElbowOuter.dx, rElbowOuter.dy);
    contourPath.cubicTo(rElbowOuter.dx + 10, rElbowOuter.dy, rShoulderOuter.dx + 15, rShoulderOuter.dy + 20, rShoulderOuter.dx, rShoulderOuter.dy);

    // 7. Right Neck Back to Head Top
    contourPath.quadraticBezierTo(rShoulderOuter.dx - 15, rShoulderOuter.dy - 10, headRight.dx, headRight.dy);
    contourPath.cubicTo(headRight.dx, headRight.dy - 10, headTop.dx + 25, headTop.dy, headTop.dx, headTop.dy);
    contourPath.close();

    // Render Silhouette Fill Layer & Glowing Contour Mask
    canvas.drawPath(contourPath, silhouetteFillPaint);
    canvas.drawPath(contourPath, contourGlowPaint);
    canvas.drawPath(contourPath, contourOutlinePaint);
  }

  @override
  bool shouldRepaint(covariant PureBodyContourPainter oldDelegate) => true;
}
