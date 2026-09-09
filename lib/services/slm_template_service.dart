import '../models/metric_model.dart';
import '../models/shot_measurement_model.dart';

class SlmTemplateService {
  /// Generates natural Korean coaching text strictly constrained by allowed observations & drills
  static Map<String, String> generateConstrainedSummary({
    required List<String> allowedObservations,
    required List<String> allowedDrills,
    required List<MetricModel> metrics,
    ShotMeasurementModel? shotData,
  }) {
    if (allowedObservations.isEmpty) {
      return {
        'korean_summary': '측정된 주요 동작 수치가 안정적인 범주 내에 있습니다. 전반적인 밸런스를 유지하며 다음 연습을 진행하세요.',
        'primary_drill_title': '현재 템포 유지 연습',
        'primary_drill_description': '어드레스부터 피니시까지 일정 속도를 지키며 10회 연속 스윙하세요.',
      };
    }

    final StringBuffer summaryBuffer = StringBuffer();
    String drillTitle = '핵심 교정 드릴';
    String drillDesc = '동작 근거 프레임을 확인하고 연습을 진행하세요.';

    for (String obs in allowedObservations) {
      switch (obs) {
        case 'OBS_LEAD_ELBOW_BENT_AT_TOP':
          summaryBuffer.writeln('• 백스윙 탑에서 리드 팔(왼팔)이 영상 상으로 다소 굽혀져 보입니다.');
          break;
        case 'OBS_QUICK_DOWNSWING_TEMPO':
          summaryBuffer.writeln('• 다운스윙 전환 템포가 다소 급하게 이루어졌습니다.');
          break;
        case 'OBS_EARLY_EXTENSION_RISING':
          summaryBuffer.writeln('• 임팩트 부근에서 상체 척추 기울기가 유지되지 않고 들리는 관찰이 있었습니다.');
          break;
      }
    }

    if (shotData != null && shotData.calculatedSmashFactor != null) {
      summaryBuffer.writeln('• 스매시 팩터(Smash Factor)는 ${shotData.calculatedSmashFactor}로 계산되었습니다.');
    }

    // Assign Primary Drill
    if (allowedDrills.contains('DRILL_WIDE_BACKSWING_ARC')) {
      drillTitle = '백스윙 아크 넓히기 연습';
      drillDesc = '테이크어웨이 시 오른손으로 왼손목을 잡고 템포를 느끼며 리드 팔을 곧게 뻗는 느낌으로 10회 연습하세요.';
    } else if (allowedDrills.contains('DRILL_PAUSE_AT_TOP')) {
      drillTitle = '탑 1초 정지 템포 연습';
      drillDesc = '백스윙 탑에서 1초 멈춘 뒤 다운스윙을 시작하여 리듬을 안정화하세요.';
    } else if (allowedDrills.contains('DRILL_POSTURE_WALL_DRILL')) {
      drillTitle = '벽에 엉덩이 대고 척추각 유지 드릴';
      drillDesc = '벽에서 10cm 떨어져 어드레스하고 백스윙과 임팩트 시 엉덩이가 벽에서 떨어지지 않게 스윙하세요.';
    }

    return {
      'korean_summary': summaryBuffer.toString().trim(),
      'primary_drill_title': drillTitle,
      'primary_drill_description': drillDesc,
    };
  }
}
