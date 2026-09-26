// ignore_for_file: avoid_print
import 'dart:convert';
import 'dart:io';
import 'package:ai_golf_coach/models/swing_model.dart';
import 'package:ai_golf_coach/services/evidence_coaching_service.dart';
import 'package:ai_golf_coach/services/coaching_dataset_service.dart';

void check(bool condition, String name) {
  if (!condition) throw StateError(name);
}

void main(List<String> args) {
  final swing = SwingModel(
      swingId: 'test',
      createdAt: DateTime(2026),
      videoPath: '/private.mp4',
      view: SwingView.rear,
      handedness: Handedness.right,
      club: '7i',
      durationMs: 6000,
      fps: 0,
      eventsMs: {'address': 100, 'top': 2000, 'impact': 2300, 'finish': 5000});
  final report = {
    'metrics': [
      for (final phase in ['address', 'top', 'impact', 'finish'])
        for (final kind in ['torso_tilt', 'lead_elbow'])
          {
            'id': '${kind}_projected_at_$phase',
            'value': phase == 'impact' ? 20.0 : 30.0,
            'status': 'estimated',
            'unit': 'deg',
            'min_joint_likelihood': 0.95
          },
    ]
  };
  final context =
      EvidenceCoachingService.build(swing, report, eventsConfirmed: true);
  check(context['facts'].length == 2, 'Compute supported pairs');
  check(
      context['facts'][0]['signed_delta_deg'] == -10, 'Signed measured delta');
  check(context['resources'].length == 2,
      'Retrieve related and general resources');
  check(context['slm_executed'] == false, 'No simulated model execution');
  final blocked =
      EvidenceCoachingService.build(swing, report, eventsConfirmed: false);
  check(blocked['facts'].isEmpty && blocked['resources'].isEmpty,
      'Unconfirmed input cannot trigger advice');
  final missing = EvidenceCoachingService.build(swing, {'metrics': []},
      eventsConfirmed: true);
  check(missing['status'] == 'insufficient_measurements',
      'No zero-valued fallback');
  final weak = jsonDecode(jsonEncode(report)) as Map<String, dynamic>;
  for (final row in weak['metrics']) {
    row['min_joint_likelihood'] = 0.1;
  }
  check(
      EvidenceCoachingService.build(swing, weak,
              eventsConfirmed: true)['resources']
          .isEmpty,
      'Weak evidence rejected');
  final face = SwingModel(
      swingId: swing.swingId,
      createdAt: swing.createdAt,
      videoPath: swing.videoPath,
      view: SwingView.faceOn,
      handedness: swing.handedness,
      club: swing.club,
      durationMs: swing.durationMs,
      fps: swing.fps,
      eventsMs: swing.eventsMs);
  check(
      EvidenceCoachingService.build(face, report,
                  eventsConfirmed: true)['facts']
              .length ==
          1,
      'View-specific torso comparison');
  final exported =
      CoachingDatasetService.draft(swing, report, eventsConfirmed: true);
  check(exported['training_target'] == null && !exported.containsKey('review'),
      'No review gate or pseudo target');
  check(!jsonEncode(exported).contains('/private.mp4'),
      'No video path disclosure');
  if (args.length == 2) {
    final actual =
        jsonDecode(File(args[0]).readAsStringSync()) as Map<String, dynamic>;
    final input = actual['input'] as Map<String, dynamic>;
    final realSwing = SwingModel(
        swingId: actual['record_id'],
        createdAt: DateTime(2026),
        videoPath: '',
        view: SwingView.values.byName(input['view']),
        handedness: Handedness.values.byName(input['handedness']),
        club: input['club'],
        durationMs: 6062,
        fps: 0,
        eventsMs: Map<String, int>.from(input['events_ms']));
    File(args[1]).writeAsStringSync(const JsonEncoder.withIndent('  ').convert(
        CoachingDatasetService.draft(
            realSwing, Map<String, dynamic>.from(input['pose_measurements']),
            eventsConfirmed: input['events_user_confirmed'] == true)));
  }
  print(
      'PASS: evidence, view, quality, missing data, references, export without instructor');
}
