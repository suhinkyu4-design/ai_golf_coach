import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';

class GalleryPoseService {
  static const _frameChannel = MethodChannel('com.metaoffice.aigolfcoatch/frame_extractor');

  static Future<bool> analyzeGalleryVideo({
    required String videoPath,
    required void Function(double progress, String status) onProgress,
  }) async {
    onProgress(0.10, '갤러리 영상 비디오 프레임 분할 중…');

    try {
      final List<dynamic>? frames = await _frameChannel.invokeMethod('extractFrames', {
        'videoPath': videoPath,
        'sampleCount': 25,
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
      final total = frames.length;

      for (int i = 0; i < total; i++) {
        final frame = Map<String, dynamic>.from(frames[i] as Map);
        final String imagePath = frame['path'] as String;
        final int tMs = frame['t_ms'] as int;
        final num w = frame['width'] as num;
        final num h = frame['height'] as num;

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

        try { File(imagePath).delete(); } catch (_) {}
      }

      await poseDetector.close();

      onProgress(0.80, '스윙 동작 생체역학 궤적 분석 중…');

      final poseFile = File('$videoPath.pose.json');
      await poseFile.writeAsString(jsonEncode({
        'schema_version': '1.0',
        'source': 'mlkit_pose_detection',
        'video_path': videoPath,
        'coordinate_space': 'upright_image_pixels',
        'timestamp_basis': 'video_pts_ms',
        'video_pts_synchronized': true,
        'samples': samples,
      }), flush: true);

      onProgress(1.0, '갤러리 영상 스윙 분석 완료!');
      return true;
    } catch (_) {
      return false;
    }
  }

  static String? _getLandmarkName(PoseLandmarkType type) {
    switch (type) {
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
      default: return null;
    }
  }
}
