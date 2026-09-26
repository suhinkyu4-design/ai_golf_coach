class CorrectionGuide {
  final String title, focus;
  final List<String> steps;
  const CorrectionGuide(this.title, this.focus, this.steps);
  static bool eligible(Map? rule) => rule?['status'] == 'rule_classified' &&
    const ['warning','sway','early_extension','standing_up','chicken_wing','head_up','casting','over_the_top'].contains(rule?['grade']);
  static const guides = <String, CorrectionGuide>{
    'head_trail_check': CorrectionGuide('옆으로 밀기보다 제자리에서 회전하기', '머리 이동을 줄이는 느낌으로 작은 백스윙', [
      '공 없이 편안한 어드레스를 만드세요.', '발바닥 안쪽의 지지를 느끼며 작은 백스윙을 천천히 해 보세요.', '목을 고정하지 말고, 다시 촬영해 머리 이동을 비교하세요.']),
    'early_extension_check': CorrectionGuide('골반이 공 쪽으로 나오는 움직임 줄이기', '어드레스의 골반 깊이를 의식하며 회전', [
      '어드레스에서 엉덩이 뒤쪽 위치를 기억하세요.', '공 없이 골반이 앞으로 튀어나오지 않도록 작게 회전해 보세요.', '임팩트 위치에서 멈춰 준비 자세의 골반 위치와 비교하세요.']),
    'standing_up_check': CorrectionGuide('상체가 먼저 펴지는 움직임 줄이기', '임팩트 전까지 숙임을 유지하는 느낌', [
      '편안하게 숙인 어드레스로 시작하세요.', '허리를 굳히지 말고 작은 스윙으로 몸통을 회전해 보세요.', '임팩트 위치까지 천천히 움직여 상체가 먼저 들리는지 확인하세요.']),
    'chicken_wing_check': CorrectionGuide('팔만 접기보다 몸통과 함께 지나가기', '작은 스윙으로 팔과 몸통의 움직임 연결', [
      '공 없이 허리 높이의 작은 스윙을 준비하세요.', '공을 지나는 구간에서 몸통과 팔이 함께 돌아가게 해 보세요.', '팔꿈치를 억지로 잠그지 말고, 지나간 직후 급하게 접히는지 확인하세요.']),
    'head_up_check': CorrectionGuide('공을 치기 전에 일어나는 움직임 줄이기', '목을 고정하지 않고 편안하게 임팩트 통과', [
      '어드레스에서 머리 높이를 확인하세요.', '작고 느린 빈스윙으로 임팩트 위치까지 움직이세요.', '머리를 억지로 누르지 말고, 타격 전에 몸과 함께 들리는지 비교하세요.']),
    'over_the_top_check': CorrectionGuide('팔을 바깥으로 던지는 움직임 줄이기', '작은 다운스윙으로 내려오는 경로 확인', [
      '공 없이 작은 백스윙에서 잠시 멈추세요.', '손을 바깥으로 밀기보다 몸통과 함께 천천히 내려 보세요.', '샤프트 비교 화면에서 백스윙과 다운스윙의 경로를 다시 확인하세요.']),
    'casting_check': CorrectionGuide('초반부터 클럽을 던지는 움직임 줄이기', '손목을 강제로 고정하지 않고 천천히 전환', [
      '공 없이 작은 백스윙으로 시작하세요.', '손으로 클럽을 급하게 던지지 말고 몸통과 팔이 함께 내려오게 해 보세요.', '하프 스윙을 다시 촬영해 다운스윙 초반의 팔·샤프트 각도를 비교하세요.']),
  };
}
