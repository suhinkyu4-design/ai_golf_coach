import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import 'impact_detection_service.dart';

class GalleryPoseService {
  static const _frameChannel = MethodChannel('com.metaoffice.aigolfcoatch/frame_extractor');
  static const int recommendedSampleCount = 45;
  static const String poseSchemaVersion = '3.0';

  static Future<bool> analyzeGalleryVideo({
    required String videoPath,
    required void Function(double progress, String status) onProgress,
  }) async {
    onProgress(0.10, '갤러리 영상 비디오 프레임 분할 중…');

    try {
      final List<dynamic>? frames = await _frameChannel.invokeMethod('extractFrames', {
        'videoPath': videoPath,
        'sampleCount': recommendedSampleCount,
      });

      if (frames == null || frames.isEmpty) {
        return false;
      }

      onProgress(0.25, '온디바이스 AI 관절 감지기 초기화 중…');
      final options = PoseDetectorOptions(
        mode: PoseDetectionMode.single,
        model: PoseDetectionModel.accurate,
      );
      final poseDetector = PoseDetector(options: options);

      final samples = <Map<String, dynamic>>[];
      final frameInputs = <Map<String, dynamic>>[];
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

      await poseDetector.close();

      onProgress(0.80, '스윙 동작 생체역학 궤적 분석 중…');
      final impactResult = await ImpactDetectionService.detectImpact(
        frames: frameInputs,
        samples: samples,
      );

      final poseFile = File('$videoPath.pose.json');
      await poseFile.writeAsString(jsonEncode({
        'schema_version': poseSchemaVersion,
        'source': 'mlkit_pose_detection',
        'video_path': videoPath,
        'sample_count': total,
        'frame_extraction_mode': 'closest_frame',
        'coordinate_space': 'upright_image_pixels',
        'timestamp_basis': 'video_pts_ms',
        'video_pts_synchronized': true,
        'vision_impact': impactResult?.toJson(),
        'samples': samples,
      }), flush: true);

      for (final frame in frameInputs) {
        final path = frame['path'];
        if (path is String) {
          try { File(path).delete(); } catch (_) {}
        }
      }

      onProgress(1.0, '갤러리 영상 스윙 분석 완료!');
      return true;
    } catch (_) {
      return false;
    }
  }

  static String? _getLandmarkName(PoseLandmarkType type) {
    switch (type) {
      case PoseLandmarkType.nose: return 'nose';
      case PoseLandmarkType.leftEye: return 'leftEye';
      case PoseLandmarkType.rightEye: return 'rightEye';
      case PoseLandmarkType.leftEar: return 'leftEar';
      case PoseLandmarkType.rightEar: return 'rightEar';
      case PoseLandmarkType.leftShoulder: return 'leftShoulder';
      case PoseLandmarkType.rightShoulder: return 'rightShoulder';
      case PoseLandmarkType.leftElbow: return 'leftElbow';
      case PoseLandmarkType.rightElbow: return 'rightElbow';
      case PoseLandmarkType.leftWrist: return 'leftWrist';
      case PoseLandmarkType.rightWrist: return 'rightWrist';
      case PoseLandmarkType.leftHip: return 'leftHip';
      case PoseLandmarkType.rightHip: return 'rightHip';
      case PoseLandmarkType.leftKnee: return 'leftKnee';
      case PoseLandmarkType.rightKnee: return 'rightKnee';
      case PoseLandmarkType.leftAnkle: return 'leftAnkle';
      case PoseLandmarkType.rightAnkle: return 'rightAnkle';
      case PoseLandmarkType.leftHeel: return 'leftHeel';
      case PoseLandmarkType.rightHeel: return 'rightHeel';
      case PoseLandmarkType.leftFootIndex: return 'leftFootIndex';
      case PoseLandmarkType.rightFootIndex: return 'rightFootIndex';
      default: return null;
    }
  }
}
