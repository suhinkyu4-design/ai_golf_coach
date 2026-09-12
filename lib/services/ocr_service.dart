import '../models/shot_measurement_model.dart';

class OcrService {
  static ShotMeasurementModel parseOcrText(String rawText, String swingId) {
    final values = <String, double?>{};
    final lines = rawText.split('\n').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();

    // 모든 숫자 및 토큰 추출
    final numberRegExp = RegExp(r'[+-]?(?:\d{1,3}(?:,\d{3})+|\d+)(?:\.\d+)?');
    final allNumbers = <_NumToken>[];

    for (int l = 0; l < lines.length; l++) {
      final matches = numberRegExp.allMatches(lines[l]);
      for (final m in matches) {
        final n = double.tryParse(m.group(0)!.replaceAll(',', ''));
        if (n != null && n.isFinite) {
          allNumbers.add(_NumToken(lineIndex: l, value: n));
        }
      }
    }

    // 골프 스크린 주요 항목 정규식 라벨
    final ballReg = RegExp(r'볼\s*(?:스피드|속도)|ball\s*speed|b\.s\b', caseSensitive: false);
    final clubReg = RegExp(r'(?:클럽|헤드)\s*(?:스피드|속도)|(?:club|head)\s*speed|c\.s\b|h\.s\b', caseSensitive: false);
    final carryReg = RegExp(r'캐리|carry', caseSensitive: false);
    final totalReg = RegExp(r'total(?:\s*distance)?|총\s*(?:비)?거리|전체\s*비거리|\b비거리\b', caseSensitive: false);
    final launchReg = RegExp(r'launch\s*angle|발사\s*각(?:도)?', caseSensitive: false);
    final backReg = RegExp(r'back\s*spin|백\s*스핀', caseSensitive: false);
    final sideReg = RegExp(r'side\s*spin|사이드\s*스핀', caseSensitive: false);

    // 라벨 근처(±2 라인)에서 수치 물리 범위 조건에 들어맞는 가장 가까운 숫자 추출 함수
    double? findNearestValue(RegExp labelReg, bool Function(double) validRange) {
      for (int l = 0; l < lines.length; l++) {
        if (labelReg.hasMatch(lines[l])) {
          for (int distance = 0; distance <= 2; distance++) {
            for (final dir in [0, 1, -1]) {
              final targetLine = l + (distance * dir);
              if (targetLine >= 0 && targetLine < lines.length) {
                final candidates = allNumbers.where((n) => n.lineIndex == targetLine && validRange(n.value)).toList();
                if (candidates.isNotEmpty) {
                  return candidates.first.value;
                }
              }
            }
          }
        }
      }
      return null;
    }

    values['ball'] = findNearestValue(ballReg, (v) => v >= 20.0 && v <= 120.0) ??
                     findNearestValue(ballReg, (v) => v > 0);
    values['club'] = findNearestValue(clubReg, (v) => v >= 15.0 && v <= 80.0) ??
                     findNearestValue(clubReg, (v) => v > 0);
    values['carry'] = findNearestValue(carryReg, (v) => v >= 30.0 && v <= 400.0) ??
                      findNearestValue(carryReg, (v) => v >= 0);
    values['total'] = findNearestValue(totalReg, (v) => v >= 30.0 && v <= 450.0) ??
                      findNearestValue(totalReg, (v) => v >= 0);
    values['launch'] = findNearestValue(launchReg, (v) => v >= -10.0 && v <= 60.0);
    values['back'] = findNearestValue(backReg, (v) => v >= 300.0 && v <= 15000.0) ??
                     findNearestValue(backReg, (v) => v >= 0);
    values['side'] = findNearestValue(sideReg, (v) => v >= -5000.0 && v <= 5000.0);

    return ShotMeasurementModel(
      measurementId: 'ocr_${DateTime.now().microsecondsSinceEpoch}',
      swingId: swingId,
      ballSpeedMs: values['ball'],
      clubSpeedMs: values['club'],
      carryDistanceMeters: values['carry'],
      totalDistanceMeters: values['total'],
      launchAngleDeg: values['launch'],
      backSpinRpm: values['back'],
      sideSpinRpm: values['side'],
      ocrStatus: OcrStatus.pending,
    );
  }
}

class _NumToken {
  final int lineIndex;
  final double value;
  _NumToken({required this.lineIndex, required this.value});
}
