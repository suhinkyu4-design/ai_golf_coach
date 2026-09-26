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
          !metric.value.isFinite || metric.value <= 0) {
        continue;
      }
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
    final poseCount = metrics.where((m) => m.id.contains('_projected_at_')).length;
    lines.add(isEn
      ? '$poseCount image-plane posture measurements are available. These are 2D estimates, not 3D joint angles.'
      : '영상상 자세 수치 $poseCount개를 계산했습니다. 선택 시각의 근접 프레임에서 계산한 2D 추정값이며, 실제 3D 관절 각도가 아닙니다.');
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
      'primary_drill_title': isEn ? 'Measurement explanation' : '측정값 설명',
      'primary_drill_description': isEn
        ? 'Review the measurements with linked reference material. Generated explanations are not training labels.'
        : '자세별 측정값과 연결된 참고 자료를 확인하세요. 생성된 설명은 학습 정답으로 취급하지 않습니다.',
    };
  }
}
