enum AssistantScreenContext {
  analysisFailure,
  cameraFailure;

  String get question => switch(this) {
    analysisFailure => '왜 분석을 완료하지 못했나요? 다음에는 어떻게 하면 되나요?',
    cameraFailure => '촬영 화면에서 오류가 났어요. 어떻게 하면 되나요?',
  };
}
