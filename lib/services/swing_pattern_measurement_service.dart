import 'dart:math' as math;
import '../models/swing_model.dart';

/// Keyframe observations only. No fault labels or uncalibrated centimetres.
class SwingPatternMeasurementService {
  static Map<String, dynamic> measure({
    required SwingModel swing,
    required Map<String, dynamic> frames,
    required bool confirmed,
  }) {
    final club = swing.club.toLowerCase();
    final supported = club == 'driver' || club == '7i' || club == 'unknown';
    final rows = <Map<String, dynamic>>[];
    final result = <String, dynamic>{
      'version': 'pattern_observations_1.0',
      'club': supported ? club : null,
      'status': 'unavailable',
      'reason': !supported ? 'unsupported_club' : 'insufficient_frames',
      'sampling': 'reviewed_keyframes_only_not_continuous_trajectory',
      'unit': 'ratio_of_address_projected_torso_length',
      'axes': 'image_right_positive_image_down_positive',
      'camera_motion_compensated': false,
      'requires_fixed_camera': true,
      'diagnosis_available': false,
      'reference_profile_status': 'not_validated',
      'observations': rows,
    };
    if (!supported) return result;
    if (!confirmed || swing.view == SwingView.unknown) {
      result['reason'] = !confirmed ? 'events_not_confirmed' : 'unknown_view';
      return result;
    }
    Map? validFrame(String phase) {
      final f = frames[phase];
      final t = swing.eventsMs[phase];
      if (f is! Map || t == null) return null;
      if (f['t_ms'] != t &&
          !(t == swing.durationMs && f['t_ms'] == t - 1)) return null;
      for (final key in ['width', 'height']) {
        final n = f[key];
        if (n is! num || !n.isFinite || n <= 0) return null;
      }
      return f;
    }

    math.Point<double>? center(Map f, List<String> names) {
      final landmarks = f['landmarks'];
      if (landmarks is! List) return null;
      var sum = const math.Point<double>(0, 0);
      for (final name in names) {
        final matches = landmarks.whereType<Map>().where((p) => p['name'] == name);
        if (matches.length != 1) return null;
        final p = matches.single;
        final x = p['x'], y = p['y'], c = p['likelihood'];
        if (x is! num || y is! num || c is! num ||
            !x.isFinite || !y.isFinite || !c.isFinite || c < .7 || c > 1 ||
            x < 0 || y < 0 || x >= f['width'] || y >= f['height']) return null;
        sum += math.Point(x.toDouble(), y.toDouble());
      }
      return sum * (1 / names.length);
    }

    const shoulders = ['leftShoulder', 'rightShoulder'];
    const hips = ['leftHip', 'rightHip'];
    final address = validFrame('address');
    if (address == null) return result;
    final shoulder = center(address, shoulders), hip = center(address, hips);
    if (shoulder == null || hip == null) return result;
    final length = (shoulder - hip).magnitude;
    final w = (address['width'] as num).toDouble();
    final h = (address['height'] as num).toDouble();
    if (length < math.sqrt(w * w + h * h) * .01) return result;
    for (final phase in ['top', 'impact', 'finish']) {
      final frame = validFrame(phase);
      if (frame == null || frame['width'] != w || frame['height'] != h ||
          swing.eventsMs[phase]! <= swing.eventsMs['address']!) continue;
      for (final entry in {
        'head_eye_midpoint': ['leftEye', 'rightEye'],
        'pelvis_midpoint': hips,
        'shoulder_midpoint': shoulders,
      }.entries) {
        final start = center(address, entry.value), end = center(frame, entry.value);
        if (start == null || end == null) continue;
        rows.add({
          'id': '${entry.key}_address_to_$phase',
          'from_phase': 'address', 'to_phase': phase,
          'joint_names': entry.value,
          'dx': (end.x - start.x) / length,
          'dy': (end.y - start.y) / length,
          'requested_times_ms': [swing.eventsMs['address'], swing.eventsMs[phase]],
          'minimum_joint_likelihood_required': .7,
        });
      }
    }
    if (rows.isNotEmpty) {
      result['status'] = 'observations_only';
      result['reason'] = null;
    }
    return result;
  }
}
