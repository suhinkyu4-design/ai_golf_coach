import 'metric_model.dart';

class AnalysisResultModel {
  final String analysisId;
  final String swingId;
  final DateTime timestamp;
  final List<MetricModel> metrics;
  final List<String> unavailableMetrics;
  final List<String> allowedObservations;
  final List<String> allowedDrills;
  final String koreanSummary;
  final String primaryDrillTitle;
  final String primaryDrillDescription;
  final String schemaVersion;

  AnalysisResultModel({
    required this.analysisId,
    required this.swingId,
    required this.timestamp,
    required this.metrics,
    required this.unavailableMetrics,
    required this.allowedObservations,
    required this.allowedDrills,
    required this.koreanSummary,
    required this.primaryDrillTitle,
    required this.primaryDrillDescription,
    this.schemaVersion = "0.1",
  });

  Map<String, dynamic> toMap() {
    return {
      'analysis_id': analysisId,
      'swing_id': swingId,
      'timestamp': timestamp.toIso8601String(),
      'metrics': metrics.map((m) => m.toMap()).toList(),
      'unavailable_metrics': unavailableMetrics,
      'allowed_observations': allowedObservations,
      'allowed_drills': allowedDrills,
      'korean_summary': koreanSummary,
      'primary_drill_title': primaryDrillTitle,
      'primary_drill_description': primaryDrillDescription,
      'schema_version': schemaVersion,
    };
  }
}
