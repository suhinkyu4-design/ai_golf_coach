// Android replacement for camera 0.10.6 + google_mlkit_pose_detection 0.10.0.
// Actual landmarks only. No silhouette segmentation or automatic swing phases.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import 'package:provider/provider.dart';
import '../models/swing_model.dart';
import '../providers/swing_provider.dart';
import 'pose_trimming_screen.dart';

class LiveCameraRecordingScreen extends StatefulWidget {
  const LiveCameraRecordingScreen({super.key});
  @override
  State<LiveCameraRecordingScreen> createState() => _LiveCameraRecordingScreenState();
}

class _LiveCameraRecordingScreenState extends State<LiveCameraRecordingScreen>
    with WidgetsBindingObserver {
  final _detector = PoseDetector(options: PoseDetectorOptions(
    mode: PoseDetectionMode.stream, model: PoseDetectionModel.base));
  CameraController? _camera;
  Future<void> _operations = Future<void>.value();
  Future<void>? _inference;
  bool _closed = false, _active = true, _acceptFrames = false, _busy = false;
  bool _recording = false, _leaving = false;
  Pose? _pose;
  Size _poseSize = Size.zero;
  String _status = '카메라 연결 중';
  String? _cameraError, _savedVideo, _saveWarning;
  DateTime? _lastResult;
  final _clock = Stopwatch()..start();
  final _recordClock = Stopwatch();
  int _lastFrameMs = -1000;
  Timer? _watchdog;
  List<Map<String, dynamic>> _samples = [];
  Map<String, dynamic>? _reference;
  double? _leftKnee, _rightKnee;

  bool get _ready => _camera?.value.isInitialized == true;
  void _refresh() { if (mounted && !_closed) setState(() {}); }
  Future<void> _enqueue(Future<void> Function() task) {
    _operations = _operations.then((_) async {
      try { await task(); }
      catch (e, st) {
        debugPrint('Live pose: $e\n$st');
        if (!_closed) { _status = '처리 실패: $e'; _refresh(); }
      }
    });
    return _operations;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _enqueue(_open);
    _watchdog = Timer.periodic(const Duration(milliseconds: 250), (_) {
      if (_closed) return;
      if (_lastResult != null && DateTime.now().difference(_lastResult!).inMilliseconds > 800) {
        _pose = null; _leftKnee = null; _rightKnee = null;
        if (_acceptFrames) _status = '인식 결과를 기다리는 중';
      }
      _refresh();
      if (_recording && _recordClock.isRunning && _recordClock.elapsed.inSeconds >= 30 && !_busy) {
        _toggleRecord(); // Keep per-shot buffers bounded.
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _active = true;
      _enqueue(() async { if (!_closed && _savedVideo == null) await _open(); });
    } else if (state == AppLifecycleState.inactive || state == AppLifecycleState.paused) {
      _active = false; _acceptFrames = false;
      _enqueue(() async {
        try { if (_recording) await _finishRecording(); }
        finally { await _releaseCamera(); }
        if (!_closed && _savedVideo == null) _status = '촬영 일시 중지';
        _refresh();
      });
    }
  }

  Future<void> _open() async {
    if (_closed || !_active || _camera != null || _savedVideo != null) return;
    _cameraError = null;
    try {
      if (!Platform.isAndroid) throw UnsupportedError('이번 교체본은 Android용입니다.');
      final cameras = await availableCameras();
      final rear = cameras.where((c) => c.lensDirection == CameraLensDirection.back);
      if (rear.isEmpty) throw StateError('후면 카메라를 찾지 못했습니다.');
      if (_closed || !_active) return;
      final c = CameraController(rear.first, ResolutionPreset.high,
        enableAudio: false, imageFormatGroup: ImageFormatGroup.yuv420);
      _camera = c;
      await c.initialize();
      if (_closed || !_active) { await _releaseCamera(); return; }
      await c.lockCaptureOrientation(DeviceOrientation.portraitUp);
      _acceptFrames = true;
      await c.startImageStream(_onFrame);
      _status = '전신이 보이도록 세로로 촬영하세요';
    } catch (e) {
      _cameraError = '카메라를 열 수 없습니다: $e';
      await _releaseCamera();
    }
    _refresh();
  }

  Future<void> _drainInference() async {
    final pending = _inference;
    if (pending != null) await pending;
  }
  Future<void> _releaseCamera() async {
    _acceptFrames = false;
    await _drainInference();
    final c = _camera; _camera = null; _pose = null;
    if (c != null) await c.dispose();
  }

  void _onFrame(CameraImage image) {
    final c = _camera;
    if (!_acceptFrames || _closed || !_active || c == null || _inference != null) return;
    // This first integration deliberately supports upright portrait capture only.
    if (c.value.deviceOrientation != DeviceOrientation.portraitUp) {
      _pose = null; _leftKnee = null; _rightKnee = null;
      _status = '휴대폰을 세로 방향으로 세워주세요'; _refresh(); return;
    }
    final now = _clock.elapsedMilliseconds;
    if (now - _lastFrameMs < 100) return; // <=10 inference requests/sec; no queue.
    _lastFrameMs = now;
    final sampleMs = _recording ? _recordClock.elapsedMilliseconds : null;
    final degrees = c.description.sensorOrientation;
    _inference = _detect(image, degrees, sampleMs).whenComplete(() { _inference = null; });
  }

  Future<void> _detect(CameraImage image, int degrees, int? sampleMs) async {
    try {
      final rotation = InputImageRotationValue.fromRawValue(degrees);
      if (rotation == null) throw StateError('지원하지 않는 회전값: $degrees');
      final bytes = _toNv21(image);
      final result = await _detector.processImage(InputImage.fromBytes(bytes: bytes,
        metadata: InputImageMetadata(size: Size(image.width.toDouble(), image.height.toDouble()),
          rotation: rotation, format: InputImageFormat.nv21, bytesPerRow: image.width)));
      if (_closed || !_active || !_acceptFrames) return;
      final upright = degrees == 90 || degrees == 270
        ? Size(image.height.toDouble(), image.width.toDouble())
        : Size(image.width.toDouble(), image.height.toDouble());
      Pose? pose = result.isEmpty ? null : result.first;
      if (pose != null && !_torsoVisible(pose, upright)) pose = null;
      _pose = pose; _poseSize = upright; _lastResult = DateTime.now();
      _leftKnee = pose == null ? null : _angle(pose, PoseLandmarkType.leftHip,
        PoseLandmarkType.leftKnee, PoseLandmarkType.leftAnkle);
      _rightKnee = pose == null ? null : _angle(pose, PoseLandmarkType.rightHip,
        PoseLandmarkType.rightKnee, PoseLandmarkType.rightAnkle);
      _status = pose == null ? '사람을 찾는 중'
        : _fullBody(pose, upright) ? '전신 인식됨 · 어드레스는 직접 확인하세요'
        : '일부 관절만 보입니다 · 발과 손까지 나오게 해주세요';
      if (sampleMs != null) {
        _samples.add({'t_ms': sampleMs, 'width': upright.width, 'height': upright.height,
          'detected': pose != null, 'landmarks': pose == null ? [] : _landmarks(pose)});
      }
      _refresh();
    } catch (e) {
      if (_closed) return;
      _pose = null; _leftKnee = null; _rightKnee = null;
      _lastResult = null;
      _status = '자세 인식 오류: $e'; _refresh();
    }
  }

  // YUV_420_888 planes have row padding and possibly interleaved chroma.
  // Copy samples using row/pixel strides, then interleave V,U for NV21.
  Uint8List _toNv21(CameraImage image) {
    final w = image.width, h = image.height;
    if (w.isOdd || h.isOdd) throw StateError('짝수 크기의 영상 프레임이 필요합니다.');
    if (image.format.raw == 17 && image.planes.length == 1) {
      final b = image.planes.first.bytes;
      if (b.length != w * h * 3 ~/ 2) throw StateError('NV21 버퍼 크기를 확인해주세요.');
      return b;
    }
    if (image.format.group != ImageFormatGroup.yuv420 || image.planes.length != 3) {
      throw StateError('YUV420 3-plane 입력 필요: ${image.format.raw}, ${image.planes.length} planes');
    }
    final out = Uint8List(w * h * 3 ~/ 2);
    int offset = 0;
    final y = image.planes[0], u = image.planes[1], v = image.planes[2];
    for (int row = 0; row < h; row++) {
      for (int col = 0; col < w; col++) {
        out[offset++] = y.bytes[row * y.bytesPerRow + col * (y.bytesPerPixel ?? 1)];
      }
    }
    for (int row = 0; row < h ~/ 2; row++) {
      for (int col = 0; col < w ~/ 2; col++) {
        out[offset++] = v.bytes[row * v.bytesPerRow + col * (v.bytesPerPixel ?? 1)];
        out[offset++] = u.bytes[row * u.bytesPerRow + col * (u.bytesPerPixel ?? 1)];
      }
    }
    return out;
  }

  bool _visible(Pose pose, PoseLandmarkType type, Size size) {
    final p = pose.landmarks[type];
    return p != null && p.likelihood >= .6 && p.x >= 0 && p.y >= 0 && p.x < size.width && p.y < size.height;
  }
  bool _torsoVisible(Pose p, Size s) => [PoseLandmarkType.leftShoulder,
    PoseLandmarkType.rightShoulder, PoseLandmarkType.leftHip, PoseLandmarkType.rightHip]
      .where((t) => _visible(p, t, s)).length >= 3;
  bool _fullBody(Pose p, Size s) => [PoseLandmarkType.nose,
    PoseLandmarkType.leftShoulder, PoseLandmarkType.rightShoulder,
    PoseLandmarkType.leftWrist, PoseLandmarkType.rightWrist,
    PoseLandmarkType.leftHip, PoseLandmarkType.rightHip,
    PoseLandmarkType.leftKnee, PoseLandmarkType.rightKnee,
    PoseLandmarkType.leftAnkle, PoseLandmarkType.rightAnkle].every((t) => _visible(p, t, s));
  List<Map<String, dynamic>> _landmarks(Pose p) => p.landmarks.entries.map((e) => {
    'name': e.key.name, 'x': e.value.x, 'y': e.value.y,
    'z_estimated': e.value.z, 'likelihood': e.value.likelihood,
  }).toList();
  double? _angle(Pose p, PoseLandmarkType a, PoseLandmarkType b, PoseLandmarkType c) {
    final x = p.landmarks[a], y = p.landmarks[b], z = p.landmarks[c];
    if (x == null || y == null || z == null || x.likelihood < .6 || y.likelihood < .6 || z.likelihood < .6) return null;
    final u = Offset(x.x-y.x, x.y-y.y), v = Offset(z.x-y.x, z.y-y.y);
    final d = u.distance * v.distance;
    if (d < 1e-6) return null;
    return math.acos(((u.dx*v.dx + u.dy*v.dy)/d).clamp(-1.0, 1.0)) * 180 / math.pi;
  }

  void _setReference() {
    final p = _pose;
    if (p == null || !_fullBody(p, _poseSize)) return;
    _reference = {'kind': 'user_confirmed_address', 'width': _poseSize.width,
      'height': _poseSize.height, 'landmarks': _landmarks(p)};
    _refresh();
  }

  void _toggleRecord() {
    if (_busy || !_ready || _savedVideo != null) return;
    _busy = true; _refresh();
    _enqueue(() async {
      try {
        if (_closed || !_active) return;
        if (_recording) {
          await _finishRecording();
        } else {
          final c = _camera!;
          _acceptFrames = false;
          if (c.value.isStreamingImages) await c.stopImageStream();
          await _drainInference();
          _samples = []; _saveWarning = null; _pose = null;
          _recordClock.reset();
          // Approximate arrival timestamps, NOT encoded-video PTS.
          _recordClock.start(); _recording = true; _acceptFrames = true;
          try {
            await c.startVideoRecording(onAvailable: _onFrame);
          } catch (e) {
            _recording = false; _recordClock.stop(); _acceptFrames = false;
            await _drainInference();
            _samples = [];
            _status = '녹화 시작 실패';
            // Restore preview after a failed combined recording/stream request.
            if (_active && !_closed) {
              await _releaseCamera(); await _open();
              _status = '녹화 시작 실패: $e';
            }
          }
        }
      } finally { _busy = false; _refresh(); }
    });
  }

  Future<void> _finishRecording() async {
    final c = _camera;
    if (c == null || !c.value.isRecordingVideo) {
      _recording = false; _recordClock.stop();
      throw StateError('실제 녹화가 시작되지 않았습니다.');
    }
    // Stop accepting results before flushing the already collected samples.
    _acceptFrames = false;
    await _drainInference();
    XFile video;
    try { video = await c.stopVideoRecording(); }
    catch (e) {
      _recordClock.stop(); _recording = c.value.isRecordingVideo;
      _status = '녹화 종료 실패: $e'; _refresh(); rethrow;
    }
    _recordClock.stop(); _recording = false;
    final file = File(video.path);
    if (!await file.exists() || await file.length() == 0) throw StateError('영상 파일이 비어 있습니다.');
    _savedVideo = video.path;
    try {
      await File('${video.path}.pose.json').writeAsString(jsonEncode({
        'schema_version': '1.0', 'source': 'mlkit_pose_detection',
        'video_path': video.path, 'coordinate_space': 'upright_image_pixels',
        'timestamp_basis': 'host_callback_elapsed_ms_from_start_request',
        'video_pts_synchronized': false, 'handedness_normalized': false,
        'reference': _reference, 'samples': _samples,
      }), flush: true);
    } catch (e) { _saveWarning = '관절 좌표 파일 저장 실패: $e'; }
    _pose = null;
    _status = '영상 저장 완료 · 좌표 ${_samples.length}개 프레임';
    _refresh();
  }

  void _continue() {
    if (_busy || _savedVideo == null || _leaving) return;
    final provider = Provider.of<SwingProvider>(context, listen: false);
    final old = provider.currentSwing;
    provider.createNewSwing(videoPath: _savedVideo!, view: old?.view ?? SwingView.faceOn,
      handedness: old?.handedness ?? Handedness.right, club: old?.club ?? '7i');
    _leaving = true;
    Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const PoseTrimmingScreen()));
  }

  @override
  void dispose() {
    _closed = true; _acceptFrames = false; _watchdog?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _enqueue(() async {
      await _releaseCamera();
      await _detector.close();
    });
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = _camera;
    final seconds = _recordClock.elapsed.inSeconds;
    final time = '${(seconds ~/ 60).toString().padLeft(2, '0')}:${(seconds % 60).toString().padLeft(2, '0')}';
    return WillPopScope(
      onWillPop: () async => !_recording && !_busy,
      child: Scaffold(backgroundColor: Colors.black,
        appBar: AppBar(title: const Text('스윙 촬영'),
          automaticallyImplyLeading: !_recording && !_busy),
        body: SafeArea(child: Column(children: [
          Expanded(child: LayoutBuilder(builder: (context, constraints) {
            if (c == null || !c.value.isInitialized) {
              return Center(child: Padding(padding: const EdgeInsets.all(20), child: Column(
                mainAxisSize: MainAxisSize.min, children: [
                Text(_cameraError ?? (_savedVideo != null ? '촬영 완료' : '카메라 연결 중'), style: const TextStyle(color: Colors.white)),
                if (_cameraError != null) TextButton(onPressed: () => _enqueue(_open), child: const Text('다시 연결')),
              ])));
            }
            // Letterbox both preview and painter in the SAME rectangle; never stretch.
            final ratio = 1 / c.value.aspectRatio;
            double w = constraints.maxWidth, h = w / ratio;
            if (h > constraints.maxHeight) { h = constraints.maxHeight; w = h * ratio; }
            return Center(child: SizedBox(width: w, height: h, child: Stack(fit: StackFit.expand, children: [
              CameraPreview(c),
              IgnorePointer(child: CustomPaint(painter: _PosePainter(_pose, _poseSize))),
            ])));
          })),
          Padding(padding: const EdgeInsets.all(12), child: Column(children: [
            Text(_status, textAlign: TextAlign.center, style: const TextStyle(color: Colors.cyanAccent)),
            if (_savedVideo == null) Text('영상상 무릎 각도  좌 ${_leftKnee?.toStringAsFixed(0) ?? "—"}° / 우 ${_rightKnee?.toStringAsFixed(0) ?? "—"}°',
              style: const TextStyle(color: Colors.white70)),
            if (_saveWarning != null) Text(_saveWarning!, style: const TextStyle(color: Colors.orangeAccent)),
            const SizedBox(height: 8),
            if (_savedVideo != null)
              ElevatedButton(onPressed: _busy ? null : _continue, child: const Text('촬영 영상으로 다음 단계'))
            else Wrap(alignment: WrapAlignment.center, spacing: 12, runSpacing: 8, children: [
              TextButton(onPressed: !_busy && !_recording && _pose != null && _fullBody(_pose!, _poseSize)
                ? _setReference : null, child: Text(_reference == null ? '현재 자세를 기준으로 저장' : '기준 자세 다시 저장')),
              ElevatedButton(onPressed: _ready && !_busy ? _toggleRecord : null,
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFD74A48), foregroundColor: Colors.white, minimumSize: const Size(100, 50)),
                child: Text(_busy ? '처리 중' : _recording ? '정지 $time' : '촬영 시작')),
            ]),
            const Text('후면 카메라 · 세로 촬영 · 최대 30초\n관절선은 추정값이며 자동 스윙 단계 판정은 제공하지 않습니다.',
              textAlign: TextAlign.center, style: TextStyle(color: Colors.white54, fontSize: 11)),
          ])),
        ])),
      ));
  }
}

class _PosePainter extends CustomPainter {
  final Pose? pose;
  final Size source;
  _PosePainter(this.pose, this.source);
  static const edges = [
    [PoseLandmarkType.leftShoulder, PoseLandmarkType.rightShoulder],
    [PoseLandmarkType.leftShoulder, PoseLandmarkType.leftElbow],
    [PoseLandmarkType.leftElbow, PoseLandmarkType.leftWrist],
    [PoseLandmarkType.rightShoulder, PoseLandmarkType.rightElbow],
    [PoseLandmarkType.rightElbow, PoseLandmarkType.rightWrist],
    [PoseLandmarkType.leftShoulder, PoseLandmarkType.leftHip],
    [PoseLandmarkType.rightShoulder, PoseLandmarkType.rightHip],
    [PoseLandmarkType.leftHip, PoseLandmarkType.rightHip],
    [PoseLandmarkType.leftHip, PoseLandmarkType.leftKnee],
    [PoseLandmarkType.leftKnee, PoseLandmarkType.leftAnkle],
    [PoseLandmarkType.rightHip, PoseLandmarkType.rightKnee],
    [PoseLandmarkType.rightKnee, PoseLandmarkType.rightAnkle],
    [PoseLandmarkType.leftAnkle, PoseLandmarkType.leftHeel],
    [PoseLandmarkType.leftHeel, PoseLandmarkType.leftFootIndex],
    [PoseLandmarkType.rightAnkle, PoseLandmarkType.rightHeel],
    [PoseLandmarkType.rightHeel, PoseLandmarkType.rightFootIndex],
  ];
  @override
  void paint(Canvas canvas, Size size) {
    final p = pose;
    if (p == null || source.isEmpty) return;
    bool visible(PoseLandmark l) => l.likelihood >= .6 && l.x >= 0 && l.y >= 0 && l.x < source.width && l.y < source.height;
    Offset project(PoseLandmark l) => Offset(l.x * size.width/source.width, l.y * size.height/source.height);
    final pen = Paint()..color = Colors.cyanAccent..strokeWidth = 3;
    canvas.save(); canvas.clipRect(Offset.zero & size);
    for (final edge in edges) {
      final a = p.landmarks[edge[0]], b = p.landmarks[edge[1]];
      if (a != null && b != null && visible(a) && visible(b)) canvas.drawLine(project(a), project(b), pen);
    }
    pen.color = Colors.yellowAccent;
    for (final l in p.landmarks.values) { if (visible(l)) canvas.drawCircle(project(l), 3, pen); }
    canvas.restore();
  }
  @override
  bool shouldRepaint(covariant _PosePainter old) => old.pose != pose || old.source != source;
}
