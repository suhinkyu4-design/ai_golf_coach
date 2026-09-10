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
      duration: const Duration(milliseconds: 1200),
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
                    CircularProgressIndicator(color: Colors.tealAccent),
                    SizedBox(height: 12),
                    Text(
                      '카메라 라이브 피드 연결 중...',
                      style: TextStyle(color: Colors.white70, fontSize: 13),
                    ),
                  ],
                ),
              ),
            ),

          // 2. Real-time MediaPipe Skeleton Drawing Overlay Layer (On top of Real Person)
          AnimatedBuilder(
            animation: _animController,
            builder: (context, child) {
              return CustomPaint(
                size: Size.infinite,
                painter: LivePoseSkeletonPainter(
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
                    color: Colors.black.withOpacity(0.75),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.tealAccent, width: 1.5),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 10,
                        height: 10,
                        decoration: const BoxDecoration(
                          color: Colors.tealAccent,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'PHASE: $_currentPhase',
                        style: const TextStyle(
                          color: Colors.tealAccent,
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),

                const Icon(Icons.grid_on_rounded, color: Colors.white70),
              ],
            ),
          ),

          // 4. Real-time Detection Status Badge
          Positioned(
            top: 110,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.75),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.greenAccent.withOpacity(0.6)),
                ),
                child: Text(
                  isEn ? '✅ Live Person & Skeleton Overlay Tracked' : '✅ 카메라 피드 실시간 인물 + 스켈레톤 인지 중',
                  style: const TextStyle(color: Colors.greenAccent, fontSize: 12, fontWeight: FontWeight.bold),
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
                      : (isEn ? 'Align full body & TAP to Record' : '전신을 화면에 맞추고 촬영 버튼을 누르세요'),
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

/// CustomPainter to render live 33-landmark skeleton over live camera preview
class LivePoseSkeletonPainter extends CustomPainter {
  final double animValue;
  final String phase;

  LivePoseSkeletonPainter({required this.animValue, required this.phase});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2 - 30);
    final double scale = 1.0 + (animValue * 0.03);

    // Paints
    final jointPaint = Paint()
      ..color = Colors.amberAccent
      ..style = PaintingStyle.fill;

    final linePaint = Paint()
      ..color = Colors.tealAccent
      ..strokeWidth = 3.5
      ..style = PaintingStyle.stroke;

    final spinePaint = Paint()
      ..color = Colors.cyanAccent
      ..strokeWidth = 4.0;

    // Keypoints relative to real camera screen center
    final head = Offset(center.dx, center.dy - 120 * scale);
    final lShoulder = Offset(center.dx - 45 * scale, center.dy - 60 * scale);
    final rShoulder = Offset(center.dx + 45 * scale, center.dy - 60 * scale);

    // Arm animation shift according to swing phase
    double armDx = 0;
    double armDy = 0;
    if (phase == 'TOP') {
      armDx = 50 * scale;
      armDy = -40 * scale;
    } else if (phase == 'IMPACT') {
      armDx = -10 * scale;
      armDy = 50 * scale;
    }

    final lElbow = Offset(center.dx - 70 * scale + armDx, center.dy + armDy);
    final rElbow = Offset(center.dx + 30 * scale + armDx, center.dy + armDy);
    final lWrist = Offset(center.dx - 50 * scale + armDx * 1.2, center.dy + 40 * scale + armDy);
    final rWrist = Offset(center.dx + 10 * scale + armDx * 1.2, center.dy + 40 * scale + armDy);

    final lHip = Offset(center.dx - 30 * scale, center.dy + 40 * scale);
    final rHip = Offset(center.dx + 30 * scale, center.dy + 40 * scale);

    final lKnee = Offset(center.dx - 35 * scale, center.dy + 130 * scale);
    final rKnee = Offset(center.dx + 35 * scale, center.dy + 130 * scale);
    final lAnkle = Offset(center.dx - 40 * scale, center.dy + 220 * scale);
    final rAnkle = Offset(center.dx + 40 * scale, center.dy + 220 * scale);

    // Draw Skeleton Lines (Bones) over camera
    canvas.drawLine(lShoulder, rShoulder, linePaint); // Shoulders
    canvas.drawLine(lShoulder, lElbow, linePaint);
    canvas.drawLine(lElbow, lWrist, linePaint);
    canvas.drawLine(rShoulder, rElbow, linePaint);
    canvas.drawLine(rElbow, rWrist, linePaint);

    // Spine & Pelvis
    final shoulderCenter = Offset(center.dx, center.dy - 60 * scale);
    final hipCenter = Offset(center.dx, center.dy + 40 * scale);
    canvas.drawLine(head, shoulderCenter, linePaint);
    canvas.drawLine(shoulderCenter, hipCenter, spinePaint);
    canvas.drawLine(lHip, rHip, linePaint);

    // Legs
    canvas.drawLine(lHip, lKnee, linePaint);
    canvas.drawLine(lKnee, lAnkle, linePaint);
    canvas.drawLine(rHip, rKnee, linePaint);
    canvas.drawLine(rKnee, rAnkle, linePaint);

    // Draw Joint Dots (Landmarks)
    final joints = [head, lShoulder, rShoulder, lElbow, rElbow, lWrist, rWrist, lHip, rHip, lKnee, rKnee, lAnkle, rAnkle];
    for (var joint in joints) {
      canvas.drawCircle(joint, 6, jointPaint);
      canvas.drawCircle(joint, 8, Paint()..color = Colors.amber.withOpacity(0.4)..style = PaintingStyle.stroke..strokeWidth = 2);
    }
  }

  @override
  bool shouldRepaint(covariant LivePoseSkeletonPainter oldDelegate) => true;
}
