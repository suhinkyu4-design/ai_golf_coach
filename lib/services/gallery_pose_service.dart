import 'capture_quality_guidance.dart';
import 'assistant_operation_log.dart';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import 'impact_detection_service.dart';
import 'club_tracking_service.dart';
import 'arm_refinement_service.dart';
import 'video_orientation_service.dart';

class GalleryPoseService {
  static const _frameChannel =
      MethodChannel('com.metaoffice.aigolfcoatch/frame_extractor');
  static const int recommendedSampleCount = 45;
  static const String poseSchemaVersion = '3.5';
  static int debugLastReviewedCacheHits = 0;
  static int debugLastTrajectoryCacheHits = 0;

  static Future<List<Map<String, dynamic>>> _loadPoseCache(
      String videoPath) async {
    try {
      final video = File(videoPath);
      final sidecar = File('$videoPath.pose.json');
      if (!await video.exists() || !await sidecar.exists()) return [];
      final data = jsonDecode(await sidecar.readAsString());
      if (data is! Map || data['schema_version'] != poseSchemaVersion ||
          data['video_path'] != videoPath) return [];
      final stat = await video.stat();
      if (data['video_size'] == null || data['video_modified_ms'] == null) {
        // Sidecars from older app versions can be adopted only when they were
        // written after the video. A replaced video therefore cannot inherit
        // the previous file's pose data.
        final sidecarStat = await sidecar.stat();
        if (sidecarStat.modified.isBefore(stat.modified)) return [];
        data['video_size'] = stat.size;
        data['video_modified_ms'] = stat.modified.millisecondsSinceEpoch;
        await sidecar.writeAsString(jsonEncode(data), flush: true);
      } else if (data['video_size'] != stat.size ||
          data['video_modified_ms'] != stat.modified.millisecondsSinceEpoch) {
        return [];
      }
      var offset = 0;
      final review = File('$videoPath.review.json');
      if (await review.exists()) {
        final decoded = jsonDecode(await review.readAsString());
        if (decoded is Map && decoded['pose_overlay_offset_ms'] is num) {
          offset = (decoded['pose_overlay_offset_ms'] as num).round();
        }
      }
      final samples = data['samples'];
      if (samples is! List) return [];
      return [
        for (final value in samples)
          if (value is Map)
            {
              ...Map<String, dynamic>.from(value),
              't_ms': ((value['t_ms'] as num?)?.round() ?? 0) - offset,
            }
      ];
    } catch (_) {
      return [];
    }
  }

  static Map<String, dynamic>? _nearestCached(
      List<Map<String, dynamic>> rows, int time, int toleranceMs) {
    Map<String, dynamic>? best;
    var distance = toleranceMs + 1;
    for (final row in rows) {
      final t = (row['t_ms'] as num?)?.round();
      final landmarks = row['landmarks'];
      if (t == null || landmarks is! List || landmarks.isEmpty) continue;
      final d = (t - time).abs();
      if (d < distance) {
        distance = d;
        best = row;
      }
    }
    return best == null ? null : Map<String, dynamic>.from(best);
  }

  static Future<void> _mergePoseCache(
      String videoPath, List<Map<String, dynamic>> fresh) async {
    if (fresh.isEmpty) return;
    try {
      final file = File('$videoPath.pose.json');
      final data = jsonDecode(await file.readAsString());
      if (data is! Map || data['schema_version'] != poseSchemaVersion) return;
      var offset = 0;
      final review = File('$videoPath.review.json');
      if (await review.exists()) {
        final decoded = jsonDecode(await review.readAsString());
        if (decoded is Map && decoded['pose_overlay_offset_ms'] is num) {
          offset = (decoded['pose_overlay_offset_ms'] as num).round();
        }
      }
      final merged = <int, Map<String, dynamic>>{};
      for (final value in (data['samples'] as List? ?? const [])) {
        if (value is Map && value['t_ms'] is num) {
          final row = Map<String, dynamic>.from(value);
          merged[(row['t_ms'] as num).round()] = row;
        }
      }
      for (final value in fresh) {
        final t = ((value['t_ms'] as num?)?.round() ?? 0) + offset;
        merged[t] = {
          't_ms': t,
          'width': value['width'],
          'height': value['height'],
          'detected': (value['landmarks'] as List? ?? const []).isNotEmpty,
          'landmarks': value['landmarks'] ?? const [],
        };
      }
      final rows = merged.values.toList()
        ..sort((a, b) => (a['t_ms'] as int).compareTo(b['t_ms'] as int));
      data['samples'] = rows;
      data['sample_count'] = rows.length;
      data['pose_cache_version'] = 1;
      await file.writeAsString(jsonEncode(data), flush: true);
    } catch (error) {
      debugPrint('[POSE_CACHE] merge failed: $error');
    }
  }

  /// Re-detect at each reviewed timestamp instead of reusing the sparse scan.
  /// Android returns the closest frame; its actual presentation time is unknown.
  static Future<Map<String, dynamic>> measureReviewedFrames(
      String videoPath, Map<String, int> events, {void Function(String)? onProgress}) async {
    debugLastReviewedCacheHits = 0;
    final cached = await _loadPoseCache(videoPath);
    final detector = PoseDetector(options: PoseDetectorOptions(
      mode: PoseDetectionMode.single, model: PoseDetectionModel.accurate));
    final output = <String, dynamic>{};
    try {
      for (final event in events.entries) {
        const labels={'address':'어드레스','top':'백스윙 탑','impact':'임팩트','finish':'피니시'};
        onProgress?.call('${labels[event.key] ?? event.key} 자세의 관절을 확인하고 있습니다.');
        final reused = _nearestCached(cached, event.value, 90);
        if (reused != null) {
          output[event.key] = reused;
          debugLastReviewedCacheHits++;
          debugPrint('[POSE_CACHE] reviewed ${event.key} reused');
          continue;
        }
        final temporary = <Map<String, dynamic>>[];
        try {
          final frames = await _frameChannel.invokeMethod<List<dynamic>>('extractFrames', {
            'videoPath': videoPath, 'startMs': event.value,
            'endMs': event.value, 'sampleCount': 2,
          });
          temporary.addAll((frames ?? []).map((f) => Map<String, dynamic>.from(f as Map)));
          if (temporary.isEmpty) continue;
          final frame = temporary.first;
          final poses = await detector.processImage(InputImage.fromFilePath(frame['path'] as String));
          output[event.key] = {
            't_ms': frame['t_ms'], 'width': frame['width'], 'height': frame['height'],
            'landmarks': poses.isEmpty ? <Map<String, dynamic>>[] : [
              for (final p in poses.first.landmarks.values)
                if (_getLandmarkName(p.type) != null)
                  {'name': _getLandmarkName(p.type), 'x': p.x, 'y': p.y, 'likelihood': p.likelihood},
            ],
          };
        } catch (error) {
          debugPrint('[POSE_MEASUREMENT] ${event.key}: $error');
        } finally {
          for (final frame in temporary) {
            try { await File(frame['path'] as String).delete(); } catch (_) {}
          }
        }
      }
    } finally {
      await detector.close();
    }
    return output;
  }

  /// Bounded uniform sampling, not native video PTS or angular velocity data.
  static Future<List<Map<String, dynamic>>> measureTrajectoryFrames(
      String videoPath, int startMs, int endMs, {int? topMs, int? finishMs, String leadSide = 'left', void Function(String)? onProgress}) async {
    debugLastTrajectoryCacheHits = 0;
    if (startMs < 0 || endMs <= startMs) return [];
    final count = (((endMs - startMs) / 33).ceil() + 1).clamp(3, 91);
    final temporary = <Map<String, dynamic>>[];
    final output = <Map<String, dynamic>>[];
    final cached = await _loadPoseCache(videoPath);
    var reusedCount = 0;
    final detector = PoseDetector(options: PoseDetectorOptions(
        mode: PoseDetectionMode.single, model: PoseDetectionModel.accurate));
    try {
      final windows = <List<int>>[];
      if (topMs != null && startMs < topMs && topMs < endMs) {
        windows.add([startMs, topMs, (((topMs-startMs)/33).ceil()+1).clamp(3,61)]);
        windows.add([topMs, endMs, (((endMs-topMs)/17).ceil()+1).clamp(3,61)]);
      } else { windows.add([startMs,endMs,count]); }
      if (finishMs != null && finishMs > endMs) {
        final followEnd = finishMs < endMs+300 ? finishMs : endMs+300;
        windows.add([endMs,followEnd,(((followEnd-endMs)/17).ceil()+1).clamp(3,21)]);
      }
      for (final window in windows) {
        onProgress?.call('스윙 동작을 자세히 볼 장면을 준비하고 있습니다. (${windows.indexOf(window)+1}/${windows.length})');
        final extracted = await _frameChannel.invokeMethod<List<dynamic>>(
            'extractFrames', {'videoPath':videoPath,'startMs':window[0],
              'endMs':window[1],'sampleCount':window[2]});
        temporary.addAll((extracted ?? []).map((f)=>Map<String,dynamic>.from(f as Map)));
      }
      final visited = <int>{};
      final totalUnique = temporary.map((f)=>f['t_ms']).toSet().length;
      for (final frame in temporary) {
        if (!visited.add(frame['t_ms'] as int)) continue;
        final time = frame['t_ms'] as int;
        final movement = time > endMs
            ? '치킨윙 분석 준비 · 임팩트 이후 팔꿈치 굽힘 확인'
            : topMs != null && time <= topMs
                ? '스웨이 분석 준비 · 어드레스부터 백스윙 탑까지 머리 이동 확인'
                : '얼리 스탠드업·배치기·헤드업 분석 준비 · 다운스윙의 상체·골반·머리 이동 확인';
        onProgress?.call('$movement\n관절 추적 ${visited.length}/$totalUnique장');
        final row = <String, dynamic>{
          't_ms': frame['t_ms'], 'width': frame['width'], 'height': frame['height'],
          'landmarks': <Map<String, dynamic>>[],
        };
        final reused = _nearestCached(cached, time, 20);
        if (reused != null) {
          row.addAll(reused);
          row['t_ms'] = time;
          reusedCount++;
          output.add(row);
          continue;
        }
        try {
          final poses = await detector.processImage(InputImage.fromFilePath(frame['path'] as String));
          if (poses.length == 1) {
            row['landmarks'] = [for (final p in poses.single.landmarks.values)
              if (_getLandmarkName(p.type) != null)
                {'name': _getLandmarkName(p.type), 'x': p.x, 'y': p.y, 'likelihood': p.likelihood}];
          }
          row['pose_count'] = poses.length;
        } catch (_) { row['error'] = 'pose_detection_failed'; }
        output.add(row);
      }
      if (reusedCount > 0) {
        debugLastTrajectoryCacheHits = reusedCount;
        onProgress?.call('기존 관절 기록 $reusedCount장을 재사용했습니다.');
        debugPrint('[POSE_CACHE] trajectory reused=$reusedCount total=$totalUnique');
      }
      // Retry only weak lead-arm observations during downswing; retain originals.
      if (topMs != null) {
        final paths = {for (final frame in temporary) frame['t_ms']: frame['path']};
        var attempts = 0;
        for (final row in output) {
          final time = row['t_ms'] as int;
          if (time < topMs || time > endMs || attempts >= 12 ||
              !ArmRefinementService.shortArm(row, leadSide)) continue;
          attempts++;
          onProgress?.call('캐스팅 측정 검증 · 팔과 손목을 확대해 다시 확인 중 ($attempts/12)');
          Map<String,dynamic>? crop;
          try {
            crop = await compute(ArmRefinementService.prepare,
              <String,dynamic>{'row':row,'path':paths[time]});
            if (crop == null) continue;
            final poses = await detector.processImage(InputImage.fromFilePath(crop['path'] as String));
            if (poses.length != 1) continue;
            final points = <Map<String,dynamic>>[for(final p in poses.single.landmarks.values)
              if (_getLandmarkName(p.type) != null)
                {'name':_getLandmarkName(p.type),'x':p.x,'y':p.y,'likelihood':p.likelihood}];
            row['arm_refinement'] = {'method':'full_body_crop_1280',
              'landmarks':ArmRefinementService.restore(points,crop),
              'crop':{for(final e in crop.entries) if(e.key!='path')e.key:e.value}};
          } catch (error) {
            row['arm_refinement']={'status':'failed','reason':'crop_detection_failed'};
          } finally {
            if(crop?['path'] is String) {
              try {await File(crop!['path'] as String).delete();} catch (_) {}
            }
          }
        }
        try { ArmRefinementService.select(output,leadSide); }
        catch (error) {
          for(final row in output) { row.remove('casting_landmarks'); }
          debugPrint('[ARM_REFINE] selection failed: $error');
        }
      }
      // Analyze before temporary images are removed; CPU work stays off the UI isolate.
      // Candidates remain separate from verified club coordinates.
      try {
        onProgress?.call('캐스팅·오버더탑 측정 검증 · 샤프트 후보 추적 중');
        // Keep the native pose detector and CPU-heavy pixel scan sequential on
        // mobile. Running both together can contend for the same device worker
        // pool and take longer, or stall, on memory-constrained phones.
        final tracks = await compute(ClubTrackingService.analyze,
          <String, dynamic>{'frames': temporary, 'samples': output});
        final byTime = {for (final track in tracks) track['t_ms']: track};
        for (final row in output) {
          final track = byTime[row['t_ms']];
          row['shaft_candidate'] = track;
          row['near_shaft_candidate'] = track?['near_grip_candidate'];
        }
      } catch (error) {
        debugPrint('[CLUB_TRACK] candidate extraction failed: $error');
      }
      await _mergePoseCache(videoPath, output);
    } finally {
      // Cleanup even if detector disposal fails.
      try { await detector.close(); } finally {
        for (final f in temporary) {
          try { await File(f['path'] as String).delete(); } catch (_) {}
        }
      }
    }
    return output;
  }

  static Future<void> _ensureVideoOrientation(String videoPath,
      void Function(double progress, String status) onProgress) async {
    final orientationFile = File('$videoPath.orientation.json');
    if (await orientationFile.exists()) return;
    final temporary = <Map<String, dynamic>>[];
    PoseDetector? detector;
    try {
      onProgress(.05, '영상 방향을 빠르게 확인하고 있습니다.');
      final extracted = await _frameChannel.invokeMethod<List<dynamic>>(
          'extractFrames', {'videoPath': videoPath, 'sampleCount': 9});
      temporary.addAll((extracted ?? const [])
          .map((f) => Map<String, dynamic>.from(f as Map)));
      if (temporary.isEmpty) return;
      detector = PoseDetector(options: PoseDetectorOptions(
          mode: PoseDetectionMode.single, model: PoseDetectionModel.base));
      final samples = <Map<String, dynamic>>[];
      for (final frame in temporary) {
        final poses = await detector.processImage(
            InputImage.fromFilePath(frame['path'] as String));
        samples.add({
          't_ms': frame['t_ms'],
          'width': frame['width'],
          'height': frame['height'],
          'detected': poses.isNotEmpty,
          'landmarks': <Map<String, dynamic>>[
            if (poses.isNotEmpty)
              for (final point in poses.first.landmarks.values)
                if (_getLandmarkName(point.type) != null)
                  {
                    'name': _getLandmarkName(point.type),
                    'x': point.x,
                    'y': point.y,
                    'likelihood': point.likelihood,
                  }
          ],
        });
      }
      final turns = VideoOrientationService.infer(samples);
      if (turns != null) {
        await orientationFile.writeAsString(jsonEncode({
          'quarter_turns': turns,
          'basis': 'nine_frame_orientation_probe',
          'version': 2,
        }), flush: true);
        if (turns != 0) {
          AssistantOperationLog.current.note('영상 방향', '대체 처리',
              '9개 장면으로 촬영 방향을 확인해 본 분석 전에 영상을 보정했습니다.');
        }
      }
    } catch (error) {
      debugPrint('[ORIENTATION_PROBE] failed: $error');
    } finally {
      await detector?.close();
      for (final frame in temporary) {
        try { await File(frame['path'] as String).delete(); } catch (_) {}
      }
    }
  }

  static Future<bool> analyzeGalleryVideo({
    required String videoPath,
    required void Function(double progress, String status) onProgress,
    void Function(int stage)? onStage,
  }) async {
    onStage?.call(0);
    onProgress(0.10, '갤러리 영상 비디오 프레임 분할 중…');

    PoseDetector? poseDetector;
    final frameInputs = <Map<String, dynamic>>[];
    try {
      await _ensureVideoOrientation(videoPath, onProgress);
      final List<dynamic>? frames =
          await _frameChannel.invokeMethod('extractFrames', {
        'videoPath': videoPath,
        'sampleCount': recommendedSampleCount,
        // Keep enough samples for a roughly 0.4 second downswing. Candidate
        // windows are rescanned around 30 fps below, so the rest stays coarse.
        'maxIntervalMs': 200,
      });

      if (frames == null || frames.isEmpty) {
        return false;
      }

      onStage?.call(1);
      onProgress(0.25, '온디바이스 AI 관절 감지기 초기화 중…');
      final options = PoseDetectorOptions(
        mode: PoseDetectionMode.single,
        model: PoseDetectionModel.accurate,
      );
      poseDetector = PoseDetector(options: options);

      final samples = <Map<String, dynamic>>[];
      final total = frames.length;

      for (int i = 0; i < total; i++) {
        final frame = Map<String, dynamic>.from(frames[i] as Map);
        final String imagePath = frame['path'] as String;
        final int tMs = frame['t_ms'] as int;
        final num w = frame['width'] as num;
        final num h = frame['height'] as num;
        frameInputs.add({
          'path': imagePath,
          't_ms': tMs,
          'width': w,
          'height': h,
        });

        final currentProgress = 0.25 + (0.50 * (i / total));
        onProgress(currentProgress, '갤러리 영상 관절 정밀 스캔 중 (${i + 1}/$total)…');

        final inputImage = InputImage.fromFilePath(imagePath);
        final List<Pose> poses = await poseDetector.processImage(inputImage);

        final landmarksList = <Map<String, dynamic>>[];
        if (poses.isNotEmpty) {
          final pose = poses.first;
          for (final entry in pose.landmarks.entries) {
            final landmark = entry.value;
            final name = _getLandmarkName(landmark.type);
            if (name != null) {
              landmarksList.add({
                'name': name,
                'x': landmark.x,
                'y': landmark.y,
                'likelihood': landmark.likelihood,
              });
            }
          }
        }

        samples.add({
          't_ms': tMs,
          'width': w,
          'height': h,
          'detected': landmarksList.isNotEmpty,
          'landmarks': landmarksList,
        });
      }

      final orientationFile=File('$videoPath.orientation.json');
      if(!await orientationFile.exists()) {
        final turns=VideoOrientationService.infer(samples);
        if(turns!=null) {
          await orientationFile.writeAsString(jsonEncode({'quarter_turns':turns,
            'basis':'confident_shoulder_to_ankle_consensus','version':1}),flush:true);
          if(turns!=0) {
            AssistantOperationLog.current.note('영상 방향', '대체 처리', '촬영 방향을 보정하고 관절 인식을 다시 시도합니다.');
            onProgress(.20,'촬영 방향을 바로잡아 관절을 다시 인식하고 있습니다.');
            await poseDetector.close();
            poseDetector=null;
            return await analyzeGalleryVideo(videoPath:videoPath,onProgress:onProgress,onStage:onStage);
          }
        }
      }
      final poseFile = File('$videoPath.pose.json');
      final videoStat = await File(videoPath).stat();
      final poseData = <String, dynamic>{
        'schema_version': poseSchemaVersion,
        'source': 'mlkit_pose_detection',
        'video_path': videoPath,
        'video_size': videoStat.size,
        'video_modified_ms': videoStat.modified.millisecondsSinceEpoch,
        'sample_count': total,
        'frame_extraction_mode': 'closest_frame',
        'coordinate_space': 'upright_image_pixels',
        'timestamp_basis': 'requested_closest_frame_ms',
        'video_pts_synchronized': false,
        'vision_impact': null,
        'impact_debug': {'version': ImpactDetectionService.debugVersion, 'status': 'pending'},
        'samples': samples,
      };
      // Preserve detected joints even if optional impact analysis fails.
      await poseFile.writeAsString(jsonEncode(poseData), flush: true);
      onStage?.call(2);
      onProgress(0.80, '관절 스캔 저장 완료 · 임팩트 후보 분석 중…');
      try {
        final windows = ImpactDetectionService.scanWindows(samples);
        if(windows.isEmpty) AssistantOperationLog.current.note('스윙 후보 탐색', '경고', '관절 기록에서 정밀 검사할 스윙 후보 구간을 찾지 못했습니다.');
        final reports=<Map<String,dynamic>>[];
        for(var candidate=0;candidate<windows.length;candidate++) {
          final window=windows[candidate];
          var impactFrames=<Map<String,dynamic>>[];
          onStage?.call(3);
          onProgress(0.80, '스윙 후보 ${candidate+1}/${windows.length} · 타격 구간 정밀 확인 중…');
          final dense = await _frameChannel.invokeMethod<List<dynamic>>('extractFrames', {
            'videoPath': videoPath,
            'startMs': window['start_ms'], 'endMs': window['end_ms'],
            'sampleCount': (((window['end_ms']! - window['start_ms']!) / 33).ceil() + 1).clamp(5, 90),
          });
          if (dense != null && dense.isNotEmpty) {
            impactFrames = dense.map((f) => Map<String, dynamic>.from(f as Map)).toList();
            frameInputs.addAll(impactFrames);
            // The screen also needs dense joints: smoothing a 150ms scan can
            // erase the brief wrist return at impact even when the phase exists.
            final byTime={for(final row in samples) row['t_ms']:row};
            for(final frame in impactFrames) {
              onProgress(0.80, '임팩트 주변 관절을 정밀 확인 중 (${impactFrames.indexOf(frame)+1}/${impactFrames.length}장)…');
              final poses=await poseDetector.processImage(InputImage.fromFilePath(frame['path'] as String));
              byTime[frame['t_ms']]={
                't_ms':frame['t_ms'],'width':frame['width'],'height':frame['height'],
                'detected':poses.length==1,'landmarks':<Map<String,dynamic>>[
                  if(poses.length==1)for(final p in poses.single.landmarks.values)
                    if(_getLandmarkName(p.type)!=null)
                      {'name':_getLandmarkName(p.type),'x':p.x,'y':p.y,'likelihood':p.likelihood}
                ]};
            }
            samples..clear()..addAll(byTime.values);
            samples.sort((a,b)=>(a['t_ms'] as int).compareTo(b['t_ms'] as int));
            poseData['sample_count']=samples.length;
            poseData['dense_pose_windows']=windows;

          }
          onStage?.call(4);
          onProgress(0.88, '스윙 후보 ${candidate+1}/${windows.length} · 공 이동·클럽 궤적 비교 중…');
          reports.add(await compute(_analyzeImpact, {
            'frames':impactFrames,'samples':samples,'window':window,
          }));
        }
        final impactResult=ImpactDetectionService.selectSwing(windows,reports);
        onStage?.call(5);
        onProgress(0.98, '영상 분석 기록을 저장하고 자세 분석을 준비하고 있습니다.');
        poseData['vision_impact'] = impactResult['result'];
        poseData['impact_debug'] = impactResult['diagnostics'];
        final debug = impactResult['diagnostics'] as Map;
        if(impactResult['result']==null) AssistantOperationLog.current.note('공·클럽 타격 확인', '대체 처리', '공 이동과 클럽 궤적으로 임팩트를 확정하지 못해 관절 기반 시점 탐색으로 이어갑니다.');
        debugPrint('[IMPACT_DEBUG] status=${debug['status']} reason=${debug['reason']} selected_ms=${debug['selected_ms']}');
        await poseFile.writeAsString(jsonEncode(poseData), flush: true);
      } catch (error, stack) {
        AssistantOperationLog.current.note('임팩트 정밀 분석', '대체 처리', '정밀 분석 중 오류가 발생했습니다. 확보한 관절 기록을 유지하고 자세 기반 분석을 이어갑니다.');
        poseData['impact_debug'] = {'version': ImpactDetectionService.debugVersion,
          'status': 'error', 'reason': 'worker_failed', 'error': error.toString()};
        await poseFile.writeAsString(jsonEncode(poseData), flush: true);
        debugPrint('Optional impact analysis failed: $error\n$stack');
      }

      final detectedCount = samples.where((s) => s['detected'] == true).length;
      final quality=CaptureQualityGuidance.assess(samples);
      AssistantOperationLog.current.note('관절 인식', quality['poor']==true?'경고':'완료', quality['message'] as String);
      if(quality['poor']==true) AssistantOperationLog.current.note('촬영 상태 확인', '경고', CaptureQualityGuidance.advice);
      onProgress(1.0, detectedCount == 0
          ? '영상 ${samples.length}개 프레임 분석 완료 · 사람 관절을 검출하지 못했습니다.'
          : '관절 스캔 완료 · ${samples.length}개 중 $detectedCount개 프레임 검출');
      return true;
    } catch (error, stack) {
      AssistantOperationLog.current.fail('관절 인식', error);
      debugPrint('Gallery pose analysis failed: $error\n$stack');
      onProgress(1.0, '관절 분석 실패: $error');
      return false;
    } finally {
      try {
        await poseDetector?.close();
      } catch (error) {
        debugPrint('Pose detector cleanup failed: $error');
      }
      for (final frame in frameInputs) {
        try {
          await File(frame['path'] as String).delete();
        } catch (_) {}
      }
    }
  }

  static String? _getLandmarkName(PoseLandmarkType type) {
    switch (type) {
      case PoseLandmarkType.leftHeel:
        return 'leftHeel';
      case PoseLandmarkType.rightHeel:
        return 'rightHeel';
      case PoseLandmarkType.leftFootIndex:
        return 'leftFootIndex';
      case PoseLandmarkType.rightFootIndex:
        return 'rightFootIndex';
      case PoseLandmarkType.leftEar:
        return 'leftEar';
      case PoseLandmarkType.rightEar:
        return 'rightEar';
      case PoseLandmarkType.leftEye:
        return 'leftEye';
      case PoseLandmarkType.rightEye:
        return 'rightEye';
      case PoseLandmarkType.leftShoulder:
        return 'leftShoulder';
      case PoseLandmarkType.rightShoulder:
        return 'rightShoulder';
      case PoseLandmarkType.leftElbow:
        return 'leftElbow';
      case PoseLandmarkType.rightElbow:
        return 'rightElbow';
      case PoseLandmarkType.leftWrist:
        return 'leftWrist';
      case PoseLandmarkType.rightWrist:
        return 'rightWrist';
      case PoseLandmarkType.leftHip:
        return 'leftHip';
      case PoseLandmarkType.rightHip:
        return 'rightHip';
      case PoseLandmarkType.leftKnee:
        return 'leftKnee';
      case PoseLandmarkType.rightKnee:
        return 'rightKnee';
      case PoseLandmarkType.leftAnkle:
        return 'leftAnkle';
      case PoseLandmarkType.rightAnkle:
        return 'rightAnkle';
      default:
        return null;
    }
  }
}

Future<Map<String, dynamic>> _analyzeImpact(Map<String, dynamic> input) async {
  return ImpactDetectionService.analyzeWithDiagnostics(
    frames: input['frames'] as List<Map<String, dynamic>>,
    samples: input['samples'] as List<Map<String, dynamic>>,
    window: input['window'] as Map<String,int>?,
  );
}
