# 9가지 동작 포착 명세 · 2026-09-18

대상: 드라이버/7번 아이언. 목표는 오류 이름을 나열하는 것이 아니라 실제 근거 장면과 측정값이 있는 동작 검출기다. SLM 및 개선 문장 작성은 이번 범위에서 제외한다. 일반 분석에서 기존 SLM 자동 호출을 중단했다.

## 판정 단계
1. 관찰 정의와 2D 특징 계산: 현재 코드에 구현.
2. 카메라/방향 및 관절/클럽 신원 검증: 일부 구현, 카메라 및 자동 클럽 신원은 미완료.
3. 클럽·촬영 방향별 참고 기준 검증: 미완료. 정상/오류 임계값을 임의로 만들지 않음.
4. 의심 후보 분류 및 오탐/미탐 평가: 미완료.
5. 개선 자료와 SLM: 보류.

현재 `measured_not_classified`는 비교용 수치가 나왔다는 뜻이며 오류 검출 성공이 아니다. `unavailable`은 정상 판정이 아니다. 모든 결과의 diagnosis는 null이다.

## 9개 특징
| 항목 | 영상/구간 | 계산 | 판정을 위해 추가로 검증할 조건 |
|---|---|---|---|
| 일찍 일어섬 | 후방, 탑~임팩트 직전 | 어드레스 상체 기울기 절댓값 - 현재 절댓값 | 시각/기울기 변화 지속성과 카메라 안정성 |
| 얼리 익스텐션 | 후방, 탑~임팩트 직전 | 공 방향 골반 중심 이동 / 어드레스 몸통 길이 | 골반 관절 중심과 엉덩이 윤곽 구분, 회전/시차 영향, 상체 변화 동반 |
| 스웨이 | 정면, 어드레스~탑 | 타깃 반대 방향 골반 중심 이동 / 몸통 길이 | 정상적인 이동과 과도한 이동 구분; 머리 움직임으로 대체 금지 |
| 슬라이드 | 정면, 탑~임팩트 직전 | 탑 기준 타깃 방향 골반 중심 이동 / 몸통 길이 | 정상 체중 이동과 구분; 2D 회전/체중 분포 주장 금지 |
| 리버스 스파인 | 정면, 탑 | 타깃 방향을 양수로 한 상체 중심선 기울기 | 실제 척추 신전과 2D 중심선 기울기는 다름; 리버스 피벗/체중과 동일시 금지 |
| 치킨윙 | 정면, 임팩트~300ms 이내 | 임팩트 대비 리드 팔꿈치 굽힘 증가 + 팔꿈치-어깨중심 거리 | 피니시에서 자연스러운 팔 굽힘 제외; 관절 가림 및 실제 팔 벌어짐 정의 보강 |
| 오버스윙 | 정면 또는 후방, 탑 | 검증된 헤드가 그립보다 아래에 있는 거리 / 몸통 길이 | 클럽 하나의 위치만으로 오류 아님; 몸통 대비 팔의 추가 진행 확인 필요 |
| 캐스팅 | 정면, 다운스윙 시간상 앞 절반 | 탑 대비 팔꿈치-그립-헤드 각도 증가 | 실제 손목각 아님; 샤프트/헤드 신원·프레임 밀도·구간 정의 검증 |
| 오버더탑 | 후방, 백스윙/다운스윙 같은 손 높이 | 클럽헤드 및 그립의 공 방향 차이 / 몸통 길이 | 2D 비교 특징이며 실제 클럽 패스 아님; 동일 높이 매칭/원근/궤적 검증 |

공통 단위: 2D upright pixels → 어드레스의 어깨중심~골반중심 길이로 정규화. cm와 3D 회전각으로 표시하지 않는다. 평균/표준편차를 곧바로 교정 기준으로 사용하지 않는다.

## 품질 조건과 관찰 근거
- 어드레스 < 탑 < 임팩트 < 피니시의 사용자 확인 시각이 필요하다.
- 각 프레임에서 필요한 관절 likelihood>=0.7, 유한 좌표, 영상 내부, 짧은 퇴화 벡터 제외. likelihood는 측정 오차의 보장이 아니다.
- 연속 특징은 유효 샘플 3개 이상 및 70% 이상, 인접 간격 100ms 이하. 3점 중앙값으로 단일 튐 완화. 모두 품질 휴리스틱이며 골프 정석 기준이 아니다.
- 머리/골반 등이 함께 움직이는 것으로 카메라 움직임을 확정하지 않는다. 배경 특징 기반 검증은 별도 구현해야 한다.
- 타깃 방향은 정면 어드레스의 lead/trail 발목으로 추정한다. 좌우 반전 영상에 맞춰 부호가 바뀐다. 오검출 가능성이 있으므로 자동 추정이 틀리거나 불가능하면 근거 화면의 정면 타깃 방향 선택으로 직접 보정한다.
- 후방 공 방향은 근거 화면에서 사용자가 화면 왼쪽/오른쪽을 지정한다. 이를 추측하여 기본값으로 넣지 않는다.
- club 데이터는 t_ms, identity_verified=true, coordinate_space=upright_image_pixels, grip/head 좌표가 필요하다. 현재 임팩트의 움직이는 흔적은 이 계약을 만족하지 않는다.

## 구현 경로
GalleryPoseService: 백스윙 목표33ms/최대61, 다운스윙 목표17ms/최대61, 임팩트 이후300ms 목표17ms/최대21. 중복 요청 시각은 추론 전에 제거. 실제 원본 FPS보다 많은 서로 다른 프레임을 보장하지 않으며 실제 PTS는 미확인.
SwingFaultFeatures: 9개 특징 및 누락 사유. 원시 근거는 report.motion_evidence에 남겨 재계산/내보내기 가능.
MotionDetectionScreen: 9개 항목 상태, 측정값과 근거시각 영상 seek, 정면 타깃 방향 및 후방 공 방향 선택. 테스트 숫자는 판정 임계값이 아니다.

## 검증 계획
- 계산 테스트: 방향 반전, 주사용 손, 크기, 구간 경계, 가림, 잘못된 클럽 좌표, 프레임 간격, 단일 튐.
- 실제 영상: 같은 장면의 수동 관절/클럽 표시와 대조. 카메라 이동·정상 피니시 팔굽힘·가림을 오탐 음성 사례에 포함.
- 사람별 분리 평가. 각 동작 및 두 클럽/각도별 positive/negative/unknown 구분. 표본 수와 precision/recall, 검출 시간 오차, 판단 보류율을 함께 기록.
- 기준 수립 전에는 9개 오류를 검출 완료했다고 표시하지 않는다. 특히 3차는 검증된 자동 클럽 추적이 선행되어야 한다.

## 정의 참고(수치 임계값 출처 아님)
- https://www.mytpi.com/improve-my-game/swing-characteristics/sway
- https://www.mytpi.com/improve-my-game/swing-characteristics/slide
- https://www.titleist.eu/instruction/stop-early-extension
- https://cdn.site.mytpi.com/improve-my-game/swing-characteristics/reverse-spine-angle
- https://www.mytpi.com/improve-my-game/swing-characteristics/chicken-winging
- https://www.mytpi.com/improve-my-game/swing-characteristics/over-the-top
- https://www.mdpi.com/2075-4663/10/6/91

오버스윙의 단일 정답 클럽 각도 및 범용 교정 임계값은 확보하지 못했다. 이 문서의 기하 특징은 구현 가설이며 골프 오류 판정의 검증된 정의가 아니다.

## 2026-09-18 실행 기록
- 9개 특징 계산 테스트, 이전 연속 이동/각도 테스트, 앱 소스 컴파일 및 APK 빌드 통과. 최신 APK(148231292 bytes) 폰 교체 설치 완료.
- 첫 실제 영상 110/110 샘플에서 관절 검출, 약30.263초. 시험은 자동 이벤트 구간/정면 설정을 사용해 실제 클럽/촬영 방향과 구간의 정답을 검증하지 않았다. 치킨윙 관련 팔 변화 특징은 계산됐고, 타깃 방향을 확인하지 못한 스웨이/슬라이드/리버스 스파인 특징은 보류됐다. 이는 치킨윙이 검출됐다는 뜻이 아니다.
- 후방 항목은 다른 촬영 방향 필요, 클럽 항목은 검증된 샤프트·헤드 좌표 필요로 표시됐다.
- 실영상에서 방향 추정 실패를 확인한 뒤 정면 타깃 방향 선택 UI를 추가해 다시 설치했다.
- 두 번째 실제 영상 실행 도중 USB 연결이 끊겨 결과를 받지 못했다. 두 번째 실영상 또는 전체 UI 확인을 통과했다고 기록하지 않는다.


## 2026-09-18 선택 설정 및 후방 머리 이동 시험 기준
- 촬영 기본값 rear / 오른손. 설정 카드와 강제 설정 팝업 제거, 상단 톱니바퀴만 유지.
- 클럽 기본값 unknown. 공통 2D 동작 측정 허용. Driver/7i 수동 선택은 옵션. 클럽 자동 분류 모델은 아직 구현되지 않았으며 자동 인식으로 표시하지 않음.
- head_trail_check: 사용자가 확인한 어드레스 머리(양눈 중심)→뒷발(오른손은 오른발, 왼손은 왼발) 거리 기준 30%.
- 어드레스 머리에서 뒷발로 향하는 고정 벡터에 어드레스→탑 머리 변위를 투영하고 기준 거리로 나눔. 0.30 이상이면 experimental 후보. 양안/발 신뢰도, 프레임 크기, 이벤트 확인 여부 검사.
- 검증된 스웨이 판정과 구분. 머리 숙임과 카메라 이동도 포함될 수 있음. 기준 미도달도 정상 판정이 아님.
- 합성 시험: 30% 경계/반대 이동/미러/낮은 관절 신뢰도. 실제 두 번째 영상 저장 좌표 결과 0.0948001(9.48%).


## 배치기 방향 자동 추정
- rear/targetLine에서 어드레스 양손목과 어깨 중심이 골반 중심의 같은 화면 방향에 있는 경우 그 방향을 공 쪽으로 추정.
- 양손목/어깨/골반 신뢰도 0.7 이상, 손목이 어깨보다 아래, 손목 간 거리 0.6몸통 이하, 손목 수평차 각각 0.15몸통 이상, 어깨 수평차 0.05몸통 이상 필요. 이 값은 모호한 추정 배제용 개발 기준이며 골프 오류 판정 기준이 아님.
- 수동 지정 우선. ball_direction_basis로 supplied/address_pose_inference/unavailable 구분. 추정 방향을 수동 확인으로 저장하지 않음.
- 공 직접 검출, 촬영 방향 자동 판별 또는 배치기 진단을 뜻하지 않음. 사선 투영/골반 회전/카메라 이동에 대한 배제 검증은 남아 있음.
- 합성 좌우반전/저신뢰도/모호한 손 위치 시험 및 실제 두 번째 영상의 수동 방향과 일치 확인.


## 스웨이 사용자 규칙 변경 — 최신 규칙
이 절이 앞선 head_trail_check 30% 규칙을 대체한다.
- 사용자 요구에 따라 명확한 앱 판정 제공: 25% 미만 기준 이내, 25~50% 미만 주의, 50% 이상 스웨이 감지.
- 분모는 어드레스 양 귀 x좌표 간격(머리 폭의 투영 근사). 분자는 어드레스 대비 탑의 양눈 중심 x이동 중 타깃 반대 방향 성분. 뒷발까지 거리 분모/2D대각선 이동 계산은 제거.
- 손잡이에 따른 lead/trail 발의 화면 위치로 방향을 추정하고 수동 타깃 방향을 우선 적용. 머리 너비/발 방향이 구분되지 않을 때만 unavailable. 귀가 저장되지 않은 과거 기록은 새 분석 필요.
- 판정 status=rule_classified, grade=sway/warning/within_rule, threshold_basis=user_selected_app_rule. 검증된 골프 진단으로 표시하지 않으며 diagnosis 필드는 null 유지.
- 결과 화면에 앱 판정과 비율 표시, 오차 설명은 하단 유의사항으로 분리. 개발용 9패턴의 기존 sway와 혼동되지 않도록 상세 목록의 구 sway 중복 카드를 숨김.
- 회전·카메라 오차는 아직 보정하지 않음. 귀 간격이 실제 머리 박스 폭과 같다는 주장은 하지 않음.
- 합성 회귀 테스트: 25/50% 경계, 반대쪽 이동, 왼손, 미러, 수동 방향, 낮은 검출 신뢰도.

- 실제 옆얼굴 영상에서 귀 x간격이 2.17px여서 머리 폭 추정 불가. 사용자 제시 대체 기준(어깨 너비 7% 주의/12% 감지) 적용. 어깨 폭도 최소 유효 폭 이하이면 보류. 분모와 임계값을 결과에 명시하며 두 정규화 비율을 직접 동일시하지 않음.


## 기본 사용자 흐름 간소화
- 갤러리 선택 후 별도의 영상선택 확인 버튼 없이 스윙 확인 화면 진입.
- 기본 흐름: 영상 선택/촬영 → 영상 확인 및 스윙 분석하기 → 결과. 구간/네 자세/샷 기록 순차 단계를 제거.
- 시점 수정은 스윙 확인 화면의 상단 톱니바퀴에서만 진입. 자동시점 유효 시 곧바로 분석. 자동시점 누락 시 임의 시점을 생성하지 않고 다른 영상 또는 설정 수정 안내.
- 저장 event_source는 user_accepted_selected_events로 기록(각 자세를 수동 검증했다고 기록하지 않음).
- 샷 기록은 결과의 더 보기 메뉴에 선택 기능으로 유지. SLM 설정/디버그 페이지/공 및 타깃 좌우 질문을 기본 화면에서 제거.
- 결과에 미구현 항목 카드를 나열하지 않음. 원시 측정 상세는 더 보기 메뉴에 유지.


## 영상 확인 화면 제거
기본 흐름은 영상 선택/촬영 → 자동 분석 진행 → 스윙 결과. PoseTrimmingScreen(autoAnalyze:true)는 초기화/자동시점 추출/분석만 수행하고 확인 UI는 표시하지 않는다. 완료 시 pushReplacement로 결과를 열어 뒤로 가기에도 확인 화면이 남지 않도록 함.
결과 톱니바퀴의 자세 시점 수정에서만 편집 모드 진입. 수정 후 재분석하고 기존 결과 화면으로 복귀. 자동시점 누락/분석 오류 때는 결과를 만들지 않고 간결한 실패 안내와 다른 영상 선택/설정 진입을 제공.
자동 저장 source=automatic_selected_events. 기존 수동 및 사용자 승인 저장 기록도 재사용 가능하도록 로더 호환 처리.


## 얼리 스탠드업 앱 판정 추가
- 어드레스 어깨중심–골반중심선의 수직 대비 절대 기울기에서 다운스윙~임팩트의 기울기를 뺀 값. 필터링된 최대 감소량을 사용하고 음수는 표시값 0도로 처리(원래 부호값 별도 보존).
- 개발 초기 앱 임계값: 5도 미만 기준 이내, 5~10도 미만 주의, 10도 이상 감지. 코치/데이터 기반으로 검증된 공통 정상범위라는 의미가 아님. threshold_basis=initial_app_rule.
- 기존 관절 신뢰도/프레임 범위/70% 커버리지/median3/100ms 간격 게이트 재사용. 임팩트 이후 피니시 일어섬은 제외.
- standing_up_check 별도 생성, 9패턴 원시 측정 계약 유지. 결과 화면에 스웨이/얼리 스탠드업 2개 카드 표시. 감지 시 준비자세 숙임을 유지하는 느린 스윙 안내.
- 경계값, 미러, 지속 변화, 단발성 튐, 피니시만 일어섬, 측정 누락 시험 통과.
- 개념 참고: https://www.mytpi.com/golfmag/bullseye (기본 숙임 유지). 위 5/10도 수치는 이 자료에서 가져온 것이 아님.


## 배치기 판정 (발 길이 기준)
- 사용자 제시 10% 주의/25% 감지를 앱 근사 규칙으로 적용. threshold_basis=user_selected_proxy_rule. 임계값이 검증된 표준이라고 주장하지 않는다.
- 어드레스 양발 heel/footIndex 좌표 중 유효하고 화면상 길이가 더 긴 발을 사용(원근 축소를 줄이기 위한 선택). 양 끝점 신뢰도 0.7 이상, 길이 화면 대각선 1% 이상 필요. 발 길이가 없으면 다른 분모에 같은 임계값을 적용하지 않는다.
- 어드레스→임팩트의 골반 관절 중심 x변위 × 공 쪽 방향 / 어드레스 발 길이. 음수는 표시 0, signed_ratio 보존.
- 이는 실제 엉덩이 실루엣의 Tush Line 이탈 측정이 아니다. tush_line_measured=false, measurement=hip_midpoint_forward_displacement. 상세에 근사 방식 명시.
- 어드레스→임팩트 상체 기울기 감소량을 보조 지표로 제공. 상체 상승이 없다는 이유로 골반 전진 판정을 막지 않는다. 얼리 스탠드업과 별도 카드로 표시.
- 누락/미확인시점/촬영방향/공방향/프레임크기 검증. 카메라 보정/몸통회전 보정은 미구현.
- 합성 경계 10/25%, 미러, 반대 이동, 발 좌표와 관절 신뢰도 누락 시험 통과.


## 클럽 미지정 연속 프레임 분석 누락 수정
실제 SwingProvider.runAnalysis에 Driver/7i 전용 분기가 남아 unknown 클럽에서 motionSamples가 비어 있었다. 키프레임 기반 스웨이/배치기는 계산되는 반면 연속 샘플 기반 standing_up만 unavailable이 되는 원인. unknown도 추출 대상으로 포함.
기존 trajectoryCheck는 추출 함수를 직접 실행하여 이 provider 경로 누락을 탐지하지 못했다. providerCheck는 실제 SwingProvider를 별도 인스턴스로 생성하여 저장 review 시점과 unknown 클럽으로 runAnalysis를 실행한다.
향후 영상별 .analysis.json에 클럽/촬영방향/이벤트/연속샘플수/항목별 결과를 기록. 로그 저장 실패는 분석 결과 반환을 막지 않음.


## 치킨윙 리드 팔꿈치 근사 규칙
- 후방 포함, 리드 팔 어깨/팔꿈치/손목이 유효한 영상에서 측정. 오른손잡이 왼팔, 왼손잡이 오른팔.
- 임팩트 팔꿈치 각도 대비 임팩트 직후 150ms 이내의 굽힘 증가. median3, 70% 관절 커버리지, 최대 100ms 간격 조건 유지. 후기 팔로스루/피니시는 제외.
- 초기 앱 기준 15도 미만 기준 이내, 15~30도 미만 주의, 30도 이상 감지. threshold_basis=initial_elbow_proxy_rule. 검증된 표준 임계값이 아님.
- 팔꿈치 추가 굽힘만 검토하므로 이미 임팩트에서 굽혀져 유지된 팔이나 손목 컵핑은 판정하지 못함. 2D 팔 회전/임팩트 시점 오차/슬로모션 시간축의 영향이 있음.
- 참고 https://www.mytpi.com/improve-my-game/swing-characteristics/chicken-winging 는 리드 팔꿈치 굽힘/손목 형태를 설명함. 위 각도와 150ms 창은 자료에서 인용한 값이 아닌 앱 개발 기준.
- 합성 테스트: 15/30 경계, 좌우 반전, 왼손잡이, 트레일 팔 제외, 피니시 제외, 손목 저신뢰도 제외.


## 헤드업 머리 상승 근사 규칙
- head_up_check 추가. 어드레스 양눈 중심의 y보다 다운스윙~임팩트(탑 이후, 임팩트 포함)에 양눈 중심이 올라간 양을 어드레스 어깨중심–골반중심 길이로 정규화.
- 초기 앱 기준 10% 주의/20% 감지. threshold_basis=initial_head_rise_proxy_rule. 검증된 골프 정상범위가 아니며 고개 회전·시선 이동을 측정한 것도 아님.
- 3개 이상 유효 샘플, 70% 커버리지, median3, 인접100ms 이하. 음수 표시0/원본 signed_ratio 보존. 임팩트 이후 상승 제외.
- 카메라 상승/회전/프레임 투영 영향은 미보정. 어드레스 아래로 숙였다가 다시 올라오지만 어드레스 높이를 넘지 않은 경우는 감지하지 않음.
- 합성 10/20% 경계/미러/단발성 튐/임팩트 이후 변화/저신뢰도 테스트 통과.


## 백스윙 뒷무릎 펴짐 근사 규칙
- trail_knee_check: 어드레스→탑의 뒷무릎(오른손 오른무릎/왼손 왼무릎) Hip-Knee-Ankle 2D각도 증가.
- 초기 앱 규칙: 증가15도 이상 주의, 증가25도 이상 AND 탑170도 이상 감지. 두 조건이 충족되지 않은 큰 증가도 주의까지만. 검증된 정상범위나 임상적 무릎 잠김 판정이 아님.
- 관절 신뢰도/화면 크기/시점 확인 게이트 적용. 음수 표시0, signed_change_deg 보존. 실제 3D 회전 및 카메라 보정 미구현.
- 참고 https://www.golfsmartacademy.com/golf-tips/insight-does-straightening-the-trail-leg-increase-hip-rotation/ 는 뒷다리 펴짐/골반회전 관계를 다룸. 위 임계값을 제공하는 근거는 아니며 개발 초기 앱 기준으로 별도 설정.
- 합성 좌우/미러/두조건조합/굽힘/저신뢰도/미확인시점 시험 통과.


## 2026-09-18: representative faults and experimental club tracking

- Trail-knee extension is reference-only (`measured_not_classified`), with no grade or fault threshold. It is removed from normal result/review cards. Natural knee extension must not be diagnosed as a standalone error.
- Added `ClubTrackingService`: wrist-anchored narrow moving-line candidates, arm-direction rejection, competing-angle rejection and temporal continuity checks. Duplicate decoded-image signatures do not count as independent observations. The signature is a lightweight sampled-image check, not native PTS verification.
- Candidate coordinates live in `shaft_candidate`, never in verified `club`. `identity_verified` and `head_detected` remain false. A visible line endpoint is not the club head.
- Added `OverTheTopService` experimental matching of backswing and early-downswing shaft rays at comparable grip heights. Comparable visible distances are used without extrapolating to a guessed head. Requires rear view, direction, event order, coverage and neighboring observations; no grade/normal/fault verdict is emitted.
- Normal results are unchanged. Optional Settings → measurement details → club tracking opens extracted-frame overlays for visual verification. Temporary review images are removed on navigation/disposal.
- Synthetic checks exercise moving versus stationary lines, missing joints, image duplicates, temporal gaps, matching, normalization, direction/view gates and prevention of unvalidated diagnoses. They do not establish golf diagnostic accuracy.
- First real phone run: 99 samples in 38.9 seconds; 26 temporally supported candidates before duplicate-image rejection, but zero matched backswing/down pairs. Visual inspection found background confusion near the top and missing/foreshortened shaft visibility. Do not weaken gates merely to produce a diagnosis. Subsequent final-version device results are recorded in workspace `outputs/club_tracking/`.
- Automatic over-the-top diagnosis remains unfinished: line candidates need identity validation and representative labeled-video evaluation before enabling a result card. Current evidence is explicitly experimental.

Final installed build (2026-09-18): APK 146,306,774 bytes; build/install successful; standalone club checks and nine-pattern checks passed; analysis server reported no ERROR/WARNING for changed files (style INFO remains).
- Phone case 0: 108 requested samples, 39269 ms total, 24 supported shaft candidates, 0 matched pairs. Status unavailable: insufficient_continuous_shaft_pairs. No over-the-top diagnosis emitted.
- Phone case 1: 99 requested samples, 38103 ms total, 23 supported shaft candidates, 0 matched pairs. Status unavailable: insufficient_continuous_shaft_pairs. No over-the-top diagnosis emitted.
