import '../services/capture_quality_guidance.dart';
import '../services/assistant_operation_log.dart';
import '../widgets/coach_app_bar.dart';
import '../providers/experience_settings.dart';
import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';
import '../providers/swing_provider.dart';
import '../services/gallery_pose_service.dart';
import '../services/video_orientation_service.dart';
import '../services/impact_detection_service.dart';
import 'analysis_result_screen.dart';

class PoseTrimmingScreen extends StatefulWidget {
  final bool autoAnalyze;
  const PoseTrimmingScreen({super.key, this.autoAnalyze = false});
  @override
  State<PoseTrimmingScreen> createState() => _PoseTrimmingScreenState();
}

class _PoseTrimmingScreenState extends State<PoseTrimmingScreen> {
  bool _automatic = false;
  int _analysisStep = 0, _elapsedSeconds = 0;
  String _analysisStatus = '영상 길이와 저장된 분석 기록을 확인하고 있습니다.';
  Timer? _progressTimer;
  final Stopwatch _analysisWatch = Stopwatch();
  void _updateAnalysis(int step, String message) {
    if (!mounted) return;
    setState(() { _analysisStep = step; _analysisStatus = message; });
  }

  int _reviewPage = 0;
  int _debugReturnPage = 0;
  VideoPlayerController? _player;
  String? _error;
  bool _loadingPose = true;
  String _poseStatus = '저장된 관절 좌표 없음';
  String _path = '';
  int _duration = 0;
  RangeValues _range = RangeValues(0, 1);
  final Map<String, int> _events = {};
  List<Map<String, dynamic>> _samples = [];
  Map<String, dynamic> _impactDebug = {};
  Map<String, dynamic> _selectionDebug = {};
  bool _showImpactOverlay = false;
  int? _visionImpactMs;
  double? _visionImpactConfidence;
  bool _overlay = false, _saving = false, _seeking = false;
  int _offset = 0;
  int _rotationTurns = 0;
  double get _displayAspect => _rotationTurns.isOdd ? 1 / _player!.value.aspectRatio : _player!.value.aspectRatio;
  static const _labels = {
    'address': '어드레스', 'top': '백스윙 탑',
    'impact': '임팩트 후보', 'finish': '피니시',
  };

  @override
  void initState() {
    super.initState();
    _automatic = widget.autoAnalyze;
    _analysisWatch.start();
    _progressTimer = Timer.periodic(Duration(seconds: 1), (_) {
      if (mounted && _error == null && (_loadingPose || _saving)) {
        setState(() => _elapsedSeconds = _analysisWatch.elapsed.inSeconds);
      }
    });
    if (!_automatic) _reviewPage = 6;
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
      _rotationTurns = await VideoOrientationService.read(_path);
      _loadingPose = false;
      await _loadReview();
      if (_events.length < _labels.length) {
        _autoDetectEvents(force: true);
      }
      if (!mounted) return;
      player.addListener(_tick);
      setState(() {});
      if (_automatic) {
        if (_valid) {
          await _save();
        } else {
          AssistantOperationLog.current.note('스윙 시점 탐색', '오류', _selectionDiagnostic);
          setState(() => _error = _selectionHelp);
        }
      }
    } catch (e) {
      _loadingPose = false;
      if (mounted) setState(() => _error = '영상을 열지 못했습니다.\n$e');
    }
  }

  Future<void> _extractPoseFromVideo() async {
    if (_player == null || _duration <= 0) return;
    setState(() => _poseStatus = '온디바이스 관절 스캔 중…');

    final analyzed = await GalleryPoseService.analyzeGalleryVideo(
      videoPath: _path,
      onProgress: (progress, status) {
        if (!mounted) return;
        setState(() { _poseStatus = status; _analysisStep = progress < .8 ? 0 : 1; _analysisStatus = status; });
      },
    );

    if (!analyzed) {
      _samples = [];
      if (mounted) {
        setState(() {
          _poseStatus = '관절 좌표를 추출하지 못했습니다. 자동 후보 시각은 단순 추정값으로 표시됩니다.';
        });
      }
      return;
    }

    await _loadPose(allowRefresh: false);
    if (!mounted) return;
    setState(() {
      final validCount = _samples.where((s) => (s['landmarks'] as List?)?.isNotEmpty == true).length;
      _poseStatus = _samples.isEmpty
          ? '관절 좌표를 읽지 못했습니다. 자동 후보 시각은 단순 추정값으로 표시됩니다.'
          : validCount == 0
              ? '영상 ${_samples.length}개 프레임 분석 완료 · 사람 관절을 검출하지 못했습니다.'
              : '온디바이스 관절 스캔 완료 · $validCount개 프레임 정밀 분석';
    });
  }

  Future<void> _loadPose({bool allowRefresh = true}) async {
    final file = File('$_path.pose.json');
    if (!await file.exists()) {
      if (allowRefresh) await _extractPoseFromVideo();
      return;
    }
    try {
      if (await file.length() > 20 * 1024 * 1024) {
        throw FormatException('관절 기록 파일이 너무 큽니다.');
      }
      final data = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      if (data['source'] != 'mlkit_pose_detection' ||
          data['coordinate_space'] != 'upright_image_pixels') {
        throw FormatException('지원하지 않는 좌표 형식');
      }
      final schemaVersion = data['schema_version'] as String?;
      final savedSampleCount = data['sample_count'] as int?;
      _impactDebug = Map<String, dynamic>.from(data['impact_debug'] as Map? ?? {});
      final visionImpact = data['vision_impact'];
      if (visionImpact is Map<String, dynamic>) {
        final rawMs = visionImpact['t_ms'];
        final rawConfidence = visionImpact['confidence'];
        _visionImpactMs = rawMs is int ? rawMs : null;
        _visionImpactConfidence = rawConfidence is num ? rawConfidence.toDouble() : null;
      } else {
        _visionImpactMs = null;
        _visionImpactConfidence = null;
      }
      final raw = data['samples'] as List;
      if (allowRefresh &&
          (schemaVersion != GalleryPoseService.poseSchemaVersion ||
              (savedSampleCount ?? raw.length) == 0)) {
        setState(() => _poseStatus = '기존 관절 기록이 거칠어서 정밀 분석용으로 다시 스캔 중…');
        await _extractPoseFromVideo();
        return;
      }
      if (raw.length > 20000) throw FormatException('기록 개수 초과');
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
      if (!['manual_video_review', 'user_accepted_selected_events', 'automatic_selected_events'].contains(data['event_source']) || data['duration_ms'] != _duration) return;
      // Recompute older automatic timings: they may be duration-ratio guesses.
      if (data['event_source'] == 'automatic_selected_events' &&
          (data['selection_version'] != 4 || data['selection_source'] == 'unverified_duration_ratio_fallback')) return;
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
      _selectionDebug = {'source': 'saved_manual_review', 'events_ms': Map.of(events)};
    } catch (_) {
      // An invalid or legacy review must never become measured event data.
    }
  }

  void _setEvent(String key, int ms) {
    setState(() {
      _selectionDebug = {..._selectionDebug, 'source': 'manual_edit', 'edited_event': key, 'edited_ms': ms};
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

  double? _averageLandmarkY(List<dynamic> landmarks, Set<String> names) {
    double sumY = 0;
    int count = 0;
    for (final item in landmarks) {
      if (item is Map && names.contains(item['name'])) {
        final y = item['y'];
        if (y is num && y.isFinite) {
          sumY += y.toDouble();
          count++;
        }
      }
    }
    return count == 0 ? null : sumY / count;
  }

  double? _averageLandmarkX(List<dynamic> landmarks, Set<String> names) {
    double sumX = 0;
    int count = 0;
    for (final item in landmarks) {
      if (item is Map && names.contains(item['name'])) {
        final x = item['x'];
        if (x is num && x.isFinite) {
          sumX += x.toDouble();
          count++;
        }
      }
    }
    return count == 0 ? null : sumX / count;
  }

  List<double> _smoothSeries(List<double> values) {
    if (values.length < 3) return List<double>.from(values);
    return List<double>.generate(values.length, (index) {
      final from = index == 0 ? 0 : index - 1;
      final to = index == values.length - 1 ? values.length - 1 : index + 1;
      double sum = 0;
      int count = 0;
      for (int i = from; i <= to; i++) {
        sum += values[i];
        count++;
      }
      return sum / count;
    });
  }

  String get _selectionHelp => '분석할 스윙을 찾지 못했어요.';

  String get _selectionDiagnostic {
    final captureHelp=CaptureQualityGuidance.failureHelp(_samples);
    if(captureHelp!=null) return captureHelp;
    if(_impactDebug['reason']=='multiple_visual_hits') {
      return '타격으로 보이는 스윙이 여러 번 있습니다. 상단 설정에서 분석할 스윙 구간을 골라 주세요.';
    }
    return '실제 타격 구간을 확실히 구분하지 못했습니다. 여러 스윙이 포함됐다면 상단 설정에서 실제 타격 구간을 지정해 주세요. 머리와 손, 공이 화면에 보이는지도 확인해 주세요.';
  }

  void _autoDetectEvents({bool force = false}) {
    if (!force && _events.length == _labels.length) return;
    _events.clear();
    _selectionDebug = {'source': 'running', 'candidates': <Map<String, dynamic>>[]};

    final startMs = _range.start.round().clamp(0, _duration);
    final endMs = _range.end.round().clamp(startMs + 100, _duration);
    _selectionDebug.addAll({'trim_start_ms': startMs, 'trim_end_ms': endMs,
      'vision_candidate_ms': _visionImpactMs, 'vision_status': _impactDebug['status'],
      'vision_reason': _impactDebug['reason']});

    // 실제 유효 관절 레코드(landmarks)가 감지된 샘플 검색
    final validSamples = _samples.where((s) {
      final t = s['t_ms'] as int;
      final landmarks = s['landmarks'] as List?;
      return t >= startMs && t <= endMs && landmarks != null && landmarks.isNotEmpty;
    }).toList();

    if (validSamples.length >= 5) {
      try {
        final wristSamples = <Map<String, dynamic>>[];
        final wristXs = <double>[];
        final wristYs = <double>[];
        for (final sample in validSamples) {
          final landmarks = sample['landmarks'] as List<dynamic>;
          final wristX = _averageLandmarkX(landmarks, const {'leftWrist', 'rightWrist'});
          final wristY = _averageLandmarkY(landmarks, const {'leftWrist', 'rightWrist'});
          if (wristX != null && wristY != null) {
            wristSamples.add(sample);
            wristXs.add(wristX);
            wristYs.add(wristY);
          }
        }

        if (wristSamples.length < 5) {
          throw FormatException('손목 궤적이 부족합니다.');
        }

        final smoothedWristXs = _smoothSeries(wristXs);
        final smoothedWristYs = _smoothSeries(wristYs);

        // Use the same phase validation for display and dense video extraction.
        final savedWindow=_impactDebug['selected_window'];
        final savedInRange=savedWindow is Map && savedWindow['address_ms'] is int &&
          savedWindow['address_ms']>=startMs && savedWindow['end_ms']<=endMs;
        final localWindows=ImpactDetectionService.scanWindows(wristSamples);
        // A range explicitly narrowed by the user may isolate one cycle. For
        // a full automatic scan, never substitute the first practice swing.
        final phase=savedInRange ? Map<String,int>.from(savedWindow as Map) :
          (_impactDebug['selection_basis']=='ambiguous_multiple_swings' &&
            startMs==0 && endMs==_duration ? null :
            (localWindows.length==1 ? localWindows.single : null));
        if(phase==null) {
          _selectionDebug.addAll({'source':'no_valid_backswing_return',
            'reason':'백스윙 후 하강 동작을 확인하지 못했습니다.'});
          debugPrint('[IMPACT_SELECTION] ${jsonEncode(_selectionDebug)}');
          return;
        }
        final addressIndex=wristSamples.indexWhere((s)=>s['t_ms']==phase['address_ms']);
        final topIndex=wristSamples.indexWhere((s)=>s['t_ms']==phase['top_ms']);
        if(addressIndex<0||topIndex<0)return;

        // 3. 임팩트 탐지:
        // 임팩트는 "가장 닮은 자세"보다
        // 탑 이후 손목 중심이 어드레스 손 위치 근처로 처음 다시 들어오는 시점에 더 가깝다.
        final addressY = smoothedWristYs[addressIndex];
        final addressX = smoothedWristXs[addressIndex];
        final topY = smoothedWristYs[topIndex];
        final swingAmplitude = (addressY - topY).abs();
        if (swingAmplitude < 1) {
          throw FormatException('스윙 진폭이 너무 작습니다.');
        }
        final topMs = (wristSamples[topIndex]['t_ms'] as int) - _offset;
        final visionImpactMs = _visionImpactMs;
        final canUseVisionImpact = visionImpactMs != null &&
            visionImpactMs > topMs &&
            visionImpactMs < endMs &&
            visionImpactMs > startMs;
        final impactThresholdY = topY + swingAmplitude * 0.64;
        final int impactSearchStart = (topIndex + 1).clamp(1, smoothedWristYs.length - 2);
        final int impactSearchEnd = wristSamples.lastIndexWhere(
          (s) => (s['t_ms'] as int) <= phase['end_ms']!)
          .clamp(impactSearchStart, wristSamples.length - 2);

        _selectionDebug.addAll({'address_index': addressIndex, 'top_index': topIndex,
          'top_ms': topMs, 'search_start_index': impactSearchStart, 'search_end_index': impactSearchEnd,
          'search_start_ms': wristSamples[impactSearchStart]['t_ms'],
          'search_end_ms': wristSamples[impactSearchEnd]['t_ms'],
          'vision_usable': canUseVisionImpact, 'threshold_y': impactThresholdY,
          'amplitude': swingAmplitude, 'smoothed_wrist_x': smoothedWristXs,
          'smoothed_wrist_y': smoothedWristYs,
          'sample_times_ms': wristSamples.map((s) => s['t_ms']).toList(),
          'source': 'default_top_plus_one_no_eligible_candidate'});
        int impactIndex = impactSearchStart;
        int? firstImpactZoneIndex;
        final addressDistances = List<double>.filled(wristSamples.length, 0);
        for (int i = 0; i < wristSamples.length; i++) {
          final dx = smoothedWristXs[i] - addressX;
          final dy = smoothedWristYs[i] - addressY;
          addressDistances[i] = (dx * dx) + ((dy * 1.15) * (dy * 1.15));
        }

        final topDistance = addressDistances[topIndex];
        if (topDistance < 1) {
          throw FormatException('어드레스와 탑 구분이 약합니다.');
        }
        final reentryDistanceThreshold = topDistance * 0.38;

        for (int i = impactSearchStart; i <= impactSearchEnd; i++) {
          final currentY = smoothedWristYs[i];
          final currentDistance = addressDistances[i];
          if (currentY >= impactThresholdY && currentDistance <= reentryDistanceThreshold) {
            firstImpactZoneIndex = i;
            break;
          }
        }

        _selectionDebug['reentry_distance_threshold'] = reentryDistanceThreshold;
        _selectionDebug['first_reentry_index'] = firstImpactZoneIndex;
        for (int i = impactSearchStart; i <= impactSearchEnd; i++) {
          (_selectionDebug['candidates'] as List).add({'index': i,
            't_ms': wristSamples[i]['t_ms'], 'wrist_y': smoothedWristYs[i],
            'address_distance_squared': addressDistances[i],
            'height_pass': smoothedWristYs[i] >= impactThresholdY,
            'distance_pass': addressDistances[i] <= reentryDistanceThreshold});
        }
        if (canUseVisionImpact) {
          _selectionDebug['source'] = 'dense_ball_departure_and_club_trace';
          final targetMs = visionImpactMs;
          double bestDelta = double.infinity;
          for (int i = impactSearchStart; i <= impactSearchEnd; i++) {
            final sampleMs = (wristSamples[i]['t_ms'] as int) - _offset;
            final delta = (sampleMs - targetMs).abs().toDouble();
            (_selectionDebug['candidates'] as List).cast<Map<String, dynamic>>()
                .firstWhere((row) => row['index'] == i)['vision_delta_ms'] = delta;
            if (delta < bestDelta) {
              bestDelta = delta;
              impactIndex = i;
            }
          }
        } else if (firstImpactZoneIndex != null) {
          _selectionDebug['source'] = 'wrist_reentry_local_score';
          int bestIndex = firstImpactZoneIndex;
          double bestScore = -double.infinity;
          final int localSearchStart = (firstImpactZoneIndex - 1).clamp(impactSearchStart, firstImpactZoneIndex);
          final int localSearchEnd = (firstImpactZoneIndex + 1).clamp(firstImpactZoneIndex, impactSearchEnd);

          for (int i = localSearchStart; i <= localSearchEnd; i++) {
            final currentDistance = addressDistances[i];
            final previousDistance = addressDistances[i - 1];
            final nextDistance = addressDistances[i + 1];
            final currentY = smoothedWristYs[i];
            final velocityIn = (smoothedWristXs[i] - smoothedWristXs[i - 1]).abs() +
                (smoothedWristYs[i] - smoothedWristYs[i - 1]).abs();
            final stillApproachingAddress = currentDistance <= previousDistance || currentDistance <= nextDistance;
            final closenessScore = 1.0 - (currentDistance / topDistance).clamp(0.0, 1.0);
            final heightScore = ((currentY - impactThresholdY) / swingAmplitude).clamp(0.0, 1.0);
            final earlyBias = i == localSearchStart ? 1.0 : 0.0;
            final score = (closenessScore * 22) + (heightScore * 8) + (velocityIn * 0.08) +
                (stillApproachingAddress ? 4.0 : 0.0) + earlyBias;
            (_selectionDebug['candidates'] as List).cast<Map<String, dynamic>>()
                .firstWhere((row) => row['index'] == i).addAll({
                  'local_score': score, 'closeness_score': closenessScore,
                  'height_score': heightScore, 'velocity_pixels_per_sample': velocityIn,
                  'early_bias': earlyBias});
            if (score > bestScore) {
              bestScore = score;
              bestIndex = i;
              _selectionDebug['best_local_score'] = score;
            }
          }

          impactIndex = bestIndex;
        } else {
          double bestScore = -double.infinity;
          for (int i = impactSearchStart; i <= impactSearchEnd; i++) {
            final currentDistance = addressDistances[i];
            final currentY = smoothedWristYs[i];
            if (currentY < impactThresholdY) continue;
            final velocityIn = (smoothedWristXs[i] - smoothedWristXs[i - 1]).abs() +
                (smoothedWristYs[i] - smoothedWristYs[i - 1]).abs();
            final closenessScore = 1.0 - (currentDistance / topDistance).clamp(0.0, 1.0);
            final heightScore = ((currentY - impactThresholdY) / swingAmplitude).clamp(0.0, 1.0);
            final progressPenalty = ((i - impactSearchStart) / (impactSearchEnd - impactSearchStart + 1)).clamp(0.0, 1.0);
            final score = (closenessScore * 20) + (heightScore * 7) + (velocityIn * 0.08) - (progressPenalty * 6);
            (_selectionDebug['candidates'] as List).cast<Map<String, dynamic>>()
                .firstWhere((row) => row['index'] == i).addAll({
                  'fallback_score': score, 'closeness_score': closenessScore,
                  'height_score': heightScore, 'velocity_pixels_per_sample': velocityIn,
                  'progress_penalty': progressPenalty});
            if (score > bestScore) {
              bestScore = score;
              impactIndex = i;
              _selectionDebug['source'] = 'wrist_height_fallback_score';
              AssistantOperationLog.current.note('임팩트 시점', '대체 처리', '손목 높이와 움직임 점수로 임팩트 후보를 추정합니다. 직접적인 공 접촉 검출은 아닙니다.');
              _selectionDebug['best_fallback_score'] = score;
            }
          }
        }

        _selectionDebug['index_before_clamp'] = impactIndex;
        if (impactIndex >= wristSamples.length - 1) {
          impactIndex = wristSamples.length - 2;
        }

        if (impactIndex <= topIndex) {
          impactIndex = (topIndex + 1).clamp(topIndex + 1, wristSamples.length - 2);
        }

        // Bound by the detected downswing, not a fraction of the entire recording.
        final int maxImpactIndex = impactSearchEnd;
        if (impactIndex > maxImpactIndex) {
          impactIndex = maxImpactIndex;
        }

        // 4. 피니시 탐지:
        // 임팩트 이후 후반부에서 움직임이 가장 안정되는 지점을 사용한다.
        final int finishSearchStart = (impactIndex + 1).clamp(impactIndex + 1, wristSamples.length - 1);
        int finishIndex = finishSearchStart;
        double bestFinishScore = double.infinity;
        for (int i = finishSearchStart; i < wristSamples.length; i++) {
          final currentY = smoothedWristYs[i];
          final previousY = smoothedWristYs[i - 1];
          final nextY = i == wristSamples.length - 1 ? currentY : smoothedWristYs[i + 1];
          final motionScore = (currentY - previousY).abs() + (nextY - currentY).abs();
          final lateBonus = (i / wristSamples.length) < 0.78 ? 40.0 : 0.0;
          final score = motionScore + lateBonus;
          if (score < bestFinishScore) {
            bestFinishScore = score;
            finishIndex = i;
          }
        }

        final addressMs = (wristSamples[addressIndex]['t_ms'] as int) - _offset;
        final impactMs = canUseVisionImpact ? visionImpactMs : (wristSamples[impactIndex]['t_ms'] as int) - _offset;
        final finishMs = (wristSamples[finishIndex]['t_ms'] as int) - _offset;

        // 순서 검증 (Address < Top < Impact < Finish)
        if (addressMs < topMs && topMs < impactMs && impactMs <= finishMs) {
          _events['address'] = addressMs.clamp(startMs, endMs);
          _events['top'] = topMs.clamp(startMs, endMs);
          final unsupportedDefault = _selectionDebug['source'] == 'default_top_plus_one_no_eligible_candidate';
          if (!unsupportedDefault) _events['impact'] = impactMs.clamp(startMs, endMs);
          _events['finish'] = finishMs.clamp(startMs, endMs);
          _selectionDebug.addAll({'selected_index': unsupportedDefault ? null : impactIndex,
            'selected_ms': unsupportedDefault ? null : impactMs,
            'discarded_default_ms': unsupportedDefault ? impactMs : null,
            'selected_height_pass': smoothedWristYs[impactIndex] >= impactThresholdY,
            'top_to_impact_ms': impactMs - topMs, 'events_ms': Map.of(_events)});
          debugPrint('[IMPACT_SELECTION] ${jsonEncode(_selectionDebug)}');
          return;
        }
      } catch (error, stack) {
        _selectionDebug.addAll({'error': error.toString(), 'stack': stack.toString()});
      }
    }

    // Missing measurements must never become percentage-based phase timestamps.
    _events.clear();
    AssistantOperationLog.current.note('스윙 시점 탐색', '경고', '관절 기록으로 어드레스와 타격 구간의 순서를 확인하지 못했습니다. 자세 시점 수정 또는 스윙 전체가 담긴 영상이 필요합니다.');
    _selectionDebug.addAll({'source': 'insufficient_phase_evidence',
      'reason': '관절 기록으로 준비 자세와 타격 구간을 확인하지 못했습니다.'});
    debugPrint('[IMPACT_SELECTION] ${jsonEncode(_selectionDebug)}');
  }

  void _smartFocusSwing() {
    if (_duration <= 0) return;

    // 대기 시간을 제외한 스윙 동작 포커스 (약 35%~85% 구역)
    final startMs = (_duration * 0.35).round().clamp(0, _duration - 2000);
    final endMs = (_duration * 0.85).round().clamp(startMs + 2000, _duration);

    setState(() {
      _range = RangeValues(startMs.toDouble(), endMs.toDouble());
      _autoDetectEvents(force: true);
      if (_player != null && _events['top'] != null) {
        _seek(_events['top']!);
      }
    });
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
        (ratio / _displayAspect - 1).abs() > .10) return null;
    return s;
  }

  Future<void> _runSwingAnalysisWithDialog(SwingProvider provider) async {
    var currentStage = 0;
    var currentStatus = '어드레스·백스윙 탑·임팩트·피니시 자세를 준비하고 있습니다.';
    var dialogActive = true;
    void Function(void Function())? refreshDialog;
    final elapsed = Stopwatch()..start();
    Timer? ticker;
    const stages = [
      '핵심 자세별 관절 확인',
      '스윙 연속 움직임 추적',
      '오류 동작 패턴 분석',
      '측정값과 코칭 결과 정리',
    ];

    unawaited(showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          refreshDialog = setDialogState;
          return PopScope(canPop: false, child: AlertDialog(
            backgroundColor: Theme.of(context).colorScheme.surface,
            title: Row(children: [
              Icon(Icons.insights_outlined, color: Theme.of(context).colorScheme.primary),
              SizedBox(width: 8),
              Text('스윙 동작 분석 중', style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontSize: 16, fontWeight: FontWeight.bold)),
            ]),
            content: SingleChildScrollView(child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(currentStatus, style: TextStyle(color: Theme.of(context).colorScheme.primary, fontSize: 13)),
                SizedBox(height: 12),
                LinearProgressIndicator(color: Theme.of(context).colorScheme.primary, backgroundColor: Theme.of(context).dividerColor),
                SizedBox(height: 8),
                Text('경과 시간 ${elapsed.elapsed.inMinutes}분 ${elapsed.elapsed.inSeconds % 60}초',
                  style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12)),
                SizedBox(height: 20),
                for (var index = 0; index < stages.length; index++)
                  Padding(padding: EdgeInsets.symmetric(vertical: 6), child: Row(children: [
                    Icon(index < currentStage ? Icons.check_circle_outline :
                      index == currentStage ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                      color: index <= currentStage ? Theme.of(context).colorScheme.primary : Theme.of(context).colorScheme.onSurfaceVariant,
                      size: 18),
                    SizedBox(width: 10),
                    Expanded(child: Text(stages[index], style: TextStyle(fontSize: 13,
                      color: index <= currentStage ? Theme.of(context).colorScheme.onSurface : Theme.of(context).colorScheme.onSurfaceVariant,
                      fontWeight: index == currentStage ? FontWeight.bold : FontWeight.normal))),
                  ])),
                SizedBox(height: 16),
                Text('스웨이·얼리 스탠드업·배치기·치킨윙·헤드업·캐스팅·오버더탑을 휴대폰에서 확인합니다.',
                  style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12)),
              ],
            )),
          ));
        },
      ),
    ).whenComplete(() { dialogActive = false; ticker?.cancel(); }));
    ticker = Timer.periodic(Duration(seconds: 1), (_) {
      if (mounted && dialogActive) refreshDialog?.call(() {});
    });
    try {
      await provider.runAnalysis(onProgress: (step, message) {
        currentStage = step >= 4 ? 3 : message.contains('검사') ? 2 : (step - 2).clamp(0, stages.length - 1);
        currentStatus = message;
        _updateAnalysis(step, message);
        if (mounted && dialogActive) refreshDialog?.call(() {});
      });
    } finally {
      ticker?.cancel();
      elapsed.stop();
      if (mounted && dialogActive) Navigator.of(context, rootNavigator: true).pop();
      dialogActive = false;
    }
  }

  Future<void> _save() async {
    if (!_valid || _saving || _seeking) return;
    setState(() => _saving = true);
    try {
      await _player!.pause();
      await File('$_path.review.json').writeAsString(jsonEncode({
        'selection_version': 4, 'selection_source': _selectionDebug['source'],
        'schema_version': '1.0', 'event_source': _automatic ? 'automatic_selected_events' : 'user_accepted_selected_events',
        'duration_ms': _duration, 'trim_start_ms': _range.start.round(),
        'trim_end_ms': _range.end.round(), 'events_ms': _events,
        'pose_overlay_offset_ms': _offset, 'pose_video_pts_synchronized': false,
      }), flush: true);
      if (!mounted) return;
      context.read<SwingProvider>().updateVideoReview(durationMs: _duration, eventsMs: _events);
      final provider = context.read<SwingProvider>();
      await _runSwingAnalysisWithDialog(provider);
      if (!mounted) return;
      if (widget.autoAnalyze) {
        Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => AnalysisResultScreen()));
      } else {
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        if (_automatic) { setState(() => _error = '분석을 완료하지 못했습니다. 다시 시도해 주세요.'); }
        else { ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('분석 실패: $e'))); }
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _rerunImpactDebug() async {
    if (_loadingPose || _saving) return;
    setState(() { _loadingPose = true; _impactDebug = {}; _selectionDebug = {}; });
    try {
      await _player?.pause();
      await _extractPoseFromVideo();
      if (!mounted) return;
      _autoDetectEvents(force: true);
    } catch (error) {
      if (mounted) _poseStatus = '재분석 실패: $error';
    } finally {
      if (mounted) setState(() => _loadingPose = false);
    }
  }

  Map<String, dynamic> get _debugReport => {
    'report_version': 'impact-debug-v2',
    'duration_ms': _duration,
    'player_position_ms': _player?.value.position.inMilliseconds,
    'vision_analysis': _impactDebug,
    'ui_selection': _selectionDebug,
    'current_events_ms': Map.of(_events),
    'pose_samples': _samples,
  };

  Widget _impactDebugPanel() => Card(child: ExpansionTile(
    title: Text('임팩트 상세 디버깅 v3'),
    subtitle: Text('선택 경로: ${_selectionDebug['source'] ?? "확인 전"}'),
    childrenPadding: EdgeInsets.all(12),
    expandedCrossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text('작은 공 후보를 연속 추적하고, 탑 이후 공이 움직이는 구간에서 움직이는 클럽 궤적 후보와 공 사이의 거리를 비교합니다. 표시점은 클럽 헤드 중심으로 확정된 좌표가 아닙니다.'),
      Text('영상 분석: ${_impactDebug['status'] ?? "이전 기록 · 재분석 필요"} / ${_impactDebug['reason'] ?? "-"}'),
      Text('후보 구간: ${_impactDebug['interval_start_ms'] ?? "-"}~${_impactDebug['interval_end_ms'] ?? "-"}ms / 클럽 궤적–공 거리: ${_impactDebug['club_ball_distance_px'] ?? "-"}px'),
      Text('영상 분석 탑: ${_impactDebug['top_ms'] ?? "-"}ms / 선택 후보: ${_impactDebug['selected_ms'] ?? "-"}ms'),
      Text('화면 선택 경로: ${_selectionDebug['source']}'),
      Text('탑→임팩트 간격: ${_selectionDebug['top_to_impact_ms'] ?? "-"}ms / 높이 조건 통과: ${_selectionDebug['selected_height_pass'] ?? "-"}'),
      if (_selectionDebug['source'] == 'default_top_plus_one_no_eligible_candidate')
        Text('검출 실패: 조건 통과 후보가 없습니다. 이전 코드가 선택하던 탑 다음 샘플은 제외했습니다. 임팩트는 미지정 상태입니다.', style: TextStyle(color: Theme.of(context).colorScheme.error)),
      if (_impactDebug['error'] != null) Text('오류: ${_impactDebug['error']}'),
      SwitchListTile(contentPadding: EdgeInsets.zero,
        title: Text('공 후보·클럽 궤적 표시'),
        value: _showImpactOverlay,
        onChanged: (v) => setState(() => _showImpactOverlay = v)),
      Wrap(spacing: 8, children: [
        TextButton(onPressed: _loadingPose ? null : _rerunImpactDebug,
          child: Text('상세 로그로 재분석')),
        TextButton(onPressed: () async {
          await Clipboard.setData(ClipboardData(text: JsonEncoder.withIndent('  ').convert(_debugReport)));
          if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('임팩트 상세 로그를 복사했습니다.')));
        }, child: Text('디버그 로그 복사')),
        if (_impactDebug['ball_reference_ms'] is int)
          TextButton(onPressed: () => _seek(_impactDebug['ball_reference_ms'] as int), child: Text('공 후보 기준 프레임 보기')),
      ]),
      SizedBox(height: 240, child: SingleChildScrollView(child: SelectableText(
        JsonEncoder.withIndent('  ').convert({'vision': _impactDebug, 'selection': _selectionDebug}),
        style: TextStyle(fontSize: 11)))),
    ],
  ));

  @override
  void dispose() {
    _progressTimer?.cancel();
    _analysisWatch.stop();
    _player?.removeListener(_tick);
    _player?.dispose();
    super.dispose();
  }

  String _time(num ms) => '${(ms / 1000).toStringAsFixed(3)}초';

  void _goReviewPage(int page) {
    _player?.pause();
    setState(() => _reviewPage = page);
    if (page >= 2 && page <= 5) {
      final time = _events[_labels.keys.elementAt(page - 2)];
      if (time != null) _seek(time);
    }
  }

  Future<bool> _reviewBack() async {
    if (_saving) return false;
    if (_reviewPage == 7) { _goReviewPage(_debugReturnPage); return false; }
    if (_reviewPage >= 2 && _reviewPage <= 5) { _goReviewPage(6); return false; }
    if (_reviewPage == 6) return true;
    if (_reviewPage > 0) { _goReviewPage(6); return false; }
    return true;
  }

  Widget _reviewVideo(VideoPlayerController p, double height) => SizedBox(
    height: height,
    child: Center(child: AspectRatio(aspectRatio: _displayAspect,
      child: ClipRRect(borderRadius: BorderRadius.circular(20), child: Stack(
        fit: StackFit.expand, children: [
          RotatedBox(quarterTurns: _rotationTurns, child: VideoPlayer(p)),
          if (_overlay) IgnorePointer(child: CustomPaint(painter: _PosePainter(_sample))),
          if (_reviewPage == 7 && _showImpactOverlay && _impactDebug['ball_candidate'] is Map)
            IgnorePointer(child: CustomPaint(painter: _ImpactCandidatePainter(
              Map<String, dynamic>.from(_impactDebug['ball_candidate'] as Map),
              _impactDebug['candidates'] as List? ?? [], p.value.position.inMilliseconds))),
        ],
      )),
    )),
  );

  Widget _reviewPlayback(VideoPlayerController p, {bool precise = false}) => Column(children: [
    SizedBox(height: 12),
    Text('${_time(p.value.position.inMilliseconds)} / ${_time(_duration)}',
      style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12)),
    Slider(value: p.value.position.inMilliseconds.clamp(0, _duration).toDouble(),
      max: _duration.toDouble(), onChanged: _seeking || _saving ? null : (v) => _seek(v.round())),
    Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
      IconButton(tooltip: precise ? '이전 프레임' : '1초 이전',
        icon: Icon(Icons.skip_previous_rounded),
        onPressed: _seeking || _saving ? null : () => _seek(p.value.position.inMilliseconds - (precise ? 33 : 1000))),
      IconButton.filled(tooltip: p.value.isPlaying ? '일시정지' : '재생',
        iconSize: 30, icon: Icon(p.value.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded),
        onPressed: _seeking || _saving ? null : () async {
          if (p.value.isPlaying) { await p.pause(); return; }
          if (p.value.position.inMilliseconds >= _range.end || p.value.position.inMilliseconds < _range.start) {
            await _seek(_range.start.round());
          }
          if (mounted) await p.play();
        }),
      IconButton(tooltip: precise ? '다음 프레임' : '1초 이후',
        icon: Icon(Icons.skip_next_rounded),
        onPressed: _seeking || _saving ? null : () => _seek(p.value.position.inMilliseconds + (precise ? 33 : 1000))),
      DropdownButton<double>(value: p.value.playbackSpeed, underline: SizedBox(),
        items: [0.25, 0.5, 1.0].map((v) => DropdownMenuItem(value: v, child: Text('$v×'))).toList(),
        onChanged: _saving ? null : (v) { if (v != null) p.setPlaybackSpeed(v); }),
    ]),
  ]);

  @override
  Widget build(BuildContext context) {
    if (_automatic) {
      return PopScope(canPop: !_saving && !_loadingPose, child: Scaffold(
        appBar: CoachAppBar(situation: _error != null ? AssistantScreenContext.analysisFailure : null, title: Text('스윙 분석'), actions: [
          if (_error != null) IconButton(tooltip: '자세 시점 수정', icon: Icon(Icons.settings_outlined),
            onPressed: () => setState(() { _automatic = false; _error = null; _reviewPage = 6; })),
        ]),
        body: Center(child: Padding(padding: EdgeInsets.all(32),
          child: _error != null ? Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.info_outline, size: 36, color: Theme.of(context).colorScheme.primary),
            SizedBox(height: 16),
            Text('분석을 완료하지 못했어요.', textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleLarge),
            SizedBox(height: 10),
            Text('상단 코치에게 원인과 다음 단계를 물어보세요.', textAlign: TextAlign.center),
            SizedBox(height: 24),
            ElevatedButton(onPressed: () => Navigator.pop(context), child: Text('다른 영상 선택')),
          ]) : SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
            CircularProgressIndicator(), SizedBox(height: 24),
            Text('스윙을 분석하고 있어요', style: Theme.of(context).textTheme.titleLarge),
            SizedBox(height: 12),
            Text(_analysisStatus, textAlign: TextAlign.center, semanticsLabel: '현재 작업: $_analysisStatus'),
            SizedBox(height: 8),
            Text('경과 시간 ${_elapsedSeconds ~/ 60}분 ${_elapsedSeconds % 60}초',
              style: Theme.of(context).textTheme.bodySmall),
            SizedBox(height: 24),
            for (final entry in ['영상 준비 · 관절 인식', '스윙 시점 찾기',
              '어드레스 · 탑 · 임팩트 · 피니시 확인', '자세별 움직임 분석', '결과 정리'].asMap().entries)
              Padding(padding: EdgeInsets.symmetric(vertical: 7), child: Row(children: [
                Icon(entry.key < _analysisStep ? Icons.check_circle_outline :
                  entry.key == _analysisStep ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                  size: 20, color: entry.key <= _analysisStep ? Theme.of(context).colorScheme.primary : Theme.of(context).colorScheme.onSurfaceVariant),
                SizedBox(width: 12),
                Expanded(child: Text(entry.value, style: TextStyle(
                  fontWeight: entry.key == _analysisStep ? FontWeight.bold : FontWeight.normal,
                  color: entry.key > _analysisStep ? Theme.of(context).colorScheme.onSurfaceVariant : null))),
              ])),
            if (_analysisStep == 3) ...[
              SizedBox(height: 16),
              for (final item in const {
                '스웨이': '머리가 타깃 반대쪽으로 이동하는지',
                '얼리 스탠드업': '임팩트 전 상체가 일어서는지',
                '배치기': '골반이 공 쪽으로 이동하는지',
                '치킨윙': '임팩트 이후 앞팔이 굽혀지는지',
                '헤드업': '임팩트 전 머리가 위로 올라가는지',
              }.entries)
                Padding(padding: EdgeInsets.symmetric(vertical: 5), child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Icon(_analysisStatus.contains(item.key) ? Icons.more_horiz : Icons.circle_outlined,
                      size: 18, color: _analysisStatus.contains(item.key)
                        ? Theme.of(context).colorScheme.primary : Theme.of(context).colorScheme.onSurfaceVariant),
                    SizedBox(width: 8),
                    Expanded(child: Text('${item.key} · ${_analysisStatus.contains(item.key) ? "확인 중" : "자료 수집 / 대기"}\n${item.value}',
                      style: Theme.of(context).textTheme.bodySmall)),
                  ])),
            ],
            SizedBox(height: 24),
            Text('인터넷 연결을 기다리는 것이 아니라, 휴대폰에서 영상을 분석하고 있습니다.\n영상 길이에 따라 시간이 걸릴 수 있어요. 화면을 열어 두시면 완료 후 결과를 보여드립니다.',
              textAlign: TextAlign.center),
          ])))),
      ));
    }
    final p = _player;
    final ready = p != null && p.value.isInitialized && _duration > 0;
    final phase = _reviewPage >= 2 && _reviewPage <= 5;
    final key = phase ? _labels.keys.elementAt(_reviewPage - 2) : null;
    final titles = ['영상을 확인하세요', '스윙 구간을 정하세요', '어드레스', '백스윙 탑', '임팩트', '피니시', '분석 시점 수정', '분석 상세'];
    final descriptions = ['자동으로 찾은 스윙으로 분석합니다.', '스윙의 시작부터 끝까지 포함해 주세요.',
      '스윙을 시작하기 전 준비 자세입니다.', '클럽이 올라간 뒤 내려오기 직전입니다.',
      '공을 치는 순간을 앞뒤 프레임으로 확인하세요.', '스윙을 마친 자세를 확인하세요.',
      '시각을 누르면 해당 자세를 다시 확인할 수 있어요.', '관절 기록과 자동 선택 근거를 확인합니다.'];

    final videoHeight = (MediaQuery.of(context).size.height * .36).clamp(180.0, 340.0);
    return PopScope(canPop: (_reviewPage == 0 || _reviewPage == 6) && !_saving,
      onPopInvoked: (didPop) { if (!didPop) _reviewBack(); }, child: Scaffold(
      appBar: CoachAppBar(situation: _error != null ? AssistantScreenContext.analysisFailure : null, title: Text(_reviewPage == 7 ? '분석 상세' : '스윙 확인'),
        leading: IconButton(tooltip: '이전 화면', icon: Icon(Icons.arrow_back), onPressed: () async {
          if (await _reviewBack() && mounted) Navigator.of(context).pop();
        }),
        actions: [IconButton(tooltip: '분석 시점 수정', icon: Icon(Icons.settings_outlined),
          onPressed: _saving || _loadingPose ? null : () => _goReviewPage(6))]),
      bottomNavigationBar: !ready || _error != null || _reviewPage == 7 ? null : SafeArea(
        child: Padding(padding: EdgeInsets.fromLTRB(24, 12, 24, 16),
          child: ElevatedButton(onPressed: _loadingPose || _saving || _seeking ||
            (((_reviewPage == 0 || _reviewPage == 6) && !_valid) || (phase && _events[key] == null)) ? null : () {
              if (_reviewPage == 0 || _reviewPage == 6) {
                _save();
              } else { _goReviewPage(6); }
            }, child: Text(_saving ? '분석 중…' : (_reviewPage == 0 || _reviewPage == 6)
              ? '스윙 분석하기' : '적용하고 돌아가기')))),
      body: _error != null ? Center(child: Padding(padding: EdgeInsets.all(24), child: Text('분석을 완료하지 못했어요.\n상단 코치에게 물어보세요.', textAlign: TextAlign.center))) :
        !ready ? Center(child: CircularProgressIndicator()) : ListView(
          key: ValueKey(_reviewPage), padding: EdgeInsets.fromLTRB(24, 12, 24, 24), children: [
            Text(titles[_reviewPage], style: TextStyle(fontSize: 26, fontWeight: FontWeight.w600)),
            SizedBox(height: 8),
            Text(descriptions[_reviewPage], style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
            SizedBox(height: 24),
            if (_reviewPage != 6) _reviewVideo(p, phase ? videoHeight * .72 : videoHeight),
            if (_reviewPage == 0 && !_loadingPose && !_valid)
              Padding(padding: EdgeInsets.only(top: 16), child: Text(_selectionHelp)),
            if (_loadingPose) ...[SizedBox(height: 16), LinearProgressIndicator(),
              SizedBox(height: 8), Text(_poseStatus)],
            if (_reviewPage == 0 || phase || _reviewPage == 7) _reviewPlayback(p, precise: phase || _reviewPage == 7),
            if (_reviewPage == 1) ...[
              SizedBox(height: 24),
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Text('시작  ${_time(_range.start)}'), Text('끝  ${_time(_range.end)}')]),
              RangeSlider(values: _range, max: _duration.toDouble(),
                labels: RangeLabels(_time(_range.start), _time(_range.end)),
                onChanged: _saving ? null : (v) {
                  if (v.end - v.start < 100) return;
                  p.pause(); setState(() { _range = v; });
                }, onChangeEnd: (v) {
                  setState(() { _autoDetectEvents(force: true); }); _seek(v.start.round());
                }),
              SizedBox(height: 16),
              TextButton.icon(onPressed: _smartFocusSwing, icon: Icon(Icons.auto_awesome_outlined),
                label: Text('스윙 구간 자동 맞추기')),
              SizedBox(height: 16),
              Text('원본 영상은 그대로 유지됩니다.', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12)),
            ],
            if (phase) ...[
              SizedBox(height: 20),
              Text(_events[key] == null ? '자동 후보가 없어요. 영상을 움직여 직접 지정해 주세요.' :
                '선택 시각  ${_time(_events[key]!)}', textAlign: TextAlign.center,
                style: TextStyle(color: _events[key] == null ? Theme.of(context).colorScheme.error : Theme.of(context).colorScheme.onSurfaceVariant)),
              SizedBox(height: 12),
              OutlinedButton(onPressed: p.value.isPlaying || _saving || _seeking ? null :
                () => _setEvent(key!, p.value.position.inMilliseconds), child: Text('현재 프레임으로 지정')),
              if (_events[key] != null) TextButton(onPressed: () => _seek(_events[key]!), child: Text('선택한 순간 보기')),
            ],
            if (_reviewPage == 6) ...[
              TextButton(onPressed: _saving ? null : () => _goReviewPage(1), child: Text('스윙 구간 수정')),

              for (int i = 0; i < _labels.length; i++) ...[
                ListTile(contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)), tileColor: Theme.of(context).colorScheme.surface,
                  title: Text(_labels.values.elementAt(i)),
                  subtitle: Text(_events[_labels.keys.elementAt(i)] == null ? '직접 지정 필요' : _time(_events[_labels.keys.elementAt(i)]!)),
                  trailing: Icon(Icons.chevron_right), onTap: () => _goReviewPage(i + 2)),
                SizedBox(height: 12),
              ],
              if (!_valid) Text('스윙 구간 안에서 어드레스 → 탑 → 임팩트 → 피니시 순서로 지정해 주세요.',
                style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
            if (_reviewPage == 7) ...[
              SizedBox(height: 24), Text(_poseStatus),
              if (_visionImpactConfidence != null) Text('후보 점수: ${(_visionImpactConfidence! * 100).round()} / 100 (확률 아님)'),
              SwitchListTile(contentPadding: EdgeInsets.zero, title: Text('관절 표시'),
                value: _overlay, onChanged: (v) => setState(() => _overlay = v)),
              _impactDebugPanel(),
            ],
          ]),
    ));
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

class _ImpactCandidatePainter extends CustomPainter {
  final Map<String, dynamic> ball;
  final List<dynamic> candidates;
  final int positionMs;
  _ImpactCandidatePainter(this.ball,this.candidates,this.positionMs);
  @override
  void paint(Canvas canvas, Size size) {
    final w = (ball['width'] as num?)?.toDouble() ?? 0;
    final h = (ball['height'] as num?)?.toDouble() ?? 0;
    if (w <= 0 || h <= 0) return;
    // Hide overlays if decoded image and player aspect ratios disagree.
    if (((w / h) / (size.width / size.height) - 1).abs() > 0.1) return;
    final sx = size.width / w, sy = size.height / h;
    final paint = Paint()..color = Colors.yellow..style = PaintingStyle.stroke..strokeWidth = 2;
    final roi = ball['roi'];
    if (roi is Map) {
      canvas.drawRect(Rect.fromLTRB(
        (roi['x_min'] as num) * sx, (roi['y_min'] as num) * sy,
        (roi['x_max'] as num) * sx, (roi['y_max'] as num) * sy), paint);
    }
    Map? row;
    int delta=1<<30;
    for(final c in candidates) {
      if(c is! Map || c['t_ms'] is! int) continue;
      final d=((c['t_ms'] as int)-positionMs).abs();
      if(d<delta) {delta=d;row=c;}
    }
    if(row==null || delta>50) return;
    final bx=(row['ball_x'] as num?)?.toDouble(),by=(row['ball_y'] as num?)?.toDouble();
    if(bx==null || by==null) return;
    final center=Offset(bx*sx,by*sy);
    canvas.drawCircle(center,7,paint);
    final club=row['club_candidate'];
    if(club is Map) {
      final point=Offset((club['x'] as num)*sx,(club['y'] as num)*sy);
      paint.color=Colors.cyanAccent;
      canvas.drawCircle(point,5,paint);canvas.drawLine(center,point,paint);
    }
  }
  @override
  bool shouldRepaint(covariant _ImpactCandidatePainter oldDelegate) => oldDelegate.ball != ball || oldDelegate.positionMs != positionMs;
}
