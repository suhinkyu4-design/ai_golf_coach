import '../models/metric_model.dart';
import '../models/shot_measurement_model.dart';
import 'localization_service.dart';

class SlmTemplateService {
  /// Generates natural coaching text strictly constrained by allowed observations & drills
  /// Supports both Korean and English output
  static Map<String, String> generateConstrainedSummary({
    required List<String> allowedObservations,
    required List<String> allowedDrills,
    required List<MetricModel> metrics,
    ShotMeasurementModel? shotData,
    AppLanguage language = AppLanguage.korean,
  }) {
    final bool isEn = language == AppLanguage.english;

    if (allowedObservations.isEmpty) {
      return {
        'korean_summary': isEn
            ? 'Measured movement metrics are within a stable range. Maintain overall balance for your next practice.'
            : '측정된 주요 동작 수치가 안정적인 범주 내에 있습니다. 전반적인 밸런스를 유지하며 다음 연습을 진행하세요.',
        'primary_drill_title': isEn ? 'Maintain Current Tempo Drill' : '현재 템포 유지 연습',
        'primary_drill_description': isEn
            ? 'Perform 10 continuous practice swings maintaining steady speed from address to finish.'
            : '어드레스부터 피니시까지 일정 속도를 지키며 10회 연속 스윙하세요.',
      };
    }

    final StringBuffer summaryBuffer = StringBuffer();
    String drillTitle = isEn ? 'Key Corrective Drill' : '핵심 교정 드릴';
    String drillDesc = isEn ? 'Review evidence frames and proceed with practice.' : '동작 근거 프레임을 확인하고 연습을 진행하세요.';

    for (String obs in allowedObservations) {
      switch (obs) {
        case 'OBS_LEAD_ELBOW_BENT_AT_TOP':
          summaryBuffer.writeln(isEn
              ? '• Lead elbow (left arm) appears slightly bent at top of backswing.'
              : '• 백스윙 탑에서 리드 팔(왼팔)이 영상 상으로 다소 굽혀져 보입니다.');
          break;
        case 'OBS_QUICK_DOWNSWING_TEMPO':
          summaryBuffer.writeln(isEn
              ? '• Downswing transition tempo was slightly rushed.'
              : '• 다운스윙 전환 템포가 다소 급하게 이루어졌습니다.');
          break;
        case 'OBS_EARLY_EXTENSION_RISING':
          summaryBuffer.writeln(isEn
              ? '• Spine tilt loss detected near impact (early extension).'
              : '• 임팩트 부근에서 상체 척추 기울기가 유지되지 않고 들리는 관찰이 있었습니다.');
          break;
      }
    }

    if (shotData != null && shotData.calculatedSmashFactor != null) {
      summaryBuffer.writeln(isEn
          ? '• Smash Factor is calculated at ${shotData.calculatedSmashFactor}.'
          : '• 스매시 팩터(Smash Factor)는 ${shotData.calculatedSmashFactor}로 계산되었습니다.');
    }

    // Assign Primary Drill
    if (allowedDrills.contains('DRILL_WIDE_BACKSWING_ARC')) {
      drillTitle = isEn ? 'Wide Backswing Arc Drill' : '백스윙 아크 넓히기 연습';
      drillDesc = isEn
          ? 'Hold your left wrist with right hand at takeaway and practice extending lead arm with rhythm for 10 reps.'
          : '테이크어웨이 시 오른손으로 왼손목을 잡고 템포를 느끼며 리드 팔을 곧게 뻗는 느낌으로 10회 연습하세요.';
    } else if (allowedDrills.contains('DRILL_PAUSE_AT_TOP')) {
      drillTitle = isEn ? '1-Second Pause at Top Drill' : '탑 1초 정지 템포 연습';
      drillDesc = isEn
          ? 'Pause at top of backswing for 1 second before downswing to stabilize rhythm.'
          : '백스윙 탑에서 1초 멈춘 뒤 다운스윙을 시작하여 리듬을 안정화하세요.';
    } else if (allowedDrills.contains('DRILL_POSTURE_WALL_DRILL')) {
      drillTitle = isEn ? 'Glute-to-Wall Posture Drill' : '벽에 엉덩이 대고 척추각 유지 드릴';
      drillDesc = isEn
          ? 'Stand 10cm from a wall at address and maintain glute contact with wall through impact.'
          : '벽에서 10cm 떨어져 어드레스하고 백스윙과 임팩트 시 엉덩이가 벽에서 떨어지지 않게 스윙하세요.';
    }

    return {
      'korean_summary': summaryBuffer.toString().trim(),
      'primary_drill_title': drillTitle,
      'primary_drill_description': drillDesc,
    };
  }
}
