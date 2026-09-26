import '../lib/services/ocr_service.dart';
import '../lib/services/shot_insight_service.dart';
import '../lib/models/shot_measurement_model.dart';
void check(bool ok, String message) { if (!ok) throw StateError(message); }
void main() {
  final p = OcrService.parseOcrText('Ball Speed 60 m/s\nClub Speed 42 m/s\nCarry 195 m\nTotal Distance 210 m\nLaunch Angle 14°\nBack Spin 2,800 rpm\nSide Spin -600 rpm', 'a');
  check(p.ballSpeedMs == 60 && p.clubSpeedMs == 42 && p.backSpinRpm == 2800 && p.sideSpinRpm == -600, 'parse example');
  check(ShotInsightService.describe(p).isEmpty, 'unconfirmed OCR leaked');
  final confirmed = ShotMeasurementModel.fromMap({...p.toMap(), 'measurement_id':'demo_1', 'ocr_status':'userConfirmed'});
  final insights = ShotInsightService.describe(confirmed, swingId:'a').join(' ');
  check(confirmed.isTestData && insights.contains('1.43') && insights.contains('15.0 m'), 'derived example');
  check(ShotInsightService.describe(confirmed, swingId:'other').isEmpty, 'cross swing leak');
  final imperial=OcrService.parseOcrText('Ball Speed 100 mph\nCarry 150 yd','a');
  check((imperial.ballSpeedMs!-44.704).abs()<.0001 && (imperial.carryDistanceMeters!-137.16).abs()<.0001, 'units');
  final missing=OcrService.parseOcrText('Ball Speed\nClub Speed 42 m/s\nCarry 135','a');
  check(missing.ballSpeedMs==null && missing.clubSpeedMs==42 && missing.carryDistanceMeters==null, 'borrowed or unitless number');
  check(OcrService.parseOcrText('Ball Speed 60 m/s\nBall Speed 70 m/s','a').ballSpeedMs==null, 'conflicting duplicates');
  check(OcrService.parseOcrText('Ball Speed 60 m/s Club Speed 42 m/s','a').ballSpeedMs==null, 'ambiguous row');
  final iron=OcrService.parseOcrText('볼스피드 45 m/s\n클럽스피드 34 m/s\n캐리 135 m\n총거리 141 m','a');
  final i=ShotMeasurementModel.fromMap({...iron.toMap(),'ocr_status':'userConfirmed'});
  check(i.calculatedSmashFactor==1.32 && ShotInsightService.describe(i).join().contains('6.0 m'), 'iron result');
  print('PASS: shot examples, confirmation, test provenance, units, missing/ambiguous values, swing ownership');
}
