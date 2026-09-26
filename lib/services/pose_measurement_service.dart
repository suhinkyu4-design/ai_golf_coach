import 'dart:math' as math;
import '../models/metric_model.dart';
import 'swing_pattern_measurement_service.dart';
import '../models/swing_model.dart';

/// Descriptive image-plane measurements, never normative golf assessments.
class PoseMeasurementService {
  static const version = 'pose_metrics_1.0';
  static const minLikelihood = 0.7;
  static const phases = ['address', 'top', 'impact', 'finish'];

  static Map<String, dynamic> measure({
    required SwingModel swing,
    required Map<String, dynamic> frames,
    required bool confirmed,
  }) {
    final rows = <Map<String, dynamic>>[];
    final lead = swing.handedness == Handedness.right ? 'left' : 'right';
    final trail = lead == 'left' ? 'right' : 'left';
    for (final phase in phases) {
      final frame = frames[phase] as Map?;
      final w = (frame?['width'] as num?)?.toDouble() ?? 0;
      final h = (frame?['height'] as num?)?.toDouble() ?? 0;
      final joints = <String, Map>{};
      for (final p in (frame?['landmarks'] as List? ?? [])) {
        if (p is Map && p['name'] is String) joints[p['name']] = p;
      }
      final definitions = <String, List<String>>{
        'lead_elbow': ['${lead}Shoulder', '${lead}Elbow', '${lead}Wrist'],
        'trail_elbow': ['${trail}Shoulder', '${trail}Elbow', '${trail}Wrist'],
        'lead_knee': ['${lead}Hip', '${lead}Knee', '${lead}Ankle'],
        'trail_knee': ['${trail}Hip', '${trail}Knee', '${trail}Ankle'],
        'torso_tilt': ['leftShoulder', 'rightShoulder', 'leftHip', 'rightHip'],
      };
      for (final entry in definitions.entries) {
        String? reason;
        double? value;
        double? confidence;
        final points = <math.Point<double>>[];
        if (!confirmed) {
          reason = 'events_not_confirmed';
        } else if (swing.view == SwingView.unknown) {
          reason = 'unknown_view';
        } else if (frame == null) {
          reason = 'frame_unavailable';
          // The exclusive video endpoint is decoded at duration - 1 ms.
          // Keep both requested and extraction times in the exported evidence.
        } else if (frame['t_ms'] != swing.eventsMs[phase] &&
            !(swing.eventsMs[phase] == swing.durationMs &&
                frame['t_ms'] == swing.durationMs - 1)) {
          reason = 'requested_time_mismatch';
        } else if (!w.isFinite || !h.isFinite || w <= 0 || h <= 0) {
          reason = 'invalid_image_size';
        } else {
          for (final name in entry.value) {
            final p = joints[name];
            final x = (p?['x'] as num?)?.toDouble();
            final y = (p?['y'] as num?)?.toDouble();
            final likelihood = (p?['likelihood'] as num?)?.toDouble();
            if (x == null ||
                y == null ||
                likelihood == null ||
                !x.isFinite ||
                !y.isFinite ||
                !likelihood.isFinite) {
              reason = 'missing_or_invalid_joint';
              break;
            }
            confidence = math.min(confidence ?? 1, likelihood);
            if (likelihood < minLikelihood || likelihood > 1) {
              reason = 'low_joint_likelihood';
              break;
            }
            if (x < 0 || y < 0 || x >= w || y >= h) {
              reason = 'joint_outside_image';
              break;
            }
            points.add(math.Point(x, y));
          }
          if (reason == null) {
            // Reject numerically unstable angles from severely foreshortened limbs.
            final minLength = math.sqrt(w * w + h * h) * 0.01;
            if (entry.key == 'torso_tilt') {
              final shoulder = (points[0] + points[1]) * 0.5;
              final hip = (points[2] + points[3]) * 0.5;
              final vector = shoulder - hip;
              if (vector.magnitude < minLength) {
                reason = 'degenerate_segment';
              } else {
                value = math.atan2(vector.x, -vector.y) * 180 / math.pi;
              }
            } else {
              final u = points[0] - points[1];
              final v = points[2] - points[1];
              if (u.magnitude < minLength || v.magnitude < minLength) {
                reason = 'degenerate_segment';
              } else {
                value = math.acos(
                        ((u.x * v.x + u.y * v.y) / (u.magnitude * v.magnitude))
                            .clamp(-1.0, 1.0)) *
                    180 /
                    math.pi;
              }
            }
          }
        }
        rows.add({
          'id': '${entry.key}_projected_at_$phase',
          'phase': phase,
          'kind': entry.key,
          'value':
              value == null ? null : double.parse(value.toStringAsFixed(2)),
          'unit': 'deg',
          'status': reason == null ? 'estimated' : 'unavailable',
          'reason': reason,
          'min_joint_likelihood': confidence,
          'joint_names': entry.value,
          'requested_t_ms': swing.eventsMs[phase],
          'sample_t_ms': frame?['t_ms'],
          'actual_video_pts_ms': null,
          'coordinate_space': 'upright_image_pixels',
        });
      }
    }
    return {
      'measurement_version': version,
      'pattern_observations': SwingPatternMeasurementService.measure(
          swing: swing, frames: frames, confirmed: confirmed),
      'timestamp_basis': 'requested_closest_frame_ms',
      'video_pts_synchronized': false,
      'minimum_joint_likelihood': minLikelihood,
      'minimum_segment_image_diagonal_ratio': 0.01,
      'thresholds_are_quality_heuristics': true,
      'interpretation': '2d_projection_only_no_normative_assessment',
      'metrics': rows,
    };
  }

  static List<MetricModel> displayMetrics(Map<String, dynamic> report) {
    const labels = {
      'lead_elbow': '리드 팔꿈치',
      'trail_elbow': '트레일 팔꿈치',
      'lead_knee': '리드 무릎',
      'trail_knee': '트레일 무릎',
      'torso_tilt': '몸통 기울기'
    };
    const phaseNames = {
      'address': '어드레스',
      'top': '탑',
      'impact': '임팩트',
      'finish': '피니시'
    };
    return (report['metrics'] as List)
        .cast<Map>()
        .where((r) => r['value'] != null)
        .map((r) => MetricModel(
              id: r['id'] as String,
              name: '${phaseNames[r['phase']]} · ${labels[r['kind']]} (2D)',
              value: (r['value'] as num).toDouble(),
              unit: 'deg',
              status: MetricStatus.estimated,
              evidenceTimeMs: [r['requested_t_ms'] as int],
            ))
        .toList();
  }
}
