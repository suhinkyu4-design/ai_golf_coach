/// Pose coverage is an observation, not an autofocus/blur diagnosis.
class CaptureQualityGuidance {
  static const retry = '다시 한번 촬영해 주세요.\n① 실제 스윙할 위치에 서서 머리부터 발끝까지 화면에 들어오는지 확인하세요. 너무 작게 찍히지 않게 하되 손과 클럽이 움직일 공간을 남겨 주세요.\n② 렌즈를 닦고 골퍼가 선 위치의 선명도와 밝기를 확인하세요.\n③ 폰을 단단히 고정하고 공과 클럽이 닿지 않는 곳에 두세요.\n④ 준비 자세에서 잠깐 멈춘 뒤 실제 타격과 피니시까지 담아 주세요.';
  static const advice = '촬영 전에 렌즈를 닦고, 골퍼가 설 위치에 초점이 맞아 몸이 선명하게 보이는지 확인해 주세요. 머리·손·발이 스윙 내내 화면 안에 들어오게 하고, 몸이 어둡게 보이지 않도록 조명과 역광을 확인하세요. 폰은 흔들리지 않게 고정해 주세요. 초점 불량이나 흔들림을 직접 측정한 결과는 아닙니다.';
  static Map<String,dynamic> assess(List samples) {
    const joints={'leftShoulder','rightShoulder','leftHip','rightHip','leftWrist','rightWrist','leftAnkle','rightAnkle'};
    var detected=0, usable=0;
    for(final sample in samples) {
      if(sample is! Map) continue;
      final landmarks=sample['landmarks'];
      if(landmarks is! List || landmarks.isEmpty) continue;
      detected++;
      final confident=<String>{};
      for(final point in landmarks) {
        if(point is Map && joints.contains(point['name']) && point['likelihood'] is num && (point['likelihood'] as num)>=.5) confident.add(point['name'] as String);
      }
      if(confident.length>=6) usable++;
    }
    // A guidance threshold only; never used to classify a swing fault.
    final poor=samples.isEmpty || usable/samples.length<.5;
    return {'total':samples.length,'detected':detected,'usable':usable,'poor':poor,
      'message':samples.isEmpty ? '분석할 관절 장면 기록을 확보하지 못했습니다. 영상 읽기와 장면 추출 기록부터 확인해야 합니다.'
        : detected==0 ? '분석한 ${samples.length}개 장면에서 사람 관절이 전혀 검출되지 않았습니다. 골퍼가 카메라 앵글 밖에 있거나 너무 작게 찍혔는지 먼저 확인해 주세요. 사람이 없었다고 확정한 것은 아닙니다.'
        : '$detected/${samples.length}개 장면에서 관절이 잡혔고, 주요 관절을 충분히 확인한 장면은 $usable개입니다.'};
  }
  static String? failureHelp(List samples) {
    final q=assess(samples);
    if(q['poor']!=true) return null;
    return '${q['message']}\n\n골퍼의 움직임을 따라갈 근거가 부족해 스윙 시점을 찾기 어렵습니다.\n\n$advice\n\n$retry';
  }
}
