import 'package:flutter_test/flutter_test.dart';
import '../lib/services/ocr_service.dart';
import '../lib/models/shot_measurement_model.dart';

void main() {
  test('Recognized units are normalized and spin directions stay separate', () {
    final shot = OcrService.parseOcrText('''Ball Speed: 100 mph
Club Speed: 144 km/h
Carry: 100 yd
Total: 110 m
BackSpin: 2,500 rpm
SideSpin: -350 rpm
Launch Angle: 14 deg''', 's1');
    expect(shot.ballSpeedMs, closeTo(44.704, .0001));
    expect(shot.clubSpeedMs, 40);
    expect(shot.carryDistanceMeters, closeTo(91.44, .0001));
    expect(shot.totalDistanceMeters, 110);
    expect(shot.backSpinRpm, 2500);
    expect(shot.sideSpinRpm, -350);
    expect(shot.launchAngleDeg, 14);
    expect(shot.ocrStatus, OcrStatus.pending);
    expect(shot.calculatedSmashFactor, isNull);
  });
  test('Unknown units and ambiguous duplicate labels do not fill fields', () {
    final shot = OcrService.parseOcrText('''Ball Speed: 60
Club Speed: 40 m/s
Club Speed: 42 m/s
Carry: 180 ft''', 's1');
    expect(shot.ballSpeedMs, isNull);
    expect(shot.clubSpeedMs, isNull);
    expect(shot.carryDistanceMeters, isNull);
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
