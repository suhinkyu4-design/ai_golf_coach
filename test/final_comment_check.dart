// ignore_for_file: avoid_print
import 'package:ai_golf_coach/services/final_comment_service.dart';
import 'package:ai_golf_coach/models/metric_model.dart';
void check(bool ok, String name) { if (!ok) throw StateError(name); }
void main() {
  final report = {'metrics': List.generate(20, (i) => {'id': '$i', 'value': i})};
  final metrics = [MetricModel(id: 'top_to_impact_duration', name: '시간', value: 300,
    unit: 'ms', status: MetricStatus.estimated, evidenceTimeMs: [100,400])];
  final coaching = {'status': 'measurement_explanation', 'facts': [
    {'id': 'one', 'text': '영상상 각도가 20°에서 25°로 변했습니다.'},
    {'id': 'two', 'text': '두 번째 측정 사실'}],
    'resources': [{'id':'general_tempo_practice'}, {'id':'posture_reference'}], 'limitations': '2D'};
  final result = FinalCommentService.build(metrics: metrics, poseReport: report, coaching: coaching);
  check(result['slm_executed'] == false, 'Do not simulate SLM');
  check(!(result['comment'] as String).contains('두 번째'), 'One main observation');
  check(result['slm_request']['facts'].length == 2, 'Keep all facts in request');
  check(result['slm_request']['pose_measurements']['metrics'].length == 20, 'Keep all pose values');
  check(result['slm_request']['timing_measurements'][0]['value'] == 300, 'Keep timing');
  check(result['slm_request']['resources'].length == 2, 'Keep reference material');
  final missing = FinalCommentService.build(metrics: [], poseReport: {}, coaching: {
    'status':'insufficient_measurements', 'facts': [], 'resources': [], 'limitations':'2D'});
  check(missing['practice_resource_ids'].isEmpty, 'No ungrounded drill');
  check(missing['practice_title'] == '다음 확인 한 가지', 'Ask to check video on missing data');
  print('PASS: concise comment, complete input, evidence IDs, unavailable fallback');
}
