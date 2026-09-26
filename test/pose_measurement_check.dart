// ignore_for_file: avoid_print
import 'dart:convert';
import 'package:ai_golf_coach/models/swing_model.dart';
import 'package:ai_golf_coach/services/pose_measurement_service.dart';
import 'package:ai_golf_coach/services/coaching_dataset_service.dart';

void check(bool condition, String message) {
  if (!condition) throw StateError(message);
}

SwingModel swing(
        {Handedness hand = Handedness.right,
        SwingView view = SwingView.faceOn}) =>
    SwingModel(
        swingId: 'test',
        createdAt: DateTime(2026),
        videoPath: '/private/video.mp4',
        view: view,
        handedness: hand,
        club: '7i',
        durationMs: 5000,
        fps: 30,
        eventsMs: {'address': 100, 'top': 200, 'impact': 300, 'finish': 400});
Map<String, dynamic> frame(int time,
        {double likelihood = 1, bool degenerate = false, double scale = 1}) =>
    {
      't_ms': time,
      'width': 1000 * scale,
      'height': 1000 * scale,
      'landmarks': [
        for (final p in [
          ['leftShoulder', 200, 200],
          ['leftElbow', 200, 300],
          ['leftWrist', degenerate ? 200 : 300, 300],
          ['rightShoulder', 400, 200],
          ['rightElbow', 400, 300],
          ['rightWrist', 400, 400],
          ['leftHip', 200, 500],
          ['leftKnee', 200, 600],
          ['leftAnkle', 200, 700],
          ['rightHip', 400, 500],
          ['rightKnee', 400, 600],
          ['rightAnkle', 400, 700],
        ])
          {
            'name': p[0],
            'x': (p[1] as num) * scale,
            'y': (p[2] as num) * scale,
            'likelihood': likelihood
          },
      ],
    };
Map<String, dynamic> report(
    {SwingModel? model,
    double likelihood = 1,
    bool degenerate = false,
    double scale = 1,
    bool confirmed = true,
    bool mismatch = false}) {
  final s = model ?? swing();
  return PoseMeasurementService.measure(
      swing: s,
      confirmed: confirmed,
      frames: {
        for (final e in s.eventsMs.entries)
          e.key: frame(e.value + (mismatch ? 20 : 0),
              likelihood: likelihood, degenerate: degenerate, scale: scale),
      });
}

void main() {
  final endSwing = SwingModel(
      swingId: 'end',
      createdAt: DateTime(2026),
      videoPath: 'test.mp4',
      view: SwingView.rear,
      handedness: Handedness.right,
      club: '7i',
      durationMs: 400,
      fps: 0,
      eventsMs: {'address': 100, 'top': 200, 'impact': 300, 'finish': 400});
  final endReport = PoseMeasurementService.measure(
      swing: endSwing, confirmed: true, frames: {'finish': frame(399)});
  check((endReport['metrics'] as List).last['value'] == 0,
      'Video endpoint uses duration-1');
  check((endReport['metrics'] as List).last['sample_t_ms'] == 399,
      'Preserve clamped extraction time');
  final normal = report();
  final rows = normal['metrics'] as List;
  check(rows.length == 20, '4 phases x 5 metrics');
  check(rows[0]['value'] == 90 && rows[1]['value'] == 180,
      'Right hand mapping / known angles');
  check(rows[4]['value'] == 0, 'Vertical torso');
  check(
      (report(model: swing(hand: Handedness.left))['metrics'] as List)[0]
              ['value'] ==
          180,
      'Left handed lead mapping');
  check(jsonEncode(rows) == jsonEncode(report(scale: 2)['metrics']),
      'Uniform scale invariant');
  check(
      (report(likelihood: 0.2)['metrics'] as List)
          .every((r) => r['value'] == null),
      'Reject low confidence');
  check(
      (report(likelihood: double.nan)['metrics'] as List)
          .every((r) => r['value'] == null),
      'Reject NaN');
  check(
      (report(degenerate: true)['metrics'] as List)[0]['reason'] ==
          'degenerate_segment',
      'Reject coincident joints');
  check(
      (report(confirmed: false)['metrics'] as List)
          .every((r) => r['value'] == null),
      'Require reviewed phases');
  check(
      (report(mismatch: true)['metrics'] as List)
          .every((r) => r['value'] == null),
      'Reject timestamp mismatch');
  check(
      (report(model: swing(view: SwingView.unknown))['metrics'] as List)
          .every((r) => r['value'] == null),
      'Unknown view');
  final missing = PoseMeasurementService.measure(
      swing: swing(), frames: {}, confirmed: true);
  check(
      (missing['metrics'] as List)
          .every((r) => r['reason'] == 'frame_unavailable'),
      'Missing frame');
  final badFrame = frame(100);
  (badFrame['landmarks'] as List)[0]['x'] = -1;
  final outside = PoseMeasurementService.measure(
      swing: swing(), frames: {'address': badFrame}, confirmed: true);
  check((outside['metrics'] as List)[0]['reason'] == 'joint_outside_image',
      'Out of image');
  final export =
      CoachingDatasetService.draft(swing(), normal, eventsConfirmed: true);
  check(!jsonEncode(export).contains('/private'), 'No private video path');
  check(
      export['training_consent'] == false &&
          export['training_target'] == null && !export.containsKey('review'),
      'No instructor gate or synthetic training label');
  check(PoseMeasurementService.displayMetrics(normal).length == 20,
      'Display valid metrics');
  check(PoseMeasurementService.displayMetrics(missing).isEmpty,
      'Unavailable not displayed as zero');
  print(
      'PASS: geometry, handedness, scale, quality, timestamps, missing data, export defaults');
}
