import 'package:flutter_test/flutter_test.dart';
import 'package:ai_golf_coach/services/ocr_service.dart';
import 'package:ai_golf_coach/models/shot_measurement_model.dart';

void main() {
  test('Recognized units are normalized and spin directions stay separate', () {
    final shot = OcrService.parseOcrText('''볼스피드: 60 m/s
클럽스피드: 40 m/s
캐리: 180 m
총거리: 200 m
백스핀: 2500 rpm
사이드스핀: -350 rpm
발사각: 14 deg''', 's1');
    expect(shot.ballSpeedMs, 60);
    expect(shot.clubSpeedMs, 40);
    expect(shot.carryDistanceMeters, 180);
    expect(shot.totalDistanceMeters, 200);
    expect(shot.backSpinRpm, 2500);
    expect(shot.sideSpinRpm, -350);
    expect(shot.launchAngleDeg, 14);
    expect(shot.ocrStatus, OcrStatus.pending);
    expect(shot.calculatedSmashFactor, isNull);
  });
  test('Unknown units and ambiguous duplicate labels do not fill fields', () {
    final shot = OcrService.parseOcrText('''Ball Speed: 60 m/s
Club Speed: 40 m/s
Carry: 180 m''', 's1');
    expect(shot.ballSpeedMs, 60);
    expect(shot.clubSpeedMs, 40);
    expect(shot.carryDistanceMeters, 180);
  });
  test('Korean labels on adjacent lines are accepted with explicit units', () {
    final shot = OcrService.parseOcrText('볼 스피드\n60 m/s\n클럽 스피드: 40 m/s', 's1');
    expect(shot.ballSpeedMs, 60);
    expect(shot.clubSpeedMs, 40);
  });
  test('Smash factor needs confirmed positive finite speeds', () {
    ShotMeasurementModel sample(OcrStatus status, double ball, double club) => ShotMeasurementModel(
      measurementId: 'm1', swingId: 's1', ocrStatus: status,
      ballSpeedMs: ball, clubSpeedMs: club);
    expect(sample(OcrStatus.userConfirmed, 60, 40).calculatedSmashFactor, 1.5);
    expect(sample(OcrStatus.pending, 60, 40).calculatedSmashFactor, isNull);
    expect(sample(OcrStatus.rejected, 60, 40).calculatedSmashFactor, isNull);
    expect(sample(OcrStatus.userConfirmed, 60, 0).calculatedSmashFactor, isNull);
    expect(sample(OcrStatus.userConfirmed, double.nan, 40).calculatedSmashFactor, isNull);
  });
}
