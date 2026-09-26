import '../models/metric_model.dart';

/// Local fallback; never presented as an executed SLM response.
class FinalCommentService {
  static Map<String, dynamic> build(
      {required List<MetricModel> metrics,
      required Map<String, dynamic> poseReport,
      required Map<String, dynamic> coaching}) {
    final facts = (coaching['facts'] as List? ?? []).cast<Map>();
    final resources = (coaching['resources'] as List? ?? []).cast<Map>();
    final insufficient = coaching['status'] == 'insufficient_measurements';
    final practice =
        resources.where((r) => r['id'] == 'general_tempo_practice').toList();
    return {
      'mode': 'local_summary',
      'slm_executed': false,
      'comment': insufficient
          ? '자세를 설명할 만큼 관절이 선명하게 잡히지 않았습니다. 촬영 방향과 선택한 자세 시각을 확인하고, 몸 전체가 보이는 영상으로 다시 분석해 주세요.'
          : facts.isEmpty
              ? '일부 자세 수치는 확인했지만 동작 사이의 변화를 비교할 근거가 부족합니다. 선택한 자세 장면을 다시 확인해 주세요.'
              : '${facts.first['text']} 이 차이만으로 잘못된 자세라고 판단할 수는 없습니다.',
      'practice_title':
          !insufficient && practice.isNotEmpty ? '다음 연습 한 가지' : '다음 확인 한 가지',
      'practice': !insufficient && practice.isNotEmpty
          ? '편안한 속도로 빈스윙하며 리듬을 확인해 보세요. 특정 자세 오류에 대한 처방이 아닌 일반 연습입니다.'
          : '어드레스·탑·임팩트·피니시 장면에서 관절이 보이는지 확인해 주세요.',
      'evidence_fact_ids': facts.isEmpty ? [] : [facts.first['id']],
      'practice_resource_ids':
          !insufficient && practice.isNotEmpty ? [practice.first['id']] : [],
      'slm_request': {
        'schema_version': 'final_comment_request_1.0',
        'instruction':
            '측정 기록, 자세별 수치, 계산된 사실과 참고 자료를 함께 읽고 최종 코멘트 2문장과 다음 연습 또는 확인 1가지만 한국어로 반환하세요. '
                '수치 목록 대신 관찰 하나만 설명하세요. 새 수치·정상 범위·문제 원인을 만들지 마세요. 일반 연습을 개인 결함의 처방으로 바꾸지 마세요. '
                '근거가 부족하면 재확인을 안내하고 사용한 fact ID와 resource ID를 별도로 반환하세요.',
        'timing_measurements': [
          for (final m in metrics)
            if (!m.id.contains('_projected_at_')) m.toMap()
        ],
        'pose_measurements': poseReport,
        'facts': coaching['facts'],
        'resources': coaching['resources'],
        'limitations': coaching['limitations'],
      },
    };
  }
}
