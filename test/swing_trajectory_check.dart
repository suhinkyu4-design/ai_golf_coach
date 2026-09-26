import 'package:ai_golf_coach/services/swing_trajectory_service.dart';
import 'pose_measurement_check.dart' as fixture;

void main() {
  final swing = fixture.swing();
  Map<String, dynamic> sample(int t, double offset, {double likelihood = 1}) {
    final f = fixture.frame(t, likelihood: likelihood);
    for (final p in f['landmarks'] as List) { p['x'] = (p['x'] as num) + offset; }
    return f;
  }
  Map<String, dynamic> run(List<Map<String, dynamic>> samples, {bool confirmed = true}) =>
    SwingTrajectoryService.measure(swing: swing, address: fixture.frame(100), samples: samples, confirmed: confirmed);
  final samples = [for (final t in [110, 140, 170, 200, 220, 250, 280, 300]) sample(t, t == 170 ? 60 : 30)];
  final result = run(samples.reversed.toList()..add(samples.first));
  fixture.check(result['requested_sample_count'] == 8, 'sort and deduplicate requested times');
  final summary = (result['summaries'] as List).firstWhere((s) => s['landmark_group'] == 'pelvis_midpoint' && s['segment'] == 'backswing');
  fixture.check(summary['dx_peak_requested_ms'] == 170, 'find interior peak, not only endpoints');
  fixture.check((summary['dx_max_abs_signed'] - .2).abs() < 1e-9, 'fixed baseline normalization');
  final poor = run([sample(110, 30), sample(140, 30, likelihood: .2), sample(170, 30), sample(200, 30, likelihood: .2)]);
  fixture.check((poor['summaries'] as List).every((s) => !s.containsKey('dx_max_abs_signed')), 'insufficient coverage suppresses peaks');
  fixture.check(run(samples, confirmed: false)['status'] == 'unavailable', 'unconfirmed events');
  fixture.check(!(result['tracks'] as Map).containsKey('head_eye_midpoint'), 'missing head does not fabricate data');
  fixture.check(result['video_pts_synchronized'] == false, 'requested time is not actual PTS');
  print('TRAJECTORY_CHECK_PASSED');
}
