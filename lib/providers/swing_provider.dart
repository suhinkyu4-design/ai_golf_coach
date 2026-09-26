import '../services/assistant_operation_log.dart';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import '../models/swing_model.dart';
import '../models/shot_measurement_model.dart';
import '../services/shot_insight_service.dart';
import '../models/analysis_result_model.dart';
import '../services/localization_service.dart';
import '../services/rule_engine.dart';
import '../services/gallery_pose_service.dart';
import '../services/pose_measurement_service.dart';
import '../services/swing_trajectory_service.dart';
import '../services/swing_fault_features.dart';
import '../services/coaching_dataset_service.dart';
import '../services/evidence_coaching_service.dart';
import '../services/final_comment_service.dart';

class SwingProvider extends ChangeNotifier {
  AppLanguage _appLanguage = AppLanguage.korean;
  bool _enableOcrStep = false;
  bool _enableAdvancedTrimming = false;
  SwingModel? _currentSwing;
  ShotMeasurementModel? _currentShotMeasurement;
  AnalysisResultModel? _currentAnalysisResult;
  final List<SwingModel> _swingHistory = [];
  bool _isAnalyzing = false;
  bool _manualEventsConfirmed = false;
  final Map<String, AnalysisResultModel> _results = {};
  final Map<String, ShotMeasurementModel?> _shots = {};
  final Map<String, bool> _confirmedEvents = {};
  final Map<String, Map<String, dynamic>> _poseReports = {};
  final Map<String, Map<String, dynamic>> _slmComments = {};
  Map<String, dynamic>? get currentSlmComment => _slmComments[_currentSwing?.swingId];

  Map<String, dynamic>? get currentCoachingContext {
    final swing = _currentSwing;
    final report = currentPoseReport;
    if (swing == null || report == null) return null;
    return EvidenceCoachingService.build(swing, report,
        eventsConfirmed: _manualEventsConfirmed);
  }

  Map<String, dynamic>? get currentPoseReport =>
      _poseReports[_currentSwing?.swingId];
  Map<String, dynamic>? get currentDatasetDraft {
    final swing = _currentSwing;
    final report = currentPoseReport;
    if (swing == null || report == null) return null;
    final draft = CoachingDatasetService.draft(swing, report,
        eventsConfirmed: _manualEventsConfirmed);
    final result = _currentAnalysisResult;
    if (result != null) {
      draft['final_comment'] = FinalCommentService.build(
          metrics: result.metrics,
          poseReport: report,
          coaching: currentCoachingContext!);
      if (currentSlmComment != null) draft['on_device_description'] = currentSlmComment;
      draft['final_comment']['slm_request']['capture_context'] = {
        'view': swing.view.name, 'handedness': swing.handedness.name,
        'club': swing.club, 'events_user_confirmed': _manualEventsConfirmed,
      };
    }
    return draft;
  }

  void openHistory(SwingModel swing) {
    _currentSwing = swing;
    _currentAnalysisResult = _results[swing.swingId];
    _currentShotMeasurement = _shots[swing.swingId];
    _manualEventsConfirmed = _confirmedEvents[swing.swingId] ?? false;
    notifyListeners();
  }

  AppLanguage get appLanguage => _appLanguage;
  bool get enableOcrStep => _enableOcrStep;
  bool get enableAdvancedTrimming => _enableAdvancedTrimming;
  SwingModel? get currentSwing => _currentSwing;
  ShotMeasurementModel? get currentShotMeasurement => _currentShotMeasurement;
  AnalysisResultModel? get currentAnalysisResult => _currentAnalysisResult;
  List<SwingModel> get swingHistory => _swingHistory;
  bool get isAnalyzing => _isAnalyzing;

  void setEnableOcrStep(bool value) {
    _enableOcrStep = value;
    notifyListeners();
  }

  void setEnableAdvancedTrimming(bool value) {
    _enableAdvancedTrimming = value;
    notifyListeners();
  }

  void toggleLanguage() {
    _appLanguage = _appLanguage == AppLanguage.korean
        ? AppLanguage.english
        : AppLanguage.korean;
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
    if (measurement.swingId != _currentSwing?.swingId)
      throw ArgumentError('다른 스윙의 샷 기록입니다.');
    if (measurement.ocrStatus != OcrStatus.userConfirmed)
      throw ArgumentError('수치를 먼저 확인하세요.');
    _currentShotMeasurement = measurement;
    _currentAnalysisResult = null;
    notifyListeners();
  }

  void updateVideoReview(
      {required int durationMs, required Map<String, int> eventsMs}) {
    final old = _currentSwing;
    if (old == null) throw StateError('No selected swing');
    int previous = -1;
    for (final key in ['address', 'top', 'impact', 'finish']) {
      final value = eventsMs[key];
      if (value == null ||
          value < 0 ||
          value > durationMs ||
          value <= previous) {
        throw ArgumentError('Invalid manual event sequence');
      }
      previous = value;
    }
    _currentSwing = SwingModel(
      swingId: old.swingId,
      createdAt: old.createdAt,
      videoPath: old.videoPath,
      view: old.view,
      handedness: old.handedness,
      club: old.club,
      durationMs: durationMs,
      fps: old.fps,
      eventsMs: Map<String, int>.unmodifiable(eventsMs),
    );
    _manualEventsConfirmed = true;
    _poseReports.remove(old.swingId);
    _slmComments.remove(old.swingId);
    _currentAnalysisResult = null;
    notifyListeners();
  }

  /// Directions refer to the displayed video, including mirrored clips.
  void setBallImageDirection(int direction) => _setMotionDirections(ballDirection: direction);
  void setTargetImageDirection(int direction) => _setMotionDirections(targetDirection: direction);
  void _setMotionDirections({int? ballDirection, int? targetDirection}) {
    if ((ballDirection != null && ![-1, 1].contains(ballDirection)) ||
        (targetDirection != null && ![-1, 1].contains(targetDirection))) return;
    final swing = _currentSwing;
    final report = currentPoseReport;
    final evidence = report?['motion_evidence'];
    if (swing == null || report == null || evidence is! Map) return;
    final previous = report['fault_features'] as Map?;
    final explicitTarget = previous?['target_direction_basis'] == 'supplied'
        ? (previous?['target_image_sign'] as int?) : null;
    report['fault_features'] = SwingFaultFeatures.analyze(
      swing: swing, reviewed: Map<String, dynamic>.from(evidence['reviewed'] as Map),
      samples: (evidence['samples'] as List).map((f) => Map<String, dynamic>.from(f as Map)).toList(),
      confirmed: _manualEventsConfirmed,
      ballImageSign: ballDirection ?? (previous?['ball_direction_basis'] == 'supplied'
          ? (previous?['ball_image_sign'] as int?) : null),
      targetImageSign: targetDirection ?? explicitTarget);
    notifyListeners();
  }

  Future<void> runAnalysis({void Function(int step, String message)? onProgress}) async {
    final swing = _currentSwing;
    if (swing == null || _isAnalyzing) return;
    final confirmed = _manualEventsConfirmed;
    _isAnalyzing = true;
    notifyListeners();
    try {
      onProgress?.call(2, '어드레스·백스윙 탑·임팩트·피니시 자세를 확인하고 있습니다.');
      var report = _poseReports[swing.swingId];
      if (report == null) {
        Map<String, dynamic> frames = {};
        if (confirmed) {
          try {
            frames = await GalleryPoseService.measureReviewedFrames(
                swing.videoPath, swing.eventsMs, onProgress: (message)=>onProgress?.call(2,message));
          } catch (error) {
            AssistantOperationLog.current.note('자세별 관절 측정', '대체 처리', '선택 시점의 관절 재측정에 실패하여 확보된 기록으로 분석을 이어갑니다.');
            debugPrint('Pose measurement unavailable: $error');
          }
        }
        report = PoseMeasurementService.measure(
            swing: swing, frames: frames, confirmed: confirmed);
        if (!identical(_currentSwing, swing)) return;
        var motionSamples = <Map<String, dynamic>>[];
        final start = swing.eventsMs['address'];
        final end = swing.eventsMs['impact'];
        if (confirmed && start != null && end != null && end > start &&
            ['driver', '7i', 'unknown'].contains(swing.club.toLowerCase())) {
          try {
            final samples = await GalleryPoseService.measureTrajectoryFrames(
                swing.videoPath, start, end, topMs: swing.eventsMs['top'],
                finishMs: swing.eventsMs['finish'],
                leadSide: swing.handedness == Handedness.right ? 'left' : 'right',
                onProgress: (message)=>onProgress?.call(3,message));
            motionSamples = samples;
            report['trajectory'] = SwingTrajectoryService.measure(
                swing: swing, address: frames['address'], samples: samples,
                confirmed: confirmed);
          } catch (error) {
            AssistantOperationLog.current.note('동작 궤적', '경고', '연속 장면 추출 또는 궤적 측정이 실패했습니다. 연속 움직임을 요구하는 판정은 제한됩니다.');
            report['trajectory'] = {'status': 'unavailable', 'reason': 'extraction_failed'};
            debugPrint('Trajectory measurement unavailable: $error');
          }
        }
        report['motion_evidence'] = {'reviewed': frames, 'samples': motionSamples};
        onProgress?.call(3, '스웨이·상체 들림·배치기·치킨윙·헤드업을 검사하고 있습니다.');
        await Future<void>.delayed(Duration.zero);
        report['fault_features'] = SwingFaultFeatures.analyze(swing: swing,
            reviewed: frames, samples: motionSamples, confirmed: confirmed);
        // A different review or swing may have been selected during native processing.
        if (!identical(_currentSwing, swing)) return;
        AssistantOperationLog.current.reportFaults(report['fault_features'] as Map);
        _poseReports[swing.swingId] = report;
        try {
          await File('${swing.videoPath}.analysis.json').writeAsString(jsonEncode({
            'schema_version': 'motion_diagnostics_1',
            'club': swing.club, 'view': swing.view.name, 'events_ms': swing.eventsMs,
            'continuous_sample_count': motionSamples.length,
            'trajectory_status': report['trajectory']?['status'],
            'fault_features': report['fault_features'],
          }), flush: true);
        } catch (error) { debugPrint('Motion diagnostics save failed: $error'); }
        if (!identical(_currentSwing, swing)) return;
      }
      onProgress?.call(4, '측정값과 자세 분석 결과를 정리하고 있습니다.');
      final evaluated = RuleEngine.evaluate(
        view: swing.view,
        handedness: swing.handedness,
        rawValues: {},
        eventTimestamps: swing.eventsMs,
        language: _appLanguage,
        manualEventsConfirmed: _manualEventsConfirmed,
      );
      final metrics = [
        ...evaluated.evaluatedMetrics,
        ...PoseMeasurementService.displayMetrics(report)
      ];
      final coaching = EvidenceCoachingService.build(swing, report,
          eventsConfirmed: confirmed);
      final comment = FinalCommentService.build(
          metrics: metrics, poseReport: report, coaching: coaching);
      // SLM is deferred until motion detection is validated.
      _slmComments.remove(swing.swingId);
      _currentAnalysisResult = AnalysisResultModel(
        analysisId: 'analysis_${DateTime.now().millisecondsSinceEpoch}',
        swingId: swing.swingId,
        timestamp: DateTime.now(),
        metrics: metrics,
        unavailableMetrics: [
          for (final row in report['metrics'] as List)
            if (row['status'] == 'unavailable') row['id'] as String,
          'club_face_angle',
          'weight_distribution',
        ],
        allowedObservations: [
          for (final fact in coaching['facts'] as List) fact['text'] as String,
          ...ShotInsightService.describe(_currentShotMeasurement, swingId: swing.swingId).map((text) => _currentShotMeasurement!.isTestData ? '[테스트 예시] $text' : text)
        ],
        allowedDrills: [],
        koreanSummary: comment['comment'] as String,
        primaryDrillTitle: comment['practice_title'] as String,
        primaryDrillDescription: comment['practice'] as String,
      );
      _results[swing.swingId] = _currentAnalysisResult!;
      _shots[swing.swingId] = _currentShotMeasurement;
      _confirmedEvents[swing.swingId] = _manualEventsConfirmed;
      final index = _swingHistory.indexWhere((s) => s.swingId == swing.swingId);
      if (index < 0) {
        _swingHistory.add(swing);
      } else {
        _swingHistory[index] = swing;
      }
      AssistantOperationLog.current.success('analysis');
    } catch (e) {
      AssistantOperationLog.current.fail('analysis', e);
      rethrow;
    } finally {
      _isAnalyzing = false;
      notifyListeners();
    }
  }
}
