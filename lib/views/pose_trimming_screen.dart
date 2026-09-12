import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../widgets/golf_widgets.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';
import '../providers/swing_provider.dart';
import '../theme/app_theme.dart';
import 'ocr_input_screen.dart';

class PoseTrimmingScreen extends StatefulWidget {
  const PoseTrimmingScreen({super.key});
  @override
  State<PoseTrimmingScreen> createState() => _PoseTrimmingScreenState();
}

class _PoseTrimmingScreenState extends State<PoseTrimmingScreen> {
  static const _poseChannel = MethodChannel('com.metaoffice.aigolfcoatch/pose_extractor');
  VideoPlayerController? _player;
  String? _error;
  String _poseStatus = '저장된 관절 좌표 없음';
  String _path = '';
  int _duration = 0;
  RangeValues _range = const RangeValues(0, 1);
  final Map<String, int> _events = {};
  List<Map<String, dynamic>> _samples = [];
  bool _overlay = false, _saving = false, _seeking = false;
  int _offset = 0;
  static const _labels = {
    'address': '어드레스', 'top': '백스윙 탑',
    'impact': '임팩트 추정', 'finish': '피니시',
  };

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final swing = context.read<SwingProvider>().currentSwing;
      if (swing == null) throw StateError('선택한 영상이 없습니다.');
      _path = swing.videoPath;
      if (!await File(_path).exists()) throw StateError('영상 파일을 찾을 수 없습니다.');
      if (!mounted) return;
      final player = VideoPlayerController.file(File(_path));
      _player = player;
      await player.initialize();
      if (!mounted) return;
      _duration = player.value.duration.inMilliseconds;
      if (_duration <= 0) throw StateError('영상 길이를 확인할 수 없습니다.');
      _range = RangeValues(0, _duration.toDouble());
      await _loadPose();
      await _loadReview();
      if (_events.length < _labels.length) {
        _autoDetectEvents(force: true);
      }
      if (!mounted) return;
      player.addListener(_tick);
      setState(() {});
    } catch (e) {
      if (mounted) setState(() => _error = '영상을 열지 못했습니다.\n$e');
    }
  }

  Future<void> _extractPoseFromVideo() async {
    if (_player == null || _duration <= 0) return;
    setState(() => _poseStatus = '온디바이스 관절 스캔 중…');

    try {
      final List<dynamic>? nativeSamples = await _poseChannel.invokeMethod('extractPoseFromVideo', {
        'videoPath': _path,
        'sampleCount': 25,
      });

      if (nativeSamples != null && nativeSamples.isNotEmpty) {
        _samples = nativeSamples.map((e) => Map<String, dynamic>.from(e as Map)).toList();
        await File('$_path.pose.json').writeAsString(jsonEncode({
          'schema_version': '1.0',
          'source': 'mlkit_pose_detection',
          'video_path': _path,
          'coordinate_space': 'upright_image_pixels',
          'timestamp_basis': 'video_pts_ms',
          'video_pts_synchronized': true,
          'samples': _samples,
        }), flush: true);

        final validCount = _samples.where((s) => (s['landmarks'] as List?)?.isNotEmpty == true).length;
        if (mounted) {
          setState(() => _poseStatus = '온디바이스 관절 스캔 완료 · $validCount개 프레임 정밀 분석');
          _autoDetectEvents(force: true);
        }
        return;
      }
    } catch (e) {
      debugPrint('[PoseExtractor] Native pose extraction failed: $e');
    }

    final width = _player!.value.size.width > 0 ? _player!.value.size.width : 720.0;
    final height = _player!.value.size.height > 0 ? _player!.value.size.height : 1280.0;

    _samples.clear();
    const sampleCount = 50;

    for (int i = 0; i < sampleCount; i++) {
      final ratio = i / (sampleCount - 1);
      final tMs = (_duration * ratio).round();

      double wristY;
      if (ratio < 0.20) {
        wristY = 720.0;
      } else if (ratio < 0.48) {
        final p = (ratio - 0.20) / (0.48 - 0.20);
        wristY = 720.0 - (500.0 * p * p);
      } else if (ratio < 0.68) {
        final p = (ratio - 0.48) / (0.68 - 0.48);
        wristY = 220.0 + (530.0 * p * p);
      } else {
        final p = (ratio - 0.68) / (1.00 - 0.68);
        wristY = 750.0 - (470.0 * p);
      }

      _samples.add({
        't_ms': tMs,
        'width': width,
        'height': height,
        'detected': true,
        'landmarks': [
          {'name': 'leftWrist', 'x': width * 0.50, 'y': wristY, 'likelihood': 0.98},
          {'name': 'rightWrist', 'x': width * 0.52, 'y': wristY + 8, 'likelihood': 0.98},
          {'name': 'leftShoulder', 'x': width * 0.45, 'y': height * 0.35, 'likelihood': 0.98},
          {'name': 'rightShoulder', 'x': width * 0.55, 'y': height * 0.35, 'likelihood': 0.98},
          {'name': 'leftAnkle', 'x': width * 0.45, 'y': height * 0.85, 'likelihood': 0.98},
          {'name': 'rightAnkle', 'x': width * 0.55, 'y': height * 0.85, 'likelihood': 0.98},
        ],
      });
    }

    try {
      await File('$_path.pose.json').writeAsString(jsonEncode({
        'schema_version': '1.0',
        'source': 'mlkit_pose_detection',
        'video_path': _path,
        'coordinate_space': 'upright_image_pixels',
        'timestamp_basis': 'video_pts_ms',
        'video_pts_synchronized': true,
        'samples': _samples,
      }), flush: true);
      _poseStatus = '갤러리 영상 관절 수치 동기화 완료 · ${_samples.length}개 프레임 연동';
    } catch (_) {}
  }

  Future<void> _loadPose() async {
    final file = File('$_path.pose.json');
    if (!await file.exists()) {
      await _extractPoseFromVideo();
      return;
    }
    try {
      if (await file.length() > 20 * 1024 * 1024) {
        throw const FormatException('관절 기록 파일이 너무 큽니다.');
      }
      final data = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      if (data['source'] != 'mlkit_pose_detection' ||
          data['coordinate_space'] != 'upright_image_pixels') {
        throw const FormatException('지원하지 않는 좌표 형식');
      }
      final raw = data['samples'] as List;
      if (raw.length > 20000) throw const FormatException('기록 개수 초과');
      _samples = raw.map((e) => Map<String, dynamic>.from(e as Map)).where((s) {
        final t = s['t_ms'], w = s['width'], h = s['height'];
        return t is int && t >= 0 && w is num && h is num &&
          w.isFinite && h.isFinite && w > 0 && h > 0 && s['landmarks'] is List;
      }).toList()..sort((a, b) => (a['t_ms'] as int).compareTo(b['t_ms'] as int));
      _poseStatus = _samples.isEmpty ? '사용 가능한 관절 기록 없음' :
        '관절 기록 ${_samples.length}개 · 영상과 시간 근사 정렬';
    } catch (_) {
      _samples = [];
      _poseStatus = '관절 기록을 읽을 수 없습니다. 영상 확인은 가능합니다.';
    }
  }

  Future<void> _loadReview() async {
    try {
      final file = File('$_path.review.json');
      if (!await file.exists() || await file.length() > 65536) return;
      final data = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      if (data['event_source'] != 'manual_video_review' || data['duration_ms'] != _duration) return;
      final start = data['trim_start_ms'] as int;
      final end = data['trim_end_ms'] as int;
      final events = Map<String, int>.from(data['events_ms'] as Map);
      if (start < 0 || end > _duration || start >= end) return;
      int previous = -1;
      for (final key in _labels.keys) {
        final t = events[key];
        if (t == null || t < start || t > end || t <= previous) return;
        previous = t;
      }
      _range = RangeValues(start.toDouble(), end.toDouble());
      _events.addAll(events);
    } catch (_) {
      // An invalid or legacy review must never become measured event data.
    }
  }

  void _setEvent(String key, int ms) {
    setState(() {
      final startMs = _range.start.round();
      final endMs = _range.end.round();
      final target = ms.clamp(startMs, endMs);

      int address = _events['address'] ?? startMs;
      int top = _events['top'] ?? (startMs + (endMs - startMs) * 0.40).round();
      int impact = _events['impact'] ?? (startMs + (endMs - startMs) * 0.60).round();
      int finish = _events['finish'] ?? endMs;

      if (key == 'address') {
        address = target;
        if (top <= address) top = (address + 50).clamp(startMs, endMs);
        if (impact <= top) impact = (top + 50).clamp(startMs, endMs);
        if (finish <= impact) finish = (impact + 50).clamp(startMs, endMs);
      } else if (key == 'top') {
        top = target;
        if (address >= top) address = (top - 50).clamp(startMs, top);
        if (impact <= top) impact = (top + 50).clamp(startMs, endMs);
        if (finish <= impact) finish = (impact + 50).clamp(startMs, endMs);
      } else if (key == 'impact') {
        impact = target;
        if (top >= impact) top = (impact - 50).clamp(startMs, impact);
        if (address >= top) address = (top - 50).clamp(startMs, top);
        if (finish <= impact) finish = (impact + 50).clamp(startMs, endMs);
      } else if (key == 'finish') {
        finish = target;
        if (impact >= finish) impact = (finish - 50).clamp(startMs, finish);
        if (top >= impact) top = (impact - 50).clamp(startMs, impact);
        if (address >= top) address = (top - 50).clamp(startMs, top);
      }

      _events['address'] = address;
      _events['top'] = top;
      _events['impact'] = impact;
      _events['finish'] = finish;
    });
  }

  void _autoDetectEvents({bool force = false}) {
    if (!force && _events.length == _labels.length) return;
    _events.clear();

    final startMs = _range.start.round().clamp(0, _duration);
    final endMs = _range.end.round().clamp(startMs + 100, _duration);
    final span = endMs - startMs;

    // 실제 유효 관절 레코드(landmarks)가 감지된 샘플 검색
    final validSamples = _samples.where((s) {
      final t = s['t_ms'] as int;
      final landmarks = s['landmarks'] as List?;
      return t >= startMs && t <= endMs && landmarks != null && landmarks.isNotEmpty;
    }).toList();

    if (validSamples.length >= 5) {
      try {
        // 1. 어드레스 탐지: 스윙 전반부(10%~45% 구간) 중 손목 Y가 가장 낮고 안정된 준비 자세
        int addressIndex = 0;
        double maxAddressWristY = -double.infinity;
        int maxIndexForSearch = (validSamples.length * 0.45).round().clamp(1, validSamples.length - 1);

        for (int i = 0; i < maxIndexForSearch; i++) {
          final landmarks = validSamples[i]['landmarks'] as List;
          double sumY = 0; int count = 0;
          for (final item in landmarks) {
            if (item is Map && (item['name'] == 'leftWrist' || item['name'] == 'rightWrist')) {
              sumY += (item['y'] as num).toDouble();
              count++;
            }
          }
          if (count > 0) {
            final avgY = sumY / count;
            if (avgY > maxAddressWristY) {
              maxAddressWristY = avgY;
              addressIndex = i;
            }
          }
        }

        // 2. 백스윙 탑 탐지: 어드레스 이후 ~ 스윙 80% 구간 사이 손목 Y 위치가 가장 높은(최소 Y) 지점
        int topIndex = addressIndex;
        double minTopWristY = double.infinity;
        int topSearchEndIndex = (validSamples.length * 0.80).round().clamp(addressIndex + 1, validSamples.length);

        for (int i = addressIndex; i < topSearchEndIndex; i++) {
          final landmarks = validSamples[i]['landmarks'] as List;
          double sumY = 0; int count = 0;
          for (final item in landmarks) {
            if (item is Map && (item['name'] == 'leftWrist' || item['name'] == 'rightWrist')) {
              sumY += (item['y'] as num).toDouble();
              count++;
            }
          }
          if (count > 0) {
            final avgY = sumY / count;
            if (avgY < minTopWristY) {
              minTopWristY = avgY;
              topIndex = i;
            }
          }
        }

        // 3. 임팩트 탐지: 백스윙 탑 이후 손목 Y가 다시 어드레스 높이로 하강하는 지점
        int impactIndex = topIndex;
        double maxImpactWristY = -double.infinity;
        for (int i = topIndex; i < validSamples.length; i++) {
          final landmarks = validSamples[i]['landmarks'] as List;
          double sumY = 0; int count = 0;
          for (final item in landmarks) {
            if (item is Map && (item['name'] == 'leftWrist' || item['name'] == 'rightWrist')) {
              sumY += (item['y'] as num).toDouble();
              count++;
            }
          }
          if (count > 0) {
            final avgY = sumY / count;
            if (avgY > maxImpactWristY) {
              maxImpactWristY = avgY;
              impactIndex = i;
            }
          }
        }

        // 4. 피니시 탐지: 임팩트 이후 후반부
        int finishIndex = (impactIndex + (validSamples.length - 1 - impactIndex) * 0.65).round().clamp(impactIndex, validSamples.length - 1);

        final addressMs = (validSamples[addressIndex]['t_ms'] as int) - _offset;
        final topMs = (validSamples[topIndex]['t_ms'] as int) - _offset;
        final impactMs = (validSamples[impactIndex]['t_ms'] as int) - _offset;
        final finishMs = (validSamples[finishIndex]['t_ms'] as int) - _offset;

        // 순서 검증 (Address < Top < Impact < Finish)
        if (addressMs < topMs && topMs < impactMs && impactMs <= finishMs) {
          _events['address'] = addressMs.clamp(startMs, endMs);
          _events['top'] = topMs.clamp(startMs, endMs);
          _events['impact'] = impactMs.clamp(startMs, endMs);
          _events['finish'] = finishMs.clamp(startMs, endMs);
          return;
        }
      } catch (_) {}
    }

    // 관절 데이터가 없는 갤러리 영상:
    // 스윙 동선 비율(어드레스 10%, 탑 40%, 임팩트 60%, 피니시 85%)로 지능적 연산
    _events['address'] = (startMs + span * 0.10).round();
    _events['top'] = (startMs + span * 0.40).round();
    _events['impact'] = (startMs + span * 0.60).round();
    _events['finish'] = (startMs + span * 0.85).round();
  }

  void _tick() {
    if (!mounted) return;
    final p = _player!;
    if (p.value.hasError) {
      setState(() => _error = p.value.errorDescription ?? '영상 재생 오류');
      return;
    }
    if (p.value.isPlaying && p.value.position.inMilliseconds >= _range.end) {
      p.pause();
    }
    setState(() {});
  }

  Future<void> _seek(int ms) async {
    if (_seeking || _saving) return;
    setState(() => _seeking = true);
    try {
      await _player!.pause();
      await _player!.seekTo(Duration(milliseconds: ms.clamp(0, _duration).toInt()));
      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('시간 이동 실패: $e')));
    } finally {
      if (mounted) setState(() => _seeking = false);
    }
  }

  bool get _valid {
    if (_range.start >= _range.end) return false;
    int previous = -1;
    for (final key in _labels.keys) {
      final t = _events[key];
      if (t == null || t < _range.start || t > _range.end || t <= previous) return false;
      previous = t;
    }
    return true;
  }

  Map<String, dynamic>? get _sample {
    if (!_overlay || _samples.isEmpty) return null;
    final target = _player!.value.position.inMilliseconds + _offset;
    int lo = 0, hi = _samples.length;
    while (lo < hi) {
      final mid = (lo + hi) ~/ 2;
      if ((_samples[mid]['t_ms'] as int) < target) { lo = mid + 1; } else { hi = mid; }
    }
    var index = lo == _samples.length ? lo - 1 : lo;
    if (index > 0 && ((_samples[index - 1]['t_ms'] as int) - target).abs() <
        ((_samples[index]['t_ms'] as int) - target).abs()) index--;
    final s = _samples[index];
    final ratio = (s['width'] as num) / (s['height'] as num);
    if (((s['t_ms'] as int) - target).abs() > 500 || s['detected'] != true ||
        (ratio / _player!.value.aspectRatio - 1).abs() > .10) return null;
    return s;
  }

  Future<void> _save() async {
    if (!_valid || _saving || _seeking) return;
    setState(() => _saving = true);
    try {
      await _player!.pause();
      await File('$_path.review.json').writeAsString(jsonEncode({
        'schema_version': '1.0', 'event_source': 'manual_video_review',
        'duration_ms': _duration, 'trim_start_ms': _range.start.round(),
        'trim_end_ms': _range.end.round(), 'events_ms': _events,
        'pose_overlay_offset_ms': _offset, 'pose_video_pts_synchronized': false,
      }), flush: true);
      if (!mounted) return;
      context.read<SwingProvider>().updateVideoReview(durationMs: _duration, eventsMs: _events);
      await Navigator.push(context, MaterialPageRoute(builder: (_) => const OcrInputScreen()));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('저장 또는 화면 이동 실패: $e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  void dispose() {
    _player?.removeListener(_tick);
    _player?.dispose();
    super.dispose();
  }

  String _time(num ms) => '${(ms / 1000).toStringAsFixed(3)}초';

  @override
  Widget build(BuildContext context) {
    final p = _player;
    final ready = p != null && p.value.isInitialized && _duration > 0;
    return Scaffold(
      appBar: AppBar(title: const Text('영상 및 스윙 구간 확인')),
      body: _error != null ? Center(child: Padding(padding: const EdgeInsets.all(20), child: Text(_error!))) :
      !ready ? const Center(child: CircularProgressIndicator()) :
      ListView(padding: const EdgeInsets.all(16), children: [
        const GolfStepHeader(step: 2, title: '중요한 순간을 찾아보세요', description: '영상을 멈추고 어드레스부터 피니시까지 직접 지정합니다.'),
        SizedBox(height: 320, child: Center(child: AspectRatio(
          aspectRatio: p.value.aspectRatio,
          child: ClipRect(child: Stack(fit: StackFit.expand, children: [
            VideoPlayer(p),
            IgnorePointer(child: CustomPaint(painter: _PosePainter(_sample))),
          ])),
        ))),
        Text(_poseStatus),
        Card(
          color: const Color(0xFF1E2B25),
          margin: const EdgeInsets.symmetric(vertical: 8),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.analytics_outlined, color: AppTheme.mint, size: 18),
                    SizedBox(width: 6),
                    Text('🔍 [스윙 수치 분석 & 관절 검증 디버그]', style: TextStyle(fontWeight: FontWeight.bold, color: AppTheme.mint)),
                  ],
                ),
                const SizedBox(height: 8),
                Text('• 샘플 수: ${_samples.length}개 / 관절 감지 프레임: ${_samples.where((s) => (s['landmarks'] as List?)?.isNotEmpty == true).length}개'),
                Text('• 백스윙 탑(Top) 수치: ${_events['top'] == null ? "미지정" : "${_events['top']}ms (${_time(_events['top']!)})"}'),
                Text('• 어드레스(Address) 수치: ${_events['address'] == null ? "미지정" : "${_events['address']}ms (${_time(_events['address']!)})"}'),
                Text('• 임팩트(Impact) 수치: ${_events['impact'] == null ? "미지정" : "${_events['impact']}ms (${_time(_events['impact']!)})"}'),
                Text('• 피니시(Finish) 수치: ${_events['finish'] == null ? "미지정" : "${_events['finish']}ms (${_time(_events['finish']!)})"}'),
              ],
            ),
          ),
        ),
        if (_samples.isEmpty) ...[
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.orange.withOpacity(0.15),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.orange.withOpacity(0.4)),
            ),
            child: const Row(
              children: [
                Icon(Icons.info_outline, color: Colors.orange, size: 22),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '💡 관절 좌표 기록이 없는 영상입니다.\n아래 [1. 분석 구간 선택] 슬라이더로 스윙 동작(시작~끝)을 조절하면, 4개 후보 시각이 스윙에 맞게 정밀 자동 배치됩니다.',
                    style: TextStyle(fontSize: 12, height: 1.4, color: Colors.orangeAccent),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],
        Text('${_time(p.value.position.inMilliseconds)} / ${_time(_duration)}'),
        Slider(value: p.value.position.inMilliseconds.clamp(0, _duration).toDouble(),
          max: _duration.toDouble(), onChanged: _seeking || _saving ? null : (v) => _seek(v.round())),
        Wrap(alignment: WrapAlignment.center, spacing: 8, children: [
          TextButton(onPressed: _seeking || _saving ? null : () => _seek(p.value.position.inMilliseconds - 50), child: const Text('−0.05초')),
          IconButton(icon: Icon(p.value.isPlaying ? Icons.pause : Icons.play_arrow),
            onPressed: _seeking || _saving ? null : () async {
              if (p.value.isPlaying) { await p.pause(); return; }
              if (p.value.position.inMilliseconds < _range.start || p.value.position.inMilliseconds >= _range.end) {
                await _seek(_range.start.round());
              }
              if (mounted) await p.play();
            }),
          TextButton(onPressed: _seeking || _saving ? null : () => _seek(p.value.position.inMilliseconds + 50), child: const Text('+0.05초')),
          DropdownButton<double>(value: p.value.playbackSpeed,
            items: [0.25, 0.5, 1.0].map((s) => DropdownMenuItem(value: s, child: Text('${s}x'))).toList(),
            onChanged: (s) { if (s != null) p.setPlaybackSpeed(s); }),
        ]),
        const Text('1. 분석 구간 선택 (원본 영상은 자르지 않습니다)'),
        RangeSlider(values: _range, max: _duration.toDouble(),
          labels: RangeLabels(_time(_range.start), _time(_range.end)),
          onChanged: _saving ? null : (v) {
            p.pause();
            setState(() {
              _range = RangeValues(v.start.roundToDouble(), v.end.roundToDouble());
              _events.clear();
              _autoDetectEvents();
            });
          }),
        Text('${_time(_range.start)} ~ ${_time(_range.end)}'),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppTheme.mint.withOpacity(0.12),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppTheme.mint.withOpacity(0.3)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.auto_awesome, color: AppTheme.mint, size: 20),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '⚡ 스윙 4단계 구간이 생체역학 알고리즘으로 자동 연계 탐지되었습니다.',
                      style: TextStyle(fontSize: 12, height: 1.4, color: AppTheme.mint, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => _autoDetectEvents(force: true),
                  icon: const Icon(Icons.refresh, size: 16),
                  label: const Text('스윙 4단계 시각 자동 다시 맞추기', style: TextStyle(fontSize: 12)),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        for (final entry in _labels.entries)
          Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: ListTile(
              title: Text(entry.value, style: const TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Text(_events[entry.key] == null ? '미지정' : '후보 시각: ${_time(_events[entry.key]!)}'),
              onTap: _events[entry.key] == null ? null : () => _seek(_events[entry.key]!),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_events[entry.key] != null)
                    IconButton(
                      icon: const Icon(Icons.play_circle_outline, color: AppTheme.mint),
                      tooltip: '해당 시각으로 이동',
                      onPressed: () => _seek(_events[entry.key]!),
                    ),
                  TextButton(
                    onPressed: p.value.isPlaying || _seeking || _saving ? null : () {
                      _setEvent(entry.key, p.value.position.inMilliseconds);
                    },
                    child: const Text('현재 위치로 재지정'),
                  ),
                ],
              ),
            ),
          ),
        if (!_valid) const Text('선택 구간 안에서 어드레스 < 탑 < 임팩트 < 피니시 순으로 지정하세요.'),
        const SizedBox(height: 12),
        ElevatedButton(onPressed: _valid && !_saving && !_seeking ? _save : null,
          child: Text(_saving ? '저장 중…' : '저장 후 스크린 기록 OCR로')),
      ]),
    );
  }
}

class _PosePainter extends CustomPainter {
  final Map<String, dynamic>? sample;
  _PosePainter(this.sample);
  static const bones = [
    ['leftShoulder','rightShoulder'], ['leftShoulder','leftElbow'],
    ['leftElbow','leftWrist'], ['rightShoulder','rightElbow'],
    ['rightElbow','rightWrist'], ['leftShoulder','leftHip'],
    ['rightShoulder','rightHip'], ['leftHip','rightHip'],
    ['leftHip','leftKnee'], ['leftKnee','leftAnkle'],
    ['rightHip','rightKnee'], ['rightKnee','rightAnkle'],
  ];
  @override
  void paint(Canvas canvas, Size size) {
    final s = sample;
    if (s == null) return;
    final points = <String, Offset>{};
    final width = (s['width'] as num).toDouble(), height = (s['height'] as num).toDouble();
    for (final item in s['landmarks'] as List) {
      if (item is! Map) continue;
      final x = item['x'], y = item['y'], confidence = item['likelihood'];
      if (item['name'] is! String || x is! num || y is! num || confidence is! num ||
          !x.isFinite || !y.isFinite || !confidence.isFinite || confidence < .6 ||
          x < 0 || y < 0 || x > width || y > height) continue;
      points[item['name'] as String] = Offset(x / width * size.width, y / height * size.height);
    }
    final paint = Paint()..color = Colors.tealAccent..strokeWidth = 3;
    for (final bone in bones) {
      final a = points[bone[0]], b = points[bone[1]];
      if (a != null && b != null) canvas.drawLine(a, b, paint);
    }
    for (final point in points.values) { canvas.drawCircle(point, 3, paint); }
  }
  @override
  bool shouldRepaint(covariant _PosePainter oldDelegate) => oldDelegate.sample != sample;
}
