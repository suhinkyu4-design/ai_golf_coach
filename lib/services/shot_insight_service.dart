import '../models/shot_measurement_model.dart';

class ShotInsightService {
  static List<String> describe(ShotMeasurementModel? shot, {String? swingId}) {
    if (shot == null || shot.ocrStatus != OcrStatus.userConfirmed ||
        (swingId != null && shot.swingId != swingId)) return [];
    final lines = <String>[];
    final smash = shot.calculatedSmashFactor;
    if (smash != null) {
      lines.add('볼스피드 ${shot.ballSpeedMs!.toStringAsFixed(1)} m/s ÷ 클럽스피드 ${shot.clubSpeedMs!.toStringAsFixed(1)} m/s = 스매시 팩터 ${smash.toStringAsFixed(2)}. 같은 클럽의 반복 샷에서 이 비율이 일정한지 비교해 보세요.');
    } else if (shot.ballSpeedMs != null) {
      lines.add('볼스피드 ${shot.ballSpeedMs!.toStringAsFixed(1)} m/s입니다. 클럽스피드를 함께 입력하면 속도 비율을 비교할 수 있습니다.');
    }
    if (shot.ballSpeedMs == null && shot.clubSpeedMs != null) lines.add('클럽스피드 ${shot.clubSpeedMs!.toStringAsFixed(1)} m/s입니다. 볼스피드를 함께 입력하면 속도 비율을 비교할 수 있습니다.');
    final carry = shot.carryDistanceMeters, total = shot.totalDistanceMeters;
    if (carry != null && total != null && carry.isFinite && total.isFinite && carry >= 0 && total >= carry) {
      lines.add('캐리 ${carry.toStringAsFixed(1)} m · 총거리 ${total.toStringAsFixed(1)} m. 캐리 이후 거리는 ${(total-carry).toStringAsFixed(1)} m로, 그린·지면 조건의 영향도 받습니다.');
    } else if (carry != null) { lines.add('캐리 ${carry.toStringAsFixed(1)} m를 같은 클럽의 다음 샷과 비교해 보세요.'); }
    if (carry == null && total != null) lines.add('총거리 ${total.toStringAsFixed(1)} m입니다. 캐리를 함께 입력하면 캐리 이후 거리를 확인할 수 있습니다.');
    if (shot.launchAngleDeg != null || shot.backSpinRpm != null) {
      lines.add([if (shot.launchAngleDeg != null) '발사각 ${shot.launchAngleDeg!.toStringAsFixed(1)}°',
        if (shot.backSpinRpm != null) '백스핀 ${shot.backSpinRpm!.toStringAsFixed(0)} rpm'].join(' · ') + '. 클럽과 속도에 따라 달라지므로 한 가지 목표값으로 판정하지 않습니다.');
    }
    if (shot.sideSpinRpm != null) lines.add('사이드스핀 ${shot.sideSpinRpm!.toStringAsFixed(0)} rpm. 좌우 방향은 측정 장비의 부호 기준을 확인해 주세요.');
    return lines;
  }
}
