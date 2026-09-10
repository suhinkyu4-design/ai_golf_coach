import '../models/metric_model.dart';
import '../models/swing_model.dart';
import 'localization_service.dart';

class RuleEvaluationResult {
  final List<String> allowedObservations;
  final List<String> allowedDrills;
  final List<MetricModel> evaluatedMetrics;

  RuleEvaluationResult({
    required this.allowedObservations,
    required this.allowedDrills,
    required this.evaluatedMetrics,
  });
}

class RuleEngine {
  /// Evaluates measured raw metrics against deterministic rules
  static RuleEvaluationResult evaluate({
    required SwingView view,
    required Handedness handedness,
    required Map<String, double> rawValues,
    required Map<String, int> eventTimestamps,
    AppLanguage language = AppLanguage.korean,
  }) {
    final bool isEn = language == AppLanguage.english;
    final List<MetricModel> metrics = [];
    final List<String> observations = [];
    final List<String> drills = [];

    // 1. Lead Elbow Angle at Top Evaluation
    final double? leadElbowTop = rawValues['lead_elbow_at_top'];
    if (leadElbowTop != null) {
      final isBent = leadElbowTop < 140.0;
      metrics.add(MetricModel(
        id: 'lead_elbow_projected_at_top',
        name: isEn ? 'Lead Elbow Flexion at Top' : '탑 위치 리드 팔 굽힘각',
        value: double.parse(leadElbowTop.toStringAsFixed(1)),
        unit: 'deg',
        status: MetricStatus.usable,
        evidenceTimeMs: [eventTimestamps['top'] ?? 0],
      ));

      if (isBent) {
        observations.add('OBS_LEAD_ELBOW_BENT_AT_TOP');
        drills.add('DRILL_WIDE_BACKSWING_ARC');
      }
    }

    // 2. Tempo Ratio Evaluation (Backswing / Downswing)
    final int? addressT = eventTimestamps['address'];
    final int? topT = eventTimestamps['top'];
    final int? impactT = eventTimestamps['impact'];

    if (topT != null && impactT != null && addressT != null && (impactT > topT) && (topT > addressT)) {
      final double backswingTimeMs = (topT - addressT).toDouble();
      final double downswingTimeMs = (impactT - topT).toDouble();
      final double tempoRatio = double.parse((backswingTimeMs / downswingTimeMs).toStringAsFixed(2));

      metrics.add(MetricModel(
        id: 'swing_tempo_ratio',
        name: isEn ? 'Swing Tempo Ratio (Backswing/Downswing)' : '스윙 템포 비율 (백스윙/다운스윙)',
        value: tempoRatio,
        unit: 'ratio',
        status: MetricStatus.usable,
        evidenceTimeMs: [addressT, topT, impactT],
      ));

      if (tempoRatio < 2.5) {
        observations.add('OBS_QUICK_DOWNSWING_TEMPO');
        drills.add('DRILL_PAUSE_AT_TOP');
      } else if (tempoRatio > 3.5) {
        observations.add('OBS_SLOW_BACKSWING_TEMPO');
      }
    }

    // 3. Upper Body Tilt Evaluation (Rear view)
    final double? spineTiltAddress = rawValues['spine_tilt_address'];
    final double? spineTiltTop = rawValues['spine_tilt_top'];
    if (view == SwingView.rear && spineTiltAddress != null && spineTiltTop != null) {
      final double tiltDiff = (spineTiltTop - spineTiltAddress).abs();
      metrics.add(MetricModel(
        id: 'upper_body_tilt_change',
        name: isEn ? 'Spine Tilt Change' : '상체 기울기 변화량',
        value: double.parse(tiltDiff.toStringAsFixed(1)),
        unit: 'deg',
        status: MetricStatus.usable,
        evidenceTimeMs: [eventTimestamps['top'] ?? 0],
      ));

      if (tiltDiff > 12.0) {
        observations.add('OBS_EARLY_EXTENSION_RISING');
        drills.add('DRILL_POSTURE_WALL_DRILL');
      }
    }

    return RuleEvaluationResult(
      allowedObservations: observations,
      allowedDrills: drills,
      evaluatedMetrics: metrics,
    );
  }
}
