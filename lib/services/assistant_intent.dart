/// Bounded, local command vocabulary. Unknown requests never mutate settings.
class AssistantIntent {
  final String action;
  final String? argument;
  const AssistantIntent(this.action, [this.argument]);
  static const topics = {
    '스웨이': 'head_trail_check',
    '배치기': 'early_extension_check',
    '얼리익스텐션': 'early_extension_check',
    '상체들림': 'standing_up_check',
    '얼리스탠드업': 'standing_up_check',
    '치킨윙': 'chicken_wing_check',
    '헤드업': 'head_up_check',
    '캐스팅': 'casting_check',
    '오버더탑': 'over_the_top_check'
  };
  static AssistantIntent parse(String input) {
    final s = input.toLowerCase().replaceAll(RegExp(r'[\s.,!?]'), '');
    if (s.isEmpty) return const AssistantIntent('unknown');
    if (RegExp(r'하지마|하지않|말고|아니|안할|안해').hasMatch(s))
      return const AssistantIntent('clarify');
    if (s.contains('설명') ||
        s.contains('뭐야') ||
        s.contains('무엇') ||
        s.contains('어떻게') ||
        s.contains('왜') ||
        s.contains('방법')) {
      for (final e in topics.entries) {
        if (s.contains(e.key)) return AssistantIntent('explain', e.value);
      }
      if (s.contains('촬영') ||
          s.contains('갤러리') ||
          s.contains('설정') ||
          s.contains('사용')) return const AssistantIntent('help');
    }
    for (final e in topics.entries) {
      if (s.contains(e.key)) return AssistantIntent('explain', e.value);
    }
    const commands = <String, List<String>>{
      'camera': [
        '시작',
        '촬영해줘',
        '카메라켜줘',
        '촬영',
        '카메라',
        '촬영할게',
        '촬영할래',
        '촬영하기',
        '촬영모드',
        '새영상촬영',
        '카메라열어줘',
        '촬영시작'
      ],
      'gallery': [
        '갤러리영상분석해줘',
        '갤러리열어',
        '갤러리',
        '갤러리모드',
        '갤러리열어줘',
        '갤러리에서가져오기',
        '영상선택',
        '동영상선택',
        '저장된영상',
        '영상가져오기',
        '갤러시'
      ],
      'settings': ['설정', '설정열어줘', '설정보여줘'],
      'history': ['기록', '최근기록', '지난기록', '기록보여줘'],
      'resultPage': ['결과펼쳐보기'],
      'result': ['결과', '분석결과', '결과보여줘', '방금스윙', '뭐가문제야', '분석결과설명해줘'],
      'detail': ['분석상세', '측정상세', '상세보기', '자세히보기'],
      'video': ['영상으로확인', '영상보여줘', '그장면보여줘', '영상으로확인하기'],
      'timing': ['자세시점수정', '시점수정', '임팩트수정'],
      'shot': ['샷기록', '샷기록추가', '샷기록입력', '샷분석', 'ocr', '스코어사진'],
      'slm': ['모델설정', 'slm설정'],
      'followup': ['왜', '왜그래', '왜그런거야', '그건뭐야', '더설명해줘'],
      'practice': ['교정안내', '연습', '연습방법', '어떻게연습해', '어떻게고쳐', '교정방법'],
      'back': ['이전', '뒤로', '이전화면', '처음으로', '홈으로', '취소'],
      'dark': ['어둡게', '화면어둡게해줘', '어두운화면', '다크모드'],
      'light': ['밝게', '화면밝게해줘', '밝은화면', '화이트모드'],
      'left': ['왼손', '왼손잡이', '왼손잡이로설정해', '레프티'],
      'right': ['오른손', '오른손잡이', '오른손잡이로설정해'],
      'driver': ['드라이버', '드라이버로설정해'],
      'iron': ['7번아이언', '아이언7번', '아이언으로설정해'],
      'rear': ['후방', '후방촬영', '후방으로설정해'],
      'face': ['정면', '정면촬영', '정면으로설정해'],
      'voiceOn': ['음성촬영켜줘', '음성으로촬영켜기'],
      'voiceOff': ['음성촬영꺼줘', '음성으로촬영끄기'],
      'menu': ['메뉴모드', '메뉴모드로변경', '메뉴모드로바꿔줘'],
      'help': ['도움말', '뭘할수있어', '기능', '사용법', '어떻게사용해', '앱소개'],
    };
    for (final e in commands.entries) {
      if (e.value.contains(s)) return AssistantIntent(e.key);
    }
    return const AssistantIntent('unknown');
  }
}
