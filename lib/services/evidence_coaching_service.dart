import '../models/swing_model.dart';

/// Local retrieval and descriptive arithmetic. No LLM, diagnosis or gold labels.
class EvidenceCoachingService {
  static const version = 'evidence_coaching_1.0';
  static Map<String, dynamic> build(
      SwingModel swing, Map<String, dynamic> report,
      {required bool eventsConfirmed}) {
    final facts = <Map<String, dynamic>>[];
    final resources = <Map<String, dynamic>>[];
    final usable = <String, Map>{};
    if (eventsConfirmed && swing.view != SwingView.unknown) {
      for (final row in report['metrics'] as List? ?? []) {
        if (row is! Map) continue;
        final value = row['value'];
        final likelihood = row['min_joint_likelihood'];
        if (row['status'] == 'estimated' &&
            value is num &&
            value.isFinite &&
            likelihood is num &&
            likelihood.isFinite &&
            likelihood >= 0.7 &&
            likelihood <= 1 &&
            row['unit'] == 'deg' &&
            row['id'] is String &&
            value.abs() <= 180) {
          usable[row['id'] as String] = row;
        }
      }
    }
    void compare(String kind, String from, String to, String label) {
      final a = usable['${kind}_projected_at_$from'];
      final b = usable['${kind}_projected_at_$to'];
      if (a == null || b == null) return;
      final av = (a['value'] as num).toDouble();
      final bv = (b['value'] as num).toDouble();
      final delta = bv - av;
      facts.add({
        'id': '${kind}_${from}_to_$to',
        'evidence_metric_ids': [a['id'], b['id']],
        'from_value': av,
        'to_value': bv,
        'signed_delta_deg': double.parse(delta.toStringAsFixed(2)),
        'text': '$label: ${av.toStringAsFixed(1)}° → ${bv.toStringAsFixed(1)}° '
            '(변화 ${delta >= 0 ? '+' : ''}${delta.toStringAsFixed(1)}°).',
      });
    }

    if (swing.view == SwingView.rear || swing.view == SwingView.targetLine) {
      compare('torso_tilt', 'address', 'impact', '어드레스→임팩트의 영상상 몸통 기울기');
    }
    compare('lead_elbow', 'top', 'impact', '탑→임팩트의 영상상 리드 팔꿈치 각도');
    if (facts.any((f) => (f['id'] as String).startsWith('torso_tilt'))) {
      resources.add({
        'id': 'posture_reference',
        'title': '몸통 자세를 영상으로 다시 확인하기',
        'connection':
            '어드레스와 임팩트의 몸통 기울기 측정값이 있어 관련 주제를 연결했습니다. 변화량이 크다는 판정은 아닙니다.',
        'text': '몸통 자세를 다루는 참고 자료입니다. 두 시점을 번갈아 보며 몸통과 골반의 움직임을 확인해 보세요. '
            '기울기 차이만으로 일찍 일어나는 동작이나 그 원인을 확정할 수 없습니다.',
        'source_title': 'PGA of America · How to Maintain Your Spine Angle',
        'source_url':
            'https://www.pga.com/story/golf-tips-how-to-maintain-your-spine-angle-for-more-speed',
        'content_type': 'original_short_summary_and_reference_link',
        'retrieval_basis': 'topic_match_not_fault_detection',
      });
    }
    if (usable.isNotEmpty) {
      resources.add({
        'id': 'general_tempo_practice',
        'title': '천천히 빈스윙하며 리듬 확인하기',
        'connection': '스윙 자세 기록이 있어 일반 연습 자료를 안내합니다. 균형이나 템포에 문제가 검출된 것은 아닙니다.',
        'text': '편안한 속도의 빈스윙으로 리듬을 확인해 보세요. 참고 자료는 발을 모으고 천천히 하는 빈스윙을 소개합니다. '
            '동작이 불편하면 따라 하지 말고 편한 스탠스를 유지하세요.',
        'source_title':
            'PGA of America · Feet Together Drill to Improve Balance and Tempo',
        'source_url':
            'https://www.pga.com/story/feet-together-drill-to-improve-balance-and-tempo',
        'content_type': 'original_short_summary_and_reference_link',
        'retrieval_basis': 'general_practice_not_personalized_prescription',
      });
    }
    return {
      'version': version,
      'mode': 'local_evidence_template',
      'slm_executed': false,
      'status': usable.isEmpty
          ? 'insufficient_measurements'
          : 'measurement_explanation',
      'facts': facts,
      'resources': resources,
      'summary': usable.isEmpty
          ? '설명에 사용할 자세 수치가 부족합니다. 촬영 방향과 선택한 자세 시각을 확인하고, 관절이 보이는 영상으로 다시 분석해 주세요.'
          : facts.isEmpty
              ? '자세 수치 ${usable.length}개가 있습니다. 시점 간 비교에 필요한 수치가 부족해 개별 측정값만 표시합니다.'
              : facts.map((f) => f['text']).join('\n'),
      'limitations':
          '각도는 영상 평면의 추정값입니다. 촬영 방향과 관절 가림의 영향을 받으며, 선택 시각과 실제 프레임 시각에 차이가 있을 수 있습니다. '
              '정상 각도, 체중 분포, 실제 3D 회전이나 클럽 페이스를 판정하지 않습니다.',
      'inference_instruction': '제공된 facts와 resources만 사용해 한국어로 짧게 설명하세요. '
          '계산된 수치를 바꾸거나 새로운 정상 범위·문제 원인을 만들지 마세요. '
          'resources는 일반 참고 자료이며 측정된 결함에 대한 처방이 아닙니다. '
          '설명에 사용한 fact id와 resource id를 함께 반환하고, 근거가 부족하면 측정 재확인을 안내하세요.',
      'generated_text_is_training_target': false,
    };
  }
}
