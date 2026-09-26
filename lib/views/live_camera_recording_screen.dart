import 'appearance_settings_screen.dart';
import '../widgets/coach_app_bar.dart';
import '../services/assistant_operation_log.dart';
import 'dart:async';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/app_error_log.dart';
import 'package:provider/provider.dart';
import '../providers/voice_settings.dart';

/// Records only. The caller analyzes the saved file through GalleryPoseService.
class LiveCameraRecordingScreen extends StatefulWidget {
  const LiveCameraRecordingScreen({super.key});
  @override
  State<LiveCameraRecordingScreen> createState() => _LiveCameraRecordingScreenState();
}

class _LiveCameraRecordingScreenState extends State<LiveCameraRecordingScreen> with WidgetsBindingObserver {
  static const _channel = MethodChannel('com.metaoffice.aigolfcoatch/frame_extractor');
  static const _voice = MethodChannel('com.metaoffice.aigolfcoatch/voice_capture');
  bool _voiceEnabled = false, _voiceChanging = false, _voiceAuto = false;
  String _voiceStatus = '음성 명령을 준비하고 있습니다.';
  bool _voiceConfigured = false;
  CameraController? _camera;
  Future<void> _operations = Future.value();
  bool _active = true, _closed = false, _busy = false, _recording = false, _returning = false;
  bool _previewAttached = false;
  String? _rawVideo, _savedPath, _error;
  String _status = '카메라 연결 중…';
  final _clock = Stopwatch();
  Timer? _timer;
  void _refresh() { if (mounted && !_closed) setState(() {}); }
  Future<void> _enqueue(Future<void> Function() task) {
    _operations = _operations.then((_) async {
      try { await task(); } catch (e, stack) {
        AppErrorLog.record('CAPTURE_ERROR', '$e\n$stack');
        if (!_closed) AssistantOperationLog.current.fail('recording', e);
        _error = '$e'; _refresh();
      }
    });
    return _operations;
  }
  @override
  void initState() {
    super.initState();
    AssistantOperationLog.current.begin();
    _voiceConfigured = context.read<VoiceSettings>().enabled;
    _voiceAuto = _voiceConfigured;
    WidgetsBinding.instance.addObserver(this);
    _bindCaptureVoice();
    _enqueue(_initialize);
    _timer = Timer.periodic(Duration(milliseconds: 250), (_) {
      if (_recording) {
        _refresh();
        if (_clock.elapsed.inSeconds >= 30 && !_busy) _toggle();
      }
    });
  }
  void _bindCaptureVoice() {
    _voice.setMethodCallHandler((call) async {
      if (call.method != 'state' || !_voiceEnabled || !_active || _closed) return;
      final state = Map<String, dynamic>.from(call.arguments as Map);
      final status = state['status'] as String;
      _voiceStatus = status == 'listening' ? '음성 명령 듣는 중' : status == 'processing' ? '명령 확인 중…' : '음성 대기 연결 중…';
      if (status == 'expired') {
        _voiceEnabled = false;
        _ensureVoice();
        return;
      }
      if (status.startsWith('unavailable')) {
        _voiceAuto = false;
        _voiceEnabled = false;
        _voiceStatus = '음성 인식을 사용할 수 없습니다. 촬영 버튼을 이용해 주세요.';
      }
      if (state['command'] == 'start' && !_recording && !_busy) _startByVoice();
      if (state['command'] == 'stop' && _recording && !_busy) _toggle();
      _refresh();
    });
  }
  Future<void> _openSettings() async {
    if (_recording || _busy || _voiceChanging) return;
    setState(() { _busy = true; _voiceAuto = false; });
    try {
      await _setVoice(false);
      if (!mounted) return;
      await Navigator.push(context, MaterialPageRoute(builder: (_) => const AppearanceSettingsScreen()));
    } finally {
      if (mounted) {
        _bindCaptureVoice();
        _voiceConfigured = context.read<VoiceSettings>().enabled;
        _voiceAuto = _voiceConfigured;
        setState(() => _busy = false);
        _ensureVoice();
      }
    }
  }
  void _ensureVoice() {
    if (_voiceAuto && !_voiceEnabled && !_voiceChanging && !_closed && _active &&
        !_busy && _rawVideo == null && _camera?.value.isInitialized == true) {
      unawaited(_setVoice(true));
    }
  }
  Future<void> _setVoice(bool value) async {
    if (_voiceChanging) return;
    _voiceChanging = true; _refresh();
    try {
      if (value) {
        _voiceEnabled = true;
        _voiceStatus = '음성 인식 연결 중…';
        await _voice.invokeMethod('enable');
        AssistantOperationLog.current.success('voice');
        if (!_active || _closed) { _voiceEnabled = false; await _voice.invokeMethod('disable'); _voiceStatus = '촬영 화면으로 돌아오면 음성 대기를 시작합니다.'; }
      } else { _voiceEnabled = false; await _voice.invokeMethod('disable'); _voiceStatus = '음성 제어 꺼짐'; }
    } catch (e) {
      _voiceAuto = false;
      _voiceEnabled = false;
      AssistantOperationLog.current.fail('voice', e);
      _voiceStatus = e is PlatformException ? (e.message ?? '음성 인식 연결 실패') : '음성 인식 연결 실패';
    } finally { _voiceChanging = false; _refresh(); _ensureVoice(); }
  }
  void _startByVoice() {
    _busy = true; _refresh();
    _enqueue(() async {
      try {
        for (var i = 3; i > 0; i--) {
          if (_closed || !_active || !_voiceEnabled) return;
          _status = '$i초 후 촬영 시작'; _refresh();
          await _voice.invokeMethod('tone');
          await Future<void>.delayed(const Duration(seconds: 1));
        }
        if (_closed || !_active || !_voiceEnabled) return;
        await _startRecording();
        await _voice.invokeMethod('tone');
      } finally { _busy = false; _refresh(); }
    });
  }
  Future<void> _startRecording() async {
    final c = _camera;
    if (c == null || !c.value.isInitialized) return;
    _error = null;
    await c.startVideoRecording();
    AssistantOperationLog.current.success('recording');
    _recording = true; _clock.reset(); _clock.start();
    _status = '촬영 중';
    AppErrorLog.record('CAPTURE_STAGE', 'recording_started voice=$_voiceEnabled');
  }
  Future<void> _initialize() async {
    if (_closed || !_active || _camera != null || _rawVideo != null) return;
    _busy = true; _error = null; _refresh();
    try {
      final devices = await availableCameras();
      if (_closed || !_active) return;
      final camera = devices.firstWhere((c) => c.lensDirection == CameraLensDirection.back);
      final controller = CameraController(camera, ResolutionPreset.high, enableAudio: false);
      _camera = controller;
      await controller.initialize();
      if (_closed || !_active) { await _release(); return; }
      await controller.lockCaptureOrientation(DeviceOrientation.portraitUp);
      AssistantOperationLog.current.success('camera');
      _previewAttached = true;
      _status = '전신이 보이도록 촬영해 주세요.';
    } catch (e) {
      AssistantOperationLog.current.fail('camera', e);
      _error = '카메라를 열 수 없습니다: $e'; await _release();
    } finally { _busy = false; _refresh(); _ensureVoice(); }
  }
  Future<void> _release() async {
    await _detachPreview();
    final c = _camera; _camera = null;
    _refresh();
    await c?.dispose();
  }
  Future<void> _detachPreview() async {
    if (!_previewAttached) return;
    _previewAttached = false;
    _refresh();
    // CameraPreview listens to stopVideoRecording's value change. Remove that
    // listener/widget before stopping/disposal, rather than leaving a dirty
    // preview to call buildPreview() against a released controller.
    if (mounted && !_closed &&
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) {
      await WidgetsBinding.instance.endOfFrame;
    }
    AppErrorLog.record('CAPTURE_STAGE', 'preview_detached');
  }
  void _toggle() {
    if (_busy || _closed || !_active) return;
    _busy = true; _refresh();
    _enqueue(() async {
      try {
        if (_recording) { await _finish(); }
        else {
          await _startRecording();
        }
      } catch (e, stack) {
        AppErrorLog.record('CAPTURE_ERROR', '$e\n$stack');
        // If stopping failed and recording continues, restore its preview.
        _previewAttached = _camera?.value.isInitialized == true;
        AssistantOperationLog.current.fail('recording', e);
        _error = '촬영 처리 실패: $e';
      }
      finally { _busy = false; _refresh(); }
    });
  }
  Future<void> _finish() async {
    final c = _camera;
    if (c == null || !c.value.isRecordingVideo) return;
    _voiceEnabled = false;
    await _voice.invokeMethod('disable');
    await _voice.invokeMethod('tone');
    _status = '촬영을 마무리하는 중…';
    await _detachPreview();
    AppErrorLog.record('CAPTURE_STAGE', 'stopping_recording');
    final file = await c.stopVideoRecording();
    _recording = false; _clock.stop(); _rawVideo = file.path;
    await _release();
    AppErrorLog.record('CAPTURE_STAGE', 'camera_released');
    await _saveToGallery();
  }
  Future<void> _saveToGallery() async {
    if (_rawVideo == null || _savedPath != null) return;
    _status = '갤러리에 저장 중…'; _error = null; _refresh();
    try {
      final result = await _channel.invokeMapMethod<String, dynamic>('saveRecordingToGallery', {'videoPath': _rawVideo});
      final path = result?['path'];
      if (path is! String || path.isEmpty) throw StateError('저장된 영상 경로가 없습니다.');
      AssistantOperationLog.current.success('recording');
      AssistantOperationLog.current.success('save');
      _savedPath = path;
      _status = '저장 완료 · 영상 분석으로 이동합니다.';
      AppErrorLog.record('CAPTURE_STAGE', 'gallery_saved');
      debugPrint('[CAPTURE_GALLERY] saved_uri=${result?['uri']} analysis_path=$path');
      _returnSavedVideo();
    } catch (e, stack) {
      AssistantOperationLog.current.fail('save', e);
      AppErrorLog.record('CAPTURE_SAVE_ERROR', '$e\n$stack');
      _error = '갤러리에 저장하지 못했습니다. 촬영 파일은 유지됩니다.\n$e';
      _status = '저장을 다시 시도해 주세요.';
    }
    _refresh();
  }
  void _returnSavedVideo() {
    if (_savedPath == null || !_active || _closed || !mounted || _returning) return;
    _returning = true;
    // Enable PopScope for this completed capture before returning its saved path.
    setState(() {});
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _active && !_closed) { Navigator.of(context).pop(_savedPath); }
      else { _returning = false; }
    });
  }
  void _retrySave() {
    if (_busy) return;
    _busy = true; _refresh();
    _enqueue(() async {
      try { await _saveToGallery(); } finally { _busy = false; _refresh(); }
    });
  }
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _active = true;
      _enqueue(() async {
        if (_savedPath != null) { _returnSavedVideo(); }
        else if (_rawVideo == null) { await _initialize(); _ensureVoice(); }
      });
    } else if (state == AppLifecycleState.inactive || state == AppLifecycleState.paused) {
      _active = false;
      if (!_voiceChanging) { _voiceEnabled = false; _voice.invokeMethod('disable'); _voiceStatus = '촬영 화면으로 돌아오면 음성 대기를 시작합니다.'; }
      _enqueue(() async {
        _busy = true; _refresh();
        try { if (_recording) await _finish(); }
        finally { await _release(); _busy = false; _refresh(); }
      });
    }
  }
  @override
  void dispose() {
    _voiceEnabled = false; _voice.setMethodCallHandler(null); _voice.invokeMethod('disable');
    _closed = true; _timer?.cancel(); WidgetsBinding.instance.removeObserver(this);
    _enqueue(_release); super.dispose();
  }
  @override
  Widget build(BuildContext context) {
    final c = _camera;
    return PopScope(canPop: _returning || (!_recording && !_busy), child: Scaffold(
      appBar: CoachAppBar(camera: true, situation: _error != null ? AssistantScreenContext.cameraFailure : null, title: Text('스윙 촬영'), automaticallyImplyLeading: !_recording && !_busy, actions: [
        IconButton(tooltip: '설정', icon: const Icon(Icons.settings_outlined),
          onPressed: _recording || _busy || _voiceChanging ? null : _openSettings),
      ]),
      body: SafeArea(child: Padding(padding: EdgeInsets.all(24), child: Column(children: [
        Expanded(child: Center(child: _previewAttached && c != null && c.value.isInitialized ?
          AspectRatio(aspectRatio: 1 / c.value.aspectRatio, child: ClipRRect(
            borderRadius: BorderRadius.circular(20), child: CameraPreview(c))) :
          Icon(_rawVideo != null ? Icons.video_file_outlined : Icons.videocam_outlined,
            size: 72, color: Theme.of(context).colorScheme.primary))),
        SizedBox(height: 12),
        if (_rawVideo == null && _voiceConfigured) ...[
          Text(_recording ? '“종료”라고 말해 주세요.' : '버튼을 누르거나 “시작”이라고 말해 주세요.',
            textAlign: TextAlign.center),
          const SizedBox(height: 8),
          Text(_voiceStatus, style: Theme.of(context).textTheme.bodySmall, textAlign: TextAlign.center),
          if (!_voiceAuto && !_voiceChanging && !_busy)
            TextButton(onPressed: () { _voiceAuto = true; _ensureVoice(); }, child: const Text('음성 인식 다시 연결')),
          const SizedBox(height: 8),
        ],
        Text(_recording ? '${_clock.elapsed.inSeconds} / 30초' : _status, textAlign: TextAlign.center),
        if (_error != null) Padding(padding: EdgeInsets.only(top: 12),
          child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error), textAlign: TextAlign.center)),
        SizedBox(height: 24),
        if (_busy) LinearProgressIndicator()
        else if (_rawVideo != null && _savedPath == null)
          ElevatedButton(onPressed: _retrySave, child: Text('갤러리 저장 다시 시도'))
        else if (_camera == null)
          OutlinedButton(onPressed: () => _enqueue(_initialize), child: Text('카메라 다시 연결'))
        else ElevatedButton.icon(onPressed: c?.value.isInitialized == true ? _toggle : null,
          icon: Icon(_recording ? Icons.stop : Icons.fiber_manual_record),
          label: Text(_recording ? '촬영 마치고 분석' : '촬영 시작')),
        SizedBox(height: 16),
        Text('무음 영상 · 최대 30초 · 촬영 후 저장하고 자동 분석합니다.',
          style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12), textAlign: TextAlign.center),
      ]))),
    ));
  }
}
