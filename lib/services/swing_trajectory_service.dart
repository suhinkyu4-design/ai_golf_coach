import '../models/swing_model.dart';
import 'swing_pattern_measurement_service.dart';

class SwingTrajectoryService {
  static Map<String, dynamic> measure({
    required SwingModel swing,
    required dynamic address,
    required List<Map<String, dynamic>> samples,
    required bool confirmed,
  }) {
    final tracks = <String, List<Map<String, dynamic>>>{};
    final summaries = <Map<String, dynamic>>[];
    final result = <String, dynamic>{
      'version': 'trajectory_1.0', 'status': 'unavailable',
      'reason': 'invalid_events_or_baseline',
      'timestamp_basis': 'requested_closest_frame_ms',
      'video_pts_synchronized': false,
      'camera_motion_compensated': false,
      'unit': 'ratio_of_address_projected_torso_length',
      'axes': 'image_right_positive_image_down_positive',
      'diagnosis_available': false,
      'tracks': tracks, 'summaries': summaries,
    };
    final start = swing.eventsMs['address'], top = swing.eventsMs['top'];
    final end = swing.eventsMs['impact'];
    if (!confirmed || start == null || top == null || end == null ||
        start < 0 || !(start < top && top < end) || end > swing.durationMs ||
        address is! Map<String, dynamic>) return result;
    final unique = <int, Map<String, dynamic>>{};
    for (final sample in samples) {
      final t = sample['t_ms'];
      if (t is int && t > start && t <= end) unique.putIfAbsent(t, () => sample);
    }
    final times = unique.keys.toList()..sort();
    result['requested_sample_count'] = times.length;
    result['interval_ms'] = [start, end];
    for (final t in times) {
      final probe = SwingModel(
        swingId: swing.swingId, createdAt: swing.createdAt, videoPath: '',
        view: swing.view, handedness: swing.handedness, club: swing.club,
        durationMs: swing.durationMs, fps: swing.fps,
        eventsMs: {'address': start, 'top': t},
      );
      final measured = SwingPatternMeasurementService.measure(
        swing: probe, frames: {'address': address, 'top': unique[t]},
        confirmed: confirmed,
      );
      for (final row in measured['observations'] as List) {
        final key = (row['id'] as String).replaceFirst('_address_to_top', '');
        tracks.putIfAbsent(key, () => []).add({
          't_ms': t, 'segment': t <= top ? 'backswing' : 'downswing',
          'dx': row['dx'], 'dy': row['dy'],
        });
      }
    }
    for (final entry in tracks.entries) {
      for (final segment in ['backswing', 'downswing']) {
        final expected = times.where((t) => segment == 'backswing' ? t <= top : t > top).length;
        final points = entry.value.where((p) => p['segment'] == segment).toList();
        final coverage = expected == 0 ? 0.0 : points.length / expected;
        final summary = <String, dynamic>{
          'landmark_group': entry.key, 'segment': segment,
          'valid_count': points.length, 'expected_count': expected,
          'coverage': coverage, 'status': 'insufficient_samples',
        };
        // Quality heuristics, not golf correctness thresholds.
        if (points.length >= 3 && coverage >= .7) {
          summary['status'] = 'observations_only';
          for (final axis in ['dx', 'dy']) {
            var peak = points.first;
            for (final p in points.skip(1)) {
              if ((p[axis] as num).abs() > (peak[axis] as num).abs()) peak = p;
            }
            summary['${axis}_max_abs_signed'] = peak[axis];
            summary['${axis}_peak_requested_ms'] = peak['t_ms'];
          }
        }
        summaries.add(summary);
      }
    }
    result['status'] = summaries.any((s) => s['status'] == 'observations_only')
        ? 'observations_only' : 'insufficient_samples';
    result['reason'] = null;
    return result;
  }
}
