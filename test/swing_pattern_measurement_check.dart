import 'package:ai_golf_coach/services/swing_pattern_measurement_service.dart';
import 'package:ai_golf_coach/models/swing_model.dart';
import 'pose_measurement_check.dart' as fixture;

void main() {
  Map<String, dynamic> run({double scale = 1, bool confirmed = true, bool low = false, bool mismatch = false, String club = '7i'}) {
    final original = fixture.swing();
    final s = SwingModel(swingId: 'test', createdAt: DateTime(2026), videoPath: '', view: original.view, handedness: original.handedness, club: club, durationMs: 5000, fps: 30, eventsMs: original.eventsMs);
    final frames = <String, dynamic>{};
    for (final e in s.eventsMs.entries) {
      final f = fixture.frame(e.value, scale: scale, likelihood: low ? .2 : 1);
      if (e.key != 'address') {
        for (final p in f['landmarks'] as List) { p['x'] = (p['x'] as num) + 30 * scale; }
      }
      if (mismatch && e.key != 'address') f['t_ms'] = 999;
      frames[e.key] = f;
    }
    return SwingPatternMeasurementService.measure(swing: s, frames: frames, confirmed: confirmed);
  }
  final base = run();
  final rows = base['observations'] as List;
  fixture.check(rows.length == 6, 'missing eyes must not be fabricated');
  fixture.check((rows.first['dx'] - .1).abs() < 1e-9, 'known displacement / fixed torso length');
  fixture.check(((run(scale: 2)['observations'] as List).first['dx'] - .1).abs() < 1e-9, 'resolution invariance');
  for (final r in [run(confirmed: false), run(low: true), run(mismatch: true), run(club: '6i')]) {
    fixture.check((r['observations'] as List).isEmpty, 'invalid observations rejected');
  }
  fixture.check(run(club: 'Driver')['club'] == 'driver', 'driver canonical mapping');
  fixture.check(base['diagnosis_available'] == false, 'no unvalidated diagnosis');
  print('PATTERN_MEASUREMENT_CHECK_PASSED');
}
