import 'package:flutter/foundation.dart';
import '../models/swing_model.dart';
import '../models/shot_measurement_model.dart';
import '../models/analysis_result_model.dart';
import '../services/rule_engine.dart';
import '../services/slm_template_service.dart';
import '../services/localization_service.dart';

class SwingProvider extends ChangeNotifier {
  AppLanguage _appLanguage = AppLanguage.korean;
  SwingModel? _currentSwing;
  ShotMeasurementModel? _currentShotMeasurement;
  AnalysisResultModel? _currentAnalysisResult;
  final List<SwingModel> _swingHistory = [];
  bool _isAnalyzing = false;

  AppLanguage get appLanguage => _appLanguage;
  SwingModel? get currentSwing => _currentSwing;
  ShotMeasurementModel? get currentShotMeasurement => _currentShotMeasurement;
  AnalysisResultModel? get currentAnalysisResult => _currentAnalysisResult;
  List<SwingModel> get swingHistory => _swingHistory;
  bool get isAnalyzing => _isAnalyzing;

  void toggleLanguage() {
    _appLanguage = _appLanguage == AppLanguage.korean ? AppLanguage.english : AppLanguage.korean;
    // Re-run summary text update if an analysis result exists
    if (_currentAnalysisResult != null && _currentSwing != null) {
      runAnalysis();
    } else {
      notifyListeners();
    }
  }

  void createNewSwing({
    required String videoPath,
    required SwingView view,
    required Handedness handedness,
    required String club,
  }) {
    _currentSwing = SwingModel(
      swingId: 'swing_${DateTime.now().millisecondsSinceEpoch}',
      createdAt: DateTime.now(),
      videoPath: videoPath,
      view: view,
      handedness: handedness,
      club: club,
      durationMs: 3000,
      fps: 60.0,
      eventsMs: {
        'address': 200,
        'top': 1200,
        'impact': 1510,
        'finish': 2800,
      },
    );
    notifyListeners();
  }

  void attachShotMeasurement(ShotMeasurementModel measurement) {
    _currentShotMeasurement = measurement;
    notifyListeners();
  }

  Future<void> runAnalysis() async {
    if (_currentSwing == null) return;
    _isAnalyzing = true;
    notifyListeners();

    // Mock pose calculation values for demo pipeline
    final Map<String, double> rawValues = {
      'lead_elbow_at_top': 135.0, // Bent lead elbow demo
      'spine_tilt_address': 25.0,
      'spine_tilt_top': 38.0, // 13 deg change demo
    };

    final ruleResult = RuleEngine.evaluate(
      view: _currentSwing!.view,
      handedness: _currentSwing!.handedness,
      rawValues: rawValues,
      eventTimestamps: _currentSwing!.eventsMs,
      language: _appLanguage,
    );

    final summary = SlmTemplateService.generateConstrainedSummary(
      allowedObservations: ruleResult.allowedObservations,
      allowedDrills: ruleResult.allowedDrills,
      metrics: ruleResult.evaluatedMetrics,
      shotData: _currentShotMeasurement,
      language: _appLanguage,
    );

    _currentAnalysisResult = AnalysisResultModel(
      analysisId: 'analysis_${DateTime.now().millisecondsSinceEpoch}',
      swingId: _currentSwing!.swingId,
      timestamp: DateTime.now(),
      metrics: ruleResult.evaluatedMetrics,
      unavailableMetrics: ['club_face_angle', 'weight_distribution'],
      allowedObservations: ruleResult.allowedObservations,
      allowedDrills: ruleResult.allowedDrills,
      koreanSummary: summary['korean_summary']!,
      primaryDrillTitle: summary['primary_drill_title']!,
      primaryDrillDescription: summary['primary_drill_description']!,
    );

    if (!_swingHistory.contains(_currentSwing!)) {
      _swingHistory.add(_currentSwing!);
    }

    _isAnalyzing = false;
    notifyListeners();
  }
}
