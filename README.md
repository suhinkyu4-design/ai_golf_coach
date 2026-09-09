# AI On-Device Golf Coach (AI 온디바이스 골프 코치)

> **무료 골프 자세 분석 앱 기획서와 기술 아키텍처 (버전 0.2)** 기반 온디바이스 AI Flutter 앱

---

## 🏗️ 프로젝트 아키텍처 및 핵심 모듈

```
lib/
├── main.dart                  # 앱 진입점 (Dark Theme, Provider 설정)
├── models/                    # 온디바이스 JSON Schema v0.1 기반 데이터 모델
│   ├── swing_model.dart
│   ├── shot_measurement_model.dart  # OCR 수치 & Smash Factor 계산
│   ├── metric_model.dart            # 2D 각도/템포 지표
│   └── analysis_result_model.dart   # 근거 기반 수치화 분석 결과
├── services/                  # 온디바이스 알고리즘 & 샌드박싱 엔진
│   ├── geometry_service.dart        # 2D 관절 각도 (acos(clamp)) & 어드레스 몸통 정규화
│   ├── rule_engine.dart             # 수치 판정 규칙 엔진 (allowed_observations / drills)
│   ├── ocr_service.dart             # ML Kit OCR 파싱 & 단위 변환
│   ├── slm_template_service.dart    # 억제된 한국어 코칭 피드백 생성기 (환각 0건 지향)
│   └── database_service.dart        # SQLite 데이터베이스 서비스
├── providers/                 # 앱 상태 관리
│   └── swing_provider.dart
└── views/                     # 프리미엄 다크 모드 UI 화면
    ├── home_screen.dart             # 메인 대시보드
    ├── video_input_screen.dart      # 정면/후방, 왼손/오른손, 클럽 선택 & 영상 로딩
    ├── ocr_input_screen.dart        # 스크린 결과 캡처 OCR 자동 파싱 & Smash Factor
    ├── analysis_result_screen.dart   # 관찰 요약, 측정 수치 리포트 & 다음 연습 1가지
    └── history_screen.dart          # 과거 분석 기록 비교
```

---

## 🖥️ 윈도우(Windows) 로컬 PC에서 실행하는 방법

1. **프로젝트 받아오기 (Git Pull)**:
   ```bash
   git pull origin main
   ```

2. **패키지 설치**:
   ```bash
   flutter pub get
   ```

3. **안드로이드 에뮬레이터 또는 실기기 연결 후 실행**:
   ```bash
   flutter run
   ```
