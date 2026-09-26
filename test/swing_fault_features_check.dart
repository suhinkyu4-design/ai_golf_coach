import 'package:ai_golf_coach/models/swing_model.dart';
import 'package:ai_golf_coach/services/swing_fault_features.dart';
import 'pose_measurement_check.dart' as fixture;

void main() {
  SwingModel swing(
          {SwingView view = SwingView.faceOn,
          Handedness hand = Handedness.right}) =>
      SwingModel(
          swingId: 't',
          createdAt: DateTime(2026),
          videoPath: '',
          view: view,
          handedness: hand,
          club: '7i',
          durationMs: 1200,
          fps: 60,
          eventsMs: {
            'address': 100,
            'top': 500,
            'impact': 800,
            'finish': 1100
          });
  Map<String, dynamic> f(int t,
      {bool mirror = false, double confidence = 1, bool club = false}) {
    final raw = fixture.frame(t, likelihood: confidence);
    for (final p in raw['landmarks'] as List) {
      if (t > 100) p['x'] = (p['x'] as num) + 30;
      if (mirror) p['x'] = 999 - (p['x'] as num);
    }
    if (club)
      raw['club'] = {
        't_ms': t,
        'identity_verified': true,
        'coordinate_space': 'upright_image_pixels',
        'grip': {'x': 350.0, 'y': 350.0},
        'head': {'x': 550.0, 'y': 600.0}
      };
    return raw;
  }

  Map<String, dynamic> run(
          {SwingView view = SwingView.faceOn,
          bool mirror = false,
          bool club = false,
          bool confirmed = true}) =>
      SwingFaultFeatures.analyze(
          swing: swing(view: view),
          reviewed: {
            for (final e in swing().eventsMs.entries)
              e.key: f(e.value, mirror: mirror, club: club)
          },
          samples: [
            for (var t = 120; t <= 1100; t += 20)
              f(t, mirror: mirror, club: club)
          ],
          confirmed: confirmed,
          ballImageSign: 1);
  Map row(Map r, String id) =>
      (r['patterns'] as List).firstWhere((p) => p['id'] == id);
  final front = run(), rear = run(view: SwingView.rear);
  fixture.check(
      (front['patterns'] as List).length == 9, 'all nine must report status');
  fixture.check(row(front, 'sway')['status'] == 'measured_not_classified',
      'front sway evidence');
  fixture.check(
      row(front, 'standing_up')['reason'] == 'different_view_required',
      'view gate');
  fixture.check(row(rear, 'standing_up')['status'] == 'measured_not_classified',
      'rear torso series');
  fixture.check(
      row(front, 'chicken_wing')['status'] == 'measured_not_classified',
      'early follow-through captured');
  fixture.check(
      row(front, 'casting')['reason'] == 'verified_club_track_required',
      'never use pose as club');
  fixture.check(
      row(run(club: true), 'casting')['status'] == 'measured_not_classified',
      'verified club contract');
  fixture.check(
      row(run(club: true), 'overswing')['status'] == 'measured_not_classified',
      'top shaft geometry');
  fixture.check(
      row(run(view: SwingView.rear, club: true), 'over_the_top')['status'] ==
          'measured_not_classified',
      'height matched path geometry');
  final mirrored = run(mirror: true);
  fixture.check(
      (row(front, 'sway')['peak']['value'] -
                  row(mirrored, 'sway')['peak']['value'])
              .abs() <
          1e-9,
      'mirror invariant target-relative displacement');
  fixture.check(
      (run(confirmed: false)['patterns'] as List)
          .every((p) => p['status'] == 'unavailable'),
      'unconfirmed events');
  fixture.check(
      (front['patterns'] as List).every((p) => p['diagnosis'] == null),
      'no unsupported diagnosis');
  fixture.check((row(front, 'sway')['peak']['value'] - .1).abs() < 1e-9,
      'known 30px / 300px translation');
  final noisy = [for (var time = 120; time <= 1100; time += 20) f(time)];
  for (final joint in noisy
      .firstWhere((frame) => frame['t_ms'] == 300)['landmarks'] as List) {
    joint['x'] = (joint['x'] as num) + 250;
  }
  final filtered = SwingFaultFeatures.analyze(
      swing: swing(),
      reviewed: {for (final e in swing().eventsMs.entries) e.key: f(e.value)},
      samples: noisy,
      confirmed: true);
  fixture.check((row(filtered, 'sway')['peak']['value'] - .1).abs() < 1e-9,
      'isolated false pose translation suppressed');
  final wrongClub = f(500, club: true);
  (wrongClub['club'] as Map)['t_ms'] = 501;
  final rejected = SwingFaultFeatures.analyze(
      swing: swing(),
      reviewed: {
        for (final e in swing().eventsMs.entries)
          e.key: e.key == 'top' ? wrongClub : f(e.value, club: true)
      },
      samples: [
        for (var time = 120; time <= 1100; time += 20) f(time, club: true)
      ],
      confirmed: true);
  fixture.check(row(rejected, 'overswing')['status'] == 'unavailable',
      'club annotation must match exact frame');
  final sparse = SwingFaultFeatures.analyze(
      swing: swing(),
      reviewed: {for (final e in swing().eventsMs.entries) e.key: f(e.value)},
      samples: [f(120), f(300), f(480)],
      confirmed: true);
  fixture.check(row(sparse, 'sway')['reason'] == 'sampling_gaps_too_large',
      'do not smooth across large gaps');
  print('NINE_PATTERN_FEATURE_CHECK_PASSED');
}
