import '../models/metric_model.dart';
import '../models/swing_model.dart';
import 'localization_service.dart';

class RuleEvaluationResult {
  final List<String> allowedObservations;
  final List<String> allowedDrills;
  final List<MetricModel> evaluatedMetrics;
  RuleEvaluationResult({required this.allowedObservations,
    required this.allowedDrills, required this.evaluatedMetrics});
}

class RuleEngine {
  /// Only descriptive timing metrics from user-confirmed video positions.
  /// Raw angles remain disabled until frame alignment and provenance exist.
  static RuleEvaluationResult evaluate({
    required SwingView view,
    required Handedness handedness,
    required Map<String, double> rawValues,
    required Map<String, int> eventTimestamps,
    AppLanguage language = AppLanguage.korean,
    bool manualEventsConfirmed = false,
  }) {
    final metrics = <MetricModel>[];
    final isEn = language == AppLanguage.english;
    final address = eventTimestamps['address'];
    final top = eventTimestamps['top'];
    final impact = eventTimestamps['impact'];
    if (manualEventsConfirmed && address != null && address >= 0 &&
        top != null && impact != null && top > address && impact > top) {
      final beforeTop = (top - address).toDouble();
      final afterTop = (impact - top).toDouble();
      metrics.add(MetricModel(
        id: 'address_to_top_duration',
        name: isEn ? 'Address to top (manual estimate)' : '어드레스→탑 시간 (수동 추정)',
        value: beforeTop, unit: 'ms', status: MetricStatus.estimated,
        evidenceTimeMs: [address, top],
      ));
      metrics.add(MetricModel(
        id: 'top_to_impact_duration',
        name: isEn ? 'Top to impact (manual estimate)' : '탑→임팩트 시간 (수동 추정)',
        value: afterTop, unit: 'ms', status: MetricStatus.estimated,
        evidenceTimeMs: [top, impact],
      ));
      metrics.add(MetricModel(
        id: 'swing_tempo_ratio',
        name: isEn ? 'Address-to-top / top-to-impact (manual)' : '어드레스→탑 / 탑→임팩트 비율 (수동)',
        value: double.parse((beforeTop / afterTop).toStringAsFixed(2)),
        unit: 'ratio', status: MetricStatus.estimated,
        evidenceTimeMs: [address, top, impact],
      ));
    }
    // An address timestamp can precede actual movement. Do not label this
    // a precise backswing ratio or infer rushed downswing / corrective drills.
    return RuleEvaluationResult(allowedObservations: [], allowedDrills: [],
      evaluatedMetrics: metrics);
  }
}
