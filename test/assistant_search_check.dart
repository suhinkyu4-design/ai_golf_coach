import 'dart:io';
import '../lib/services/assistant_rules.dart';

void main() {
  final rules = AssistantRules.fromJson(
      File('assets/assistant_rules.json').readAsStringSync());
  final cases = <String, String>{
    '오늘은 저장해 둔 영상을 가져와 주세요': 'gallery',
    '지금 카메라를 열어 주세요': 'camera',
    '환경 설정 좀 보여줘': 'settings',
    '지난 기록을 다시 보여줘': 'history',
    '모델 파일을 선택하고 싶어요': 'slm',
    '발사각을 입력하고 싶어요': 'shot',
    '화면 배경을 검정으로 바꿔 주세요': 'dark',
    '흰색 테마로 변경해 주세요': 'light',
    '다음부터 레프티로 설정해 주세요': 'left',
    '오른손잡이로 설정해 주세요': 'right',
    '이번 클럽은 드라이버로 설정해 주세요': 'driver',
    '클럽을 7번 아이언으로 설정해 주세요': 'iron',
    '음성 촬영을 켜 주세요': 'voiceOn',
    '음성 촬영을 꺼 주세요': 'voiceOff',
    '메뉴 방식으로 바꿔 주세요': 'menu',
    '카메라는 어떻게 사용하나요': 'reply',
    '저장된 영상은 어떻게 가져오나요': 'reply',
    '언어 모델은 무엇을 하는 건가요': 'reply',
    '샷 기록은 어디서 입력하나요': 'reply',
    '테마를 어둡게 하려면 어떻게 하나요': 'reply',
    '음성 촬영을 켜는 방법 알려줘': 'reply',
    '갤러리 그리고 카메라를 열어줘': 'clarify',
    '다크 테마 말고 흰색으로 바꿔': 'clarify',
    '카메라를 켜지 말고 기다려': 'clarify',
  };
  for (final e in cases.entries) {
    final d = rules.resolve(e.key, hasAnalysis: true, busy: false);
    if (d.intent.action != e.value)
      throw StateError('${e.key}: ${d.intent.action} != ${e.value}');
    if (e.value == 'reply' && (d.message?.isEmpty ?? true))
      throw StateError('missing explanation');
  }
  if (rules
          .resolve('발사각을 입력하고 싶어요', hasAnalysis: false, busy: false)
          .intent
          .action !=
      'reply') throw StateError('missing analysis');
  if (rules
          .resolve('흰색 테마로 변경해 주세요', hasAnalysis: true, busy: true)
          .intent
          .action !=
      'reply') throw StateError('busy');
  print(
      'PASS: ${cases.length + 2} independently authored search and state cases');
}
