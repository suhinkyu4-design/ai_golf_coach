import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import '../widgets/golf_widgets.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';
import '../providers/swing_provider.dart';
import '../services/gallery_pose_service.dart';
import '../theme/app_theme.dart';
import 'ocr_input_screen.dart';
import 'analysis_result_screen.dart';

class PoseTrimmingScreen extends StatefulWidget {
  const PoseTrimmingScreen({super.key});
  @override
  State<PoseTrimmingScreen> createState() => _PoseTrimmingScreenState();
}

class _PoseTrimmingScreenState extends State<PoseTrimmingScreen> {
  VideoPlayerController? _player;
  String? _error;
  String _poseStatus = '저장된 관절 좌표 없음';
  String _path = '';
  int _duration = 0;
  RangeValues _range = const RangeValues(0, 1);
  final Map<String, int> _events = {};
  List<Map<String, dynamic>> _samples = [];
  int? _visionImpactMs;
  double? _visionImpactConfidence;
  bool _overlay = false, _saving = false, _seeking = false;
  int _offset = 0;
  static const _labels = {
    'address': '어드레스', 'top': '백스윙 탑',
    'impact': '임팩트 후보', 'finish': '피니시',
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

    final analyzed = await GalleryPoseService.analyzeGalleryVideo(
      videoPath: _path,
      onProgress: (progress, status) {
        if (!mounted) return;
        setState(() => _poseStatus = status);
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
          : '온디바이스 관절 스캔 완료 · $validCount개 프레임 정밀 분석';
    });
  }

  Future<void> _loadPose({bool allowRefresh = true}) async {
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
      final schemaVersion = data['schema_version'] as String?;
      final savedSampleCount = data['sample_count'] as int?;
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
              (savedSampleCount ?? raw.length) < GalleryPoseService.recommendedSampleCount ||
              _visionImpactMs == null)) {
        setState(() => _poseStatus = '기존 관절 기록이 거칠어서 정밀 분석용으로 다시 스캔 중…');
        await _extractPoseFromVideo();
        return;
      }
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
          throw const FormatException('손목 궤적이 부족합니다.');
        }

        final smoothedWristXs = _smoothSeries(wristXs);
        final smoothedWristYs = _smoothSeries(wristYs);

        // 1. 어드레스 탐지: 스윙 전반부(10%~45% 구간) 중 손목 Y가 가장 큰 준비 자세
        int addressIndex = 0;
        double maxAddressWristY = -double.infinity;
        int maxIndexForSearch = (wristSamples.length * 0.45).round().clamp(1, wristSamples.length - 1);

        for (int i = 0; i < maxIndexForSearch; i++) {
          final avgY = smoothedWristYs[i];
          if (avgY > maxAddressWristY) {
            maxAddressWristY = avgY;
            addressIndex = i;
          }
        }

        // 2. 백스윙 탑 탐지: 어드레스 이후 ~ 스윙 80% 구간 사이 손목 Y 위치가 가장 높은(최소 Y) 지점
        int topIndex = addressIndex;
        double minTopWristY = double.infinity;
        int topSearchEndIndex = (wristSamples.length * 0.80).round().clamp(addressIndex + 1, wristSamples.length);

        for (int i = addressIndex; i < topSearchEndIndex; i++) {
          final avgY = smoothedWristYs[i];
          if (avgY < minTopWristY) {
            minTopWristY = avgY;
            topIndex = i;
          }
        }

        // 3. 임팩트 탐지:
        // 임팩트는 "가장 닮은 자세"보다
        // 탑 이후 손목 중심이 어드레스 손 위치 근처로 처음 다시 들어오는 시점에 더 가깝다.
        final addressY = smoothedWristYs[addressIndex];
        final addressX = smoothedWristXs[addressIndex];
        final topY = smoothedWristYs[topIndex];
        final swingAmplitude = (addressY - topY).abs();
        if (swingAmplitude < 1) {
          throw const FormatException('스윙 진폭이 너무 작습니다.');
        }
        final topMs = (wristSamples[topIndex]['t_ms'] as int) - _offset;
        final visionImpactMs = _visionImpactMs;
        final canUseVisionImpact = visionImpactMs != null &&
            visionImpactMs > topMs &&
            visionImpactMs < endMs &&
            visionImpactMs > startMs;
        final impactThresholdY = topY + swingAmplitude * 0.64;
        final int impactSearchStart = (topIndex + 1).clamp(1, smoothedWristYs.length - 2);
        final int impactSearchEnd = (wristSamples.length * 0.78).round().clamp(impactSearchStart + 1, wristSamples.length - 2);

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
          throw const FormatException('어드레스와 탑 구분이 약합니다.');
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

        if (canUseVisionImpact) {
          final targetMs = visionImpactMs!;
          double bestDelta = double.infinity;
          for (int i = impactSearchStart; i <= impactSearchEnd; i++) {
            final sampleMs = (wristSamples[i]['t_ms'] as int) - _offset;
            final delta = (sampleMs - targetMs).abs().toDouble();
            if (delta < bestDelta) {
              bestDelta = delta;
              impactIndex = i;
            }
          }
        } else if (firstImpactZoneIndex != null) {
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
            if (score > bestScore) {
              bestScore = score;
              bestIndex = i;
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
            if (score > bestScore) {
              bestScore = score;
              impactIndex = i;
            }
          }
        }

        if (impactIndex >= wristSamples.length - 1) {
          impactIndex = wristSamples.length - 2;
        }

        if (impactIndex <= topIndex) {
          impactIndex = (topIndex + 1).clamp(topIndex + 1, wristSamples.length - 2);
        }

        // 임팩트가 너무 뒤로 밀리면 자동으로 한 단계 앞당긴다.
        final int maxImpactIndex = (wristSamples.length * 0.80).round().clamp(topIndex + 1, wristSamples.length - 2);
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
        final impactMs = (wristSamples[impactIndex]['t_ms'] as int) - _offset;
        final finishMs = (wristSamples[finishIndex]['t_ms'] as int) - _offset;

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

  Widget _buildTimelineChips(VideoPlayerController p) {
    final startMs = _range.start.round();
    final endMs = _range.end.round();
    final span = endMs - startMs;
    if (span <= 0) return const SizedBox();

    const count = 10;
    final step = span / (count - 1);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('📸 스윙 순간 타임라인 (누르면 즉시 이동)',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppTheme.mint)),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              onPressed: _smartFocusSwing,
              icon: const Icon(Icons.center_focus_strong, size: 14, color: AppTheme.mint),
              label: const Text('스윙 동작 자동 포커스', style: TextStyle(fontSize: 11, color: AppTheme.mint)),
            ),
          ],
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 40,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: count,
            itemBuilder: (context, index) {
              final ms = (startMs + (step * index)).round();
              final isCurrent = (p.value.position.inMilliseconds - ms).abs() < (step / 2);

              return Padding(
                padding: const EdgeInsets.only(right: 6),
                child: ChoiceChip(
                  label: Text('${(ms / 1000).toStringAsFixed(2)}초',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
                      color: isCurrent ? Colors.black : Colors.white70,
                    )),
                  selected: isCurrent,
                  selectedColor: AppTheme.mint,
                  backgroundColor: const Color(0xFF26332C),
                  onSelected: (_) => _seek(ms),
                ),
              );
            },
          ),
        ),
      ],
    );
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
      final provider = context.read<SwingProvider>();
      provider.updateVideoReview(durationMs: _duration, eventsMs: _events);

      if (provider.enableOcrStep) {
        await Navigator.push(context, MaterialPageRoute(builder: (_) => const OcrInputScreen()));
      } else {
        await provider.runAnalysis();
        if (!mounted) return;
        await Navigator.push(context, MaterialPageRoute(builder: (_) => AnalysisResultScreen()));
      }
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
        const GolfStepHeader(step: 2, title: '중요한 순간을 찾아보세요', description: '자동 후보를 먼저 보고, 특히 임팩트는 직접 한 번 확인해 주세요.'),
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
                Text('• 임팩트 후보(Impact candidate): ${_events['impact'] == null ? "미지정" : "${_events['impact']}ms (${_time(_events['impact']!)})"}'),
                if (_visionImpactMs != null)
                  Text('• 클럽/공 기반 임팩트 후보: ${_visionImpactMs}ms (${_time(_visionImpactMs!)})  신뢰도 ${((_visionImpactConfidence ?? 0) * 100).toStringAsFixed(0)}%'),
                Text('• 피니시(Finish) 수치: ${_events['finish'] == null ? "미지정" : "${_events['finish']}ms (${_time(_events['finish']!)})"}'),
              ],
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.orange.withOpacity(0.12),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.orange.withOpacity(0.35)),
          ),
          child: const Text(
            '현재 자동 임팩트는 사람 관절 포즈만으로 추정한 후보입니다. ML Kit 포즈는 클럽 헤드와 공을 직접 검출하지 않아서, 실제 임팩트와 어긋날 수 있습니다. 임팩트는 아래 버튼으로 한 번 확인해 주세요.',
            style: TextStyle(color: Colors.orangeAccent, fontSize: 12, height: 1.45),
          ),
        ),
        const SizedBox(height: 12),
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
        _buildTimelineChips(p),
        const SizedBox(height: 12),
        Wrap(alignment: WrapAlignment.center, spacing: 4, children: [
          TextButton(onPressed: _seeking || _saving ? null : () => _seek(p.value.position.inMilliseconds - 33), child: const Text('−1프레임')),
          TextButton(onPressed: _seeking || _saving ? null : () => _seek(p.value.position.inMilliseconds - 100), child: const Text('−0.1초')),
          IconButton(icon: Icon(p.value.isPlaying ? Icons.pause : Icons.play_arrow),
            onPressed: _seeking || _saving ? null : () async {
              if (p.value.isPlaying) { await p.pause(); return; }
              if (p.value.position.inMilliseconds < _range.start || p.value.position.inMilliseconds >= _range.end) {
                await _seek(_range.start.round());
              }
              if (mounted) await p.play();
            }),
          TextButton(onPressed: _seeking || _saving ? null : () => _seek(p.value.position.inMilliseconds + 100), child: const Text('+0.1초')),
          TextButton(onPressed: _seeking || _saving ? null : () => _seek(p.value.position.inMilliseconds + 33), child: const Text('+1프레임')),
          DropdownButton<double>(value: p.value.playbackSpeed,
            items: [0.25, 0.5, 1.0].map((s) => DropdownMenuItem(value: s, child: Text('${s}x'))).toList(),
            onChanged: (s) { if (s != null) p.setPlaybackSpeed(s); }),
        ]),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFF40534A)),
          ),
          child: Column(
            children: [
              const Text('⚡ 현재 영상 위치로 스윙 구간 원터치 지정',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppTheme.mint)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                alignment: WrapAlignment.center,
                children: [
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF2E3D35),
                      foregroundColor: AppTheme.mint,
                      minimumSize: const Size(100, 40),
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    ),
                    onPressed: p.value.isPlaying || _seeking || _saving ? null : () {
                      _setEvent('address', p.value.position.inMilliseconds);
                    },
                    icon: const Icon(Icons.sports_golf, size: 15),
                    label: const Text('어드레스', style: TextStyle(fontSize: 12)),
                  ),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF2E3D35),
                      foregroundColor: AppTheme.mint,
                      minimumSize: const Size(100, 40),
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    ),
                    onPressed: p.value.isPlaying || _seeking || _saving ? null : () {
                      _setEvent('top', p.value.position.inMilliseconds);
                    },
                    icon: const Icon(Icons.vertical_align_top, size: 15),
                    label: const Text('백스윙 탑', style: TextStyle(fontSize: 12)),
                  ),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF2E3D35),
                      foregroundColor: AppTheme.mint,
                      minimumSize: const Size(100, 40),
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    ),
                    onPressed: p.value.isPlaying || _seeking || _saving ? null : () {
                      _setEvent('impact', p.value.position.inMilliseconds);
                    },
                    icon: const Icon(Icons.flash_on, size: 15),
                    label: const Text('임팩트', style: TextStyle(fontSize: 12)),
                  ),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF2E3D35),
                      foregroundColor: AppTheme.mint,
                      minimumSize: const Size(100, 40),
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    ),
                    onPressed: p.value.isPlaying || _seeking || _saving ? null : () {
                      _setEvent('finish', p.value.position.inMilliseconds);
                    },
                    icon: const Icon(Icons.flag, size: 15),
                    label: const Text('피니시', style: TextStyle(fontSize: 12)),
                  ),
                ],
              ),
            ],
          ),
        ),
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
                      '⚡ 스윙 4단계 구간이 자동 추정되었습니다. 임팩트는 후보값으로 보고 확인해 주세요.',
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
        ElevatedButton(
          onPressed: _valid && !_saving && !_seeking ? _save : null,
          child: Text(
            _saving
                ? '분석 리포트 생성 중…'
                : (context.watch<SwingProvider>().enableOcrStep
                    ? '다음: 스크린 샷 OCR 연동 →'
                    : 'AI 스윙 분석 결과 확인   →'),
          ),
        ),
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
