import 'dart:convert';
import 'dart:io';
import '../lib/services/slm_measurement_contract.dart';

void expect(bool value, String message) {
  if (!value) throw StateError(message);
}

Map<String, dynamic> metric({num value = 148.21, num confidence = .9}) => {
      'id': 'lead_elbow_projected_at_impact',
      'phase': 'impact',
      'kind': 'lead_elbow',
      'value': value,
      'unit': 'deg',
      'status': 'estimated',
      'reason': null,
      'min_joint_likelihood': confidence,
      'joint_names': ['leftShoulder', 'leftElbow', 'leftWrist']
    };
Map<String, dynamic>? select(Map<String, dynamic> row) =>
    SlmMeasurementContract.select({
      'metrics': [row]
    }, 'faceOn', '7i');
void main() {
  final payload = select(metric())!;
  expect(SlmMeasurementContract.prompt(payload) == File('test/fixtures/slm_impact_prompt.txt').readAsStringSync(), 'validated wire format');
  expect((payload['measurements'] as List).first['kind'] == 'left_elbow',
      'anatomical mapping');
  final valid = {
    'comment':
        '임팩트 왼쪽 팔꿈치 각도는 148.21도로 기록되어 있습니다. ${SlmMeasurementContract.limitation}',
    'next_check': SlmMeasurementContract.check,
    'evidence_ids': ['lead_elbow_projected_at_impact'],
    'practice_prescription': null
  };
  expect(
      SlmMeasurementContract.validate(
              payload, jsonEncode(valid))['slm_output_used'] ==
          true,
      'valid response');
  for (final replace in [
    ['임팩트', '탑'],
    ['왼쪽 팔꿈치', '오른쪽 무릎'],
    ['148.21', '30']
  ]) {
    final wrong = {
      ...valid,
      'comment': (valid['comment'] as String).replaceAll(replace[0], replace[1])
    };
    expect(
        SlmMeasurementContract.validate(
                payload, jsonEncode(wrong))['slm_output_used'] ==
            false,
        'reject mismatch');
  }
  expect(
      SlmMeasurementContract.validate(
              payload,
              jsonEncode({
                ...valid,
                'practice_prescription': 'swing harder'
              }))['slm_output_used'] ==
          false,
      'reject prescription');
  expect(select(metric(value: 0)) != null, 'zero is valid');
  for (final value in [double.nan, double.infinity, -1, 181]) {
    expect(select(metric(value: value)) == null, 'invalid numeric');
  }
  expect(select(metric(confidence: .69)) == null, 'low likelihood');
  expect(select({...metric(), 'reason': 'events_not_confirmed'}) == null,
      'unconfirmed');
  expect(select({...metric(), 'status': 'unavailable'}) == null, 'unavailable');
  expect(
      select({...metric(), 'phase': 'top'}) == null, 'phase and id mismatch');
  expect(
      select({
            ...metric(),
            'joint_names': ['leftShoulder', 'rightElbow', 'leftWrist']
          }) ==
          null,
      'mixed anatomy');
  final leftHanded = {
    ...metric(),
    'joint_names': ['rightShoulder', 'rightElbow', 'rightWrist']
  };
  expect(
      (select(leftHanded)!['measurements'] as List).first['kind'] ==
          'right_elbow',
      'left-handed lead uses actual landmarks');
  expect(
      SlmMeasurementContract.select({
            'metrics': [metric()]
          }, 'unknown', '7i') ==
          null,
      'unknown view');
  print('SLM measurement contract checks passed');
}
