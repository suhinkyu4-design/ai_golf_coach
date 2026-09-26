# 기기 내 측정 설명 모델

현재 기능은 검증된 2D 관절 수치 하나를 설명한다. 골프 자세의 정상 범위,
결함 원인, 개인별 교정 처방을 생성하는 모델이 아니다. 타이밍·샷 수치·참고 자료
전체를 설명하는 모델로 확장하려면 별도 데이터와 평가가 필요하다.

## 모델과 앱 동작

- 기본 모델 Qwen/Qwen3-0.6B + CaddieSet 합성 설명 LoRA, 병합 후 Q8_0.
- `golf_slm_q8_0.gguf`, 639,446,720 bytes.
- SHA-256: `72f3911c4e922c63b2b5ccafabadada241d010e6fb86a6edb3b0daf0e1e251b1`.
- 결과 화면 오른쪽 위 설정에서 모델 파일을 한 번 등록한다. 파일 크기와 해시를 확인한 뒤 앱 전용 저장소에 보관한다. 현재 테스트 폰에는 등록 완료.
- 분석 시 모델이 준비되어 있으면 자동으로 사용한다. 사용할 수 있는 수치가 없으면 실행하지 않는다.
- 모델 미등록·실행 실패 시 기존 요약을 유지한다. 응답의 숫자, 관절명, 시점, 근거 ID, 문장 형식이 다르면 검증된 수치 설명으로 대체한다.
- 왼손/오른손 사용자 구분을 추측하지 않고 실제 `joint_names`로 좌우 관절을 정한다.
- 현재 Android 9(API 28) 이상 arm64 대상, CPU 4 threads, context 2048, 최대 출력 256 tokens, 90초 제한. 실행 종료 후 프로세스/임시 파일을 정리한다.
- 원문 설명은 생성 응답 검사를 통과한 경우에만 표시한다. `slm_executed`와 `slm_output_used`를 구분한다.

## 입력 형식

첫 유효 관절만 넣어 불필요한 결측/메타데이터를 제외한다. Colab 점검에서 7/7 생성 응답 통과,
결측 2개는 실행 없이 처리했으며 중앙 응답 시간은 CPU 2 threads에서 약 17.4초였다.
작은 모델이 공백 차이에 민감하므로 Python `json.dumps`와 같은 `, ` 및 `: ` 구분자,
LF 줄바꿈, Qwen3 `enable_thinking=False` 템플릿을 유지한다.
`test/fixtures/slm_impact_prompt.txt`는 폰에서 검증한 입력의 정확한 텍스트이다.

## 네이티브 빌드

Windows에서 설치된 NDK 27.0.12077973 및 CMake 3.22.1로 실행한다.

```powershell
python tool/build_slm_android.py --sdk C:/Users/IBCenter/AppData/Local/Android/sdk
flutter build apk --debug --target-platform android-arm64
```

llama.cpp revision은 `79bfc1d43a2e1e790f455522e0b4edbef7e9d22c`로 고정한다.
실행 파일은 `libgolf_slm.so` 이름으로 APK의 native library 경로에 묶는다.
공유 라이브러리 JNI 호출이 아니라 설치된 실행 파일의 별도 프로세스를 사용한다.
`useLegacyPackaging` 및 `extractNativeLibs` 설정을 유지해야 한다.
앱 자체 파일 경로의 실행 파일을 내려받아 실행하는 방식이 아니다.
native 바이너리는 위 소스로 다시 만들 수 있으며 관련 라이선스는 APK assets에 포함한다.

이 컴퓨터의 Codex 실행 환경에서는 Flutter의 하위 프로세스 생성이 `CreateFile failed 5`로 실패했다.
이번 검증 APK는 동일 SDK의 frontend_server를 직접 실행해 현재 Dart 소스를 컴파일한 후,
JDK 17로 Gradle `assembleDebug`를 실행해 묶었다. APK 내부 kernel 해시가 새 컴파일 결과와 일치함을 확인했다.
Java 25 대신 JDK 17로 Android 빌드를 확인했다. 일반 환경에서는 위 표준 Flutter 빌드를 우선 사용한다.

## 검사

```powershell
dart test/slm_measurement_check.dart
```

숫자·시점·관절명 오류, 결측·신뢰도, 좌우 해석, 입력 형식을 검사한다.
디버그 빌드의 기존 인증된 Dart VM Service에는 `ext.golf.slmCheck`가 등록된다.
사용자 데이터를 받지 않는 고정 공개 사례 2개로 실제 MethodChannel과 네이티브 모델을 검사한다.
assert 안에서 등록하므로 release에는 등록되지 않는다.

2026-09-17 테스트 폰 SM-F741N에서 최신 앱 MethodChannel 점검 2/2 통과.
정면 7,936ms, 이전 오류 사례 7,357ms. 최초 요청에는 모델 해시 검증도 포함한다.
별도 실행 도구의 첫 테스트 최대 RSS는 927,516KiB(약 906MiB)였으며 앱 전체 메모리 수치는 아니다.
새 영상의 교정 정확도나 다양한 기기의 성능을 보증하는 결과가 아니다.


### Direct compiler plugin registration (2026-09-17 fix)

When bypassing `compileFlutterBuildDebug`, the frontend compiler must include the generated Dart plugin registry, following Flutter `compile.dart`:

```text
--source <absolute-file-URI-of-.dart_tool/flutter_build/dart_plugin_registrant.dart>
--source package:flutter/src/dart_plugin_registrant.dart
-Dflutter.dart_plugin_registrant=<same-absolute-file-URI>
```

Fail the build if the generated registry is absent. Native Android registration alone is insufficient: omitting these flags left image_picker using its legacy channel and caused MissingPluginException for pickVideo. The corrected APK was installed on SM-F741N; debug `ext.golf.mediaCheck` verified the image picker native retrieveLostData call and camera enumeration (4 cameras). These checks verify channel registration, not a complete user video selection/analysis flow.
