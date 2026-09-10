import 'package:flutter_test/flutter_test.dart';
import '../lib/models/swing_model.dart';
import '../lib/services/rule_engine.dart';
import '../lib/services/slm_template_service.dart';

void main() {
  test('Unconfirmed legacy timestamps and sample angles yield no metrics', () {
    final result = RuleEngine.evaluate(view: SwingView.rear,
      handedness: Handedness.right,
      rawValues: {'lead_elbow_at_top': 135, 'spine_tilt_address': 25, 'spine_tilt_top': 38},
      eventTimestamps: {'address': 200, 'top': 1200, 'impact': 1510});
    expect(result.evaluatedMetrics, isEmpty);
    expect(result.allowedObservations, isEmpty);
    expect(result.allowedDrills, isEmpty);
  });

  test('Confirmed zero-start events produce timing without posture diagnosis', () {
    final result = RuleEngine.evaluate(view: SwingView.faceOn,
      handedness: Handedness.left, rawValues: {}, manualEventsConfirmed: true,
      eventTimestamps: {'address': 0, 'top': 1000, 'impact': 1250});
    expect(result.evaluatedMetrics.map((m) => m.value).toList(), [1000.0, 250.0, 4.0]);
    expect(result.allowedObservations, isEmpty);
    expect(result.allowedDrills, isEmpty);
    final summary = SlmTemplateService.generateConstrainedSummary(
      allowedObservations: [], allowedDrills: [], metrics: result.evaluatedMetrics);
    expect(summary['korean_summary'], contains('4.00'));
    expect(summary['korean_summary'], contains('대기 시간'));
  });

  test('Invalid ordering and negative times do not produce timing', () {
    for (final events in [
      {'address': 0, 'top': 1000, 'impact': 1000},
      {'address': -1, 'top': 1000, 'impact': 1250},
      {'address': 1000, 'top': 500, 'impact': 1250},
      <String, int>{},
    ]) {
      final result = RuleEngine.evaluate(view: SwingView.unknown,
        handedness: Handedness.right, rawValues: {}, manualEventsConfirmed: true,
        eventTimestamps: events);
      expect(result.evaluatedMetrics, isEmpty);
    }
  });

  test('No evidence must not produce a positive assessment or exercise', () {
    final summary = SlmTemplateService.generateConstrainedSummary(
      allowedObservations: ['OBS_EARLY_EXTENSION_RISING'],
      allowedDrills: ['DRILL_POSTURE_WALL_DRILL'], metrics: []);
    expect(summary['korean_summary'], contains('확인된 시간 측정값이 없습니다'));
    expect(summary['primary_drill_title'], '자세 분석 대기');
    expect(summary['primary_drill_description'], isNot(contains('벽')));
  });
}
