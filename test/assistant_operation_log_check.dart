import '../lib/services/assistant_operation_log.dart';
void main() {
 final log=AssistantOperationLog();
 final now=DateTime(2026,9,23,12);
 void check(bool value,String label) { if(!value) throw StateError(label); }
 check(log.explain('촬영 실패 이유',now:now)==null,'no invented error');
 log.fail('camera','CameraAccessDenied /private/video.mp4',at:now);
 check(log.explain('촬영이 실패한 이유',now:now)!.contains('권한'),'known error');
 check(!log.explain('촬영 오류',now:now)!.contains('/private'),'redaction');
 check(log.explain('분석 실패',now:now)==null,'unrelated stage');
 check(log.explain('촬영해줘',now:now)==null,'normal command');
 check(log.explain('촬영 실패',now:now.add(const Duration(minutes:31)))==null,'expiry');
 log.success('camera');
 check(log.explain('촬영 실패',now:now)==null,'successful retry');
 log.fail('save','ENOSPC',at:now);
 check(log.explain('저장 실패',now:now)!.contains('공간'),'storage failure');
 log.fail('analysis','secret stack',at:now);
 check(log.explain('분석이 안돼',now:now)!.contains('원인은 확인되지'),'unknown cause');
 log.fail('selection','MissingPluginException',at:now);
 check(log.explain('갤러리 선택 오류',now:now)!.contains('기기 기능 연결'),'selection');
 log.begin();
 check(log.explain('저장 실패',now:now)==null,'new operation clears stale');
 print('11 operation log checks passed');
}
