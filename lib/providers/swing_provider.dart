import 'package:flutter/foundation.dart';
import '../models/swing_model.dart';
import '../models/shot_measurement_model.dart';
import '../models/analysis_result_model.dart';
import '../services/localization_service.dart';
import '../services/rule_engine.dart';
import '../services/slm_template_service.dart';

class SwingProvider extends ChangeNotifier {
  AppLanguage _appLanguage = AppLanguage.korean;
  SwingModel? _currentSwing;
  ShotMeasurementModel? _currentShotMeasurement;
  AnalysisResultModel? _currentAnalysisResult;
  final List<SwingModel> _swingHistory = [];
  bool _isAnalyzing = false;
  bool _manualEventsConfirmed = false;
  final Map<String, AnalysisResultModel> _results = {};
  final Map<String, ShotMeasurementModel?> _shots = {};
  final Map<String, bool> _confirmedEvents = {};

  void openHistory(SwingModel swing) {
    _currentSwing = swing;
    _currentAnalysisResult = _results[swing.swingId];
    _currentShotMeasurement = _shots[swing.swingId];
    _manualEventsConfirmed = _confirmedEvents[swing.swingId] ?? false;
    notifyListeners();
  }

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
    _manualEventsConfirmed = false;
    _currentShotMeasurement = null;
    _currentAnalysisResult = null;
    _currentSwing = SwingModel(
      swingId: 'swing_${DateTime.now().millisecondsSinceEpoch}',
      createdAt: DateTime.now(),
      videoPath: videoPath,
      view: view,
      handedness: handedness,
      club: club,
      durationMs: 0, // Unknown until the real video is opened.
      fps: 0.0, // Unknown. Do not infer frame rate from playback position.
      eventsMs: {},
    );
    notifyListeners();
  }

  void clearShotMeasurement() {
    _currentShotMeasurement = null;
    _currentAnalysisResult = null;
    notifyListeners();
  }

  void attachShotMeasurement(ShotMeasurementModel measurement) {
    if (measurement.swingId != _currentSwing?.swingId) throw ArgumentError('다른 스윙의 샷 기록입니다.');
    if (measurement.ocrStatus != OcrStatus.userConfirmed) throw ArgumentError('수치를 먼저 확인하세요.');
    _currentShotMeasurement = measurement;
    _currentAnalysisResult = null;
    notifyListeners();
  }

  void updateVideoReview({required int durationMs, required Map<String, int> eventsMs}) {
    final old = _currentSwing;
    if (old == null) throw StateError('No selected swing');
    int previous = -1;
    for (final key in ['address', 'top', 'impact', 'finish']) {
      final value = eventsMs[key];
      if (value == null || value < 0 || value > durationMs || value <= previous) {
        throw ArgumentError('Invalid manual event sequence');
      }
      previous = value;
    }
    _currentSwing = SwingModel(
      swingId: old.swingId, createdAt: old.createdAt, videoPath: old.videoPath,
      view: old.view, handedness: old.handedness, club: old.club,
      durationMs: durationMs, fps: old.fps,
      eventsMs: Map<String, int>.unmodifiable(eventsMs),
    );
    _manualEventsConfirmed = true;
    _currentAnalysisResult = null;
    notifyListeners();
  }

  Future<void> runAnalysis() async {
    final swing = _currentSwing;
    if (swing == null) return;
    final evaluated = RuleEngine.evaluate(
      view: swing.view, handedness: swing.handedness, rawValues: {},
      eventTimestamps: swing.eventsMs, language: _appLanguage,
      manualEventsConfirmed: _manualEventsConfirmed,
    );
    final summary = SlmTemplateService.generateConstrainedSummary(
      allowedObservations: evaluated.allowedObservations,
      allowedDrills: evaluated.allowedDrills,
      metrics: evaluated.evaluatedMetrics,
      shotData: _currentShotMeasurement, language: _appLanguage,
    );
    _currentAnalysisResult = AnalysisResultModel(
      analysisId: 'analysis_${DateTime.now().millisecondsSinceEpoch}',
      swingId: swing.swingId,
      timestamp: DateTime.now(),
      metrics: evaluated.evaluatedMetrics,
      unavailableMetrics: [
        'lead_elbow_at_top', 'spine_tilt_address', 'spine_tilt_top',
        'club_face_angle', 'weight_distribution',
      ],
      allowedObservations: [],
      allowedDrills: [],
      koreanSummary: summary['korean_summary']!,
      primaryDrillTitle: summary['primary_drill_title']!,
      primaryDrillDescription: summary['primary_drill_description']!,
    );
    _results[swing.swingId] = _currentAnalysisResult!;
    _shots[swing.swingId] = _currentShotMeasurement;
    _confirmedEvents[swing.swingId] = _manualEventsConfirmed;
    final index = _swingHistory.indexWhere((s) => s.swingId == swing.swingId);
    if (index < 0) { _swingHistory.add(swing); } else { _swingHistory[index] = swing; }
    _isAnalyzing = false;
    notifyListeners();
  }
}
