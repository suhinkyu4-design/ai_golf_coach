import '../models/metric_model.dart';
import '../models/shot_measurement_model.dart';
import 'localization_service.dart';

/// Deterministic text formatting only; no SLM is loaded or executed.
/// Keep the existing class/API name for caller compatibility.
class SlmTemplateService {
  static Map<String, String> generateConstrainedSummary({
    required List<String> allowedObservations,
    required List<String> allowedDrills,
    required List<MetricModel> metrics,
    ShotMeasurementModel? shotData,
    AppLanguage language = AppLanguage.korean,
  }) {
    final isEn = language == AppLanguage.english;
    final lines = <String>[];
    const supported = {
      'address_to_top_duration', 'top_to_impact_duration', 'swing_tempo_ratio',
    };
    for (final metric in metrics) {
      if (!supported.contains(metric.id) || metric.status == MetricStatus.unavailable ||
          !metric.value.isFinite || metric.value <= 0) continue;
      final String label;
      if (metric.id == 'address_to_top_duration') {
        label = isEn ? 'Address to top' : '어드레스→탑';
      } else if (metric.id == 'top_to_impact_duration') {
        label = isEn ? 'Top to impact' : '탑→임팩트';
      } else {
        label = isEn ? 'Time ratio' : '시간 비율';
      }
      lines.add('$label: ${metric.value.toStringAsFixed(metric.unit == 'ms' ? 0 : 2)} ${metric.unit}');
    }
    if (lines.isEmpty) {
      lines.add(isEn ? 'No confirmed timing measurements are available.' : '확인된 시간 측정값이 없습니다.');
    } else {
      lines.add(isEn
        ? 'These estimates use manually selected video positions. Address-to-top time may include waiting before the swing starts.'
        : '사용자가 영상에서 지정한 시각으로 계산한 추정치입니다. 어드레스→탑 시간에는 스윙 시작 전 대기 시간이 포함될 수 있습니다.');
    }
    lines.add(isEn
      ? 'Posture angles have not been measured. No stable-posture assessment or corrective drill is generated.'
      : '자세 각도는 아직 측정하지 않았습니다. 안정적인 자세 판정이나 교정 동작 추천은 생성하지 않습니다.');
    if (shotData != null && shotData.ocrStatus == OcrStatus.userConfirmed) {
      final smash = shotData.calculatedSmashFactor;
      lines.add(isEn ? 'Shot values were confirmed by the user.' : '사용자가 확인한 샷 기록을 함께 표시합니다.');
      if (smash != null) {
        lines.add(isEn ? 'Ball speed / club speed: $smash.' : '볼스피드 ÷ 클럽스피드: $smash.');
      }
      lines.add(isEn
        ? 'These shot values do not establish a cause in your posture.'
        : '샷 수치만으로 자세의 문제나 원인을 단정하지 않습니다.');
    }

    return {
      'korean_summary': lines.join('\n'),
      'primary_drill_title': isEn ? 'Posture analysis pending' : '자세 분석 대기',
      'primary_drill_description': isEn
        ? 'Review the selected video positions. Verified pose measurement is not connected yet.'
        : '지정한 영상 시점을 확인하세요. 검증된 자세 측정 기능은 아직 연결되지 않았습니다.',
    };
  }
}
