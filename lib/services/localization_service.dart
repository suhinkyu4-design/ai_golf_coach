enum AppLanguage { korean, english }

class LocalizationService {
  static Map<String, Map<String, String>> _localizedStrings = {
    'app_title': {
      'ko': 'AI 온디바이스 골프 코치',
      'en': 'AI On-Device Golf Coach',
    },
    'banner_title': {
      'ko': '영상과 샷 기록 확인',
      'en': 'Video and shot review',
    },
    'banner_subtitle': {
      'ko': '촬영한 영상과 직접 확인한 스크린장 수치를 함께 기록합니다.',
      'en': 'Review video and confirmed shot values together.',
    },
    'start_new_swing': {
      'ko': '새 스윙 분석 시작',
      'en': 'Start New Swing Analysis',
    },
    'select_video_btn': {
      'ko': '스윙 영상 선택 및 촬영',
      'en': 'Select or Record Swing Video',
    },
    'select_video_sub': {
      'ko': '정면/후방 스윙 영상 불러오기',
      'en': 'Import Face-on or Rear Swing Video',
    },
    'recent_history': {
      'ko': '이번 실행의 스윙 기록',
      'en': 'Current Session History',
    },
    'view_all': {
      'ko': '전체보기',
      'en': 'View All',
    },
    'no_history': {
      'ko': '아직 분석된 스윙 기록이 없습니다.',
      'en': 'No analyzed swing records yet.',
    },
    'video_setting_title': {
      'ko': '스윙 정보 및 영상 설정',
      'en': 'Swing Info & Video Settings',
    },
    'select_orientation': {
      'ko': '촬영 방향 선택',
      'en': 'Select Camera Angle',
    },
    'face_on': {
      'ko': '정면 (Face-on)',
      'en': 'Face-on',
    },
    'rear': {
      'ko': '후방 (Rear)',
      'en': 'Rear (Target-line)',
    },
    'handedness': {
      'ko': '주 타석 손 잡이',
      'en': 'Golfer Handedness',
    },
    'right_handed': {
      'ko': '오른손잡이',
      'en': 'Right-handed',
    },
    'left_handed': {
      'ko': '왼손잡이',
      'en': 'Left-handed',
    },
    'club_used': {
      'ko': '사용 클럽',
      'en': 'Club Used',
    },
    'next_ocr': {
      'ko': '다음: 스크린 샷 OCR 추가 (선택)',
      'en': 'Next: Attach Screen OCR (Optional)',
    },
    'ocr_title': {
      'ko': '스크린 결과 OCR 연동',
      'en': 'Screen Golf OCR Integration',
    },
    'ocr_desc': {
      'ko': '볼스피드, 헤드스피드, 비거리가 포함된 모니터 화면 사진을 추가하면 동작과 통합 분석합니다.',
      'en': 'Add screen monitor photos with Ball Speed & Carry for integrated motion coaching.',
    },
    'ocr_btn': {
      'ko': '스크린 캡처 OCR 자동 분석 실행',
      'en': 'Run Screen Capture OCR Parser',
    },
    'ocr_success': {
      'ko': 'OCR 추출 성공',
      'en': 'OCR Extraction Succeeded',
    },
    'ball_speed': {
      'ko': '볼 스피드',
      'en': 'Ball Speed',
    },
    'club_speed': {
      'ko': '클럽 스피드',
      'en': 'Club Speed',
    },
    'smash_factor': {
      'ko': '스매시 팩터 (Smash Factor)',
      'en': 'Smash Factor',
    },
    'carry_dist': {
      'ko': '캐리 거리',
      'en': 'Carry Distance',
    },
    'start_analysis': {
      'ko': '통합 분석 시작',
      'en': 'Start Integrated Analysis',
    },
    'analysis_result_title': {
      'ko': '스윙 분석 결과',
      'en': 'Swing Analysis Result',
    },
    'key_summary': {
      'ko': '핵심 관찰 요약',
      'en': 'Key Observation Summary',
    },
    'metrics_report': {
      'ko': '측정 수치 리포트',
      'en': 'Measured Metrics Report',
    },
    'recommended_drill': {
      'ko': '다음 연습 한 가지 (Recommended Drill)',
      'en': 'Recommended Actionable Drill',
    },
    'back_to_home': {
      'ko': '홈으로 돌아가기',
      'en': 'Back to Home',
    },
  };

  static String tr(String key, AppLanguage lang) {
    final langCode = lang == AppLanguage.english ? 'en' : 'ko';
    return _localizedStrings[key]?[langCode] ?? key;
  }
}
