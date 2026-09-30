import 'dart:convert';
import 'dart:io';
import 'package:ai_golf_coach/services/capture_quality_guidance.dart';
import 'package:ai_golf_coach/services/impact_detection_service.dart';

void check(bool value, String message) { if (!value) throw StateError(message); }

Map<String, dynamic> sample(int time, double wristY, {bool detected = true}) => {
  't_ms': time, 'width': 720, 'height': 1280, 'detected': detected,
  'landmarks': detected ? [
    {'name': 'leftWrist', 'x': 320.0, 'y': wristY, 'likelihood': .99},
    {'name': 'rightWrist', 'x': 335.0, 'y': wristY, 'likelihood': .99},
    {'name': 'leftShoulder', 'x': 300.0, 'y': 480.0, 'likelihood': .99},
    {'name': 'rightShoulder', 'x': 340.0, 'y': 480.0, 'likelihood': .99},
    {'name': 'leftHip', 'x': 300.0, 'y': 650.0, 'likelihood': .99},
    {'name': 'rightHip', 'x': 340.0, 'y': 650.0, 'likelihood': .99},
    {'name': 'leftAnkle', 'x': 300.0, 'y': 900.0, 'likelihood': .99},
    {'name': 'rightAnkle', 'x': 340.0, 'y': 900.0, 'likelihood': .99},
  ] : [],
};

Future<void> main() async {
  final manifest = jsonDecode(await File('test/fixtures/gallery_video_regression.json').readAsString()) as Map;
  final cases = List<Map<String, dynamic>>.from(manifest['cases'] as List);
  final fast = cases.first;
  final ys = List<num>.from(fast['wrist_y'] as List);
  final fastSamples = [for (var i = 0; i < ys.length; i++) sample(i * 200, ys[i].toDouble())];
  final window = ImpactDetectionService.scanWindow(fastSamples);
  check(window != null, 'fast downswing was rejected: $window');
  check(window!['top_ms']! < window['return_ms']!, 'swing window must return after top');
  check(CaptureQualityGuidance.assess(fastSamples)['poor'] == false, 'usable capture marked poor');

  final departed = cases.last;
  final detected = List<int>.from(departed['detected_indices'] as List).toSet();
  final sampleCount = departed['sample_count'] as int;
  final lostSamples = [for (var i = 0; i < sampleCount; i++) sample(i * 200, 640, detected: detected.contains(i))];
  final quality = CaptureQualityGuidance.assess(lostSamples);
  check(quality['detected'] == 8 && quality['usable'] == 8, 'coverage changed: $quality');
  check(quality['poor'] == true && CaptureQualityGuidance.failureHelp(lostSamples) != null, 'subject-leaves-frame must be a quality failure');
  stdout.writeln('PASS: gallery video regression fixtures (fast downswing and subject leaves frame)');
}
