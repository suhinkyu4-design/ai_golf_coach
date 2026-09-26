import 'dart:io';
import 'dart:convert';
import '../lib/services/assistant_operation_log.dart';
Future<void> main() async {
 final dir=await Directory.systemTemp.createTemp('golf_journal_test');
 try {
 final file=File('${dir.path}/journal.json');
 final log=AssistantOperationLog(storage:file);
 void check(bool ok,String label) { if(!ok) throw StateError(label); }
 log.begin();
 log.note('스윙 시점 탐색','경고','관절 기록이 부족합니다.');
 log.note('임팩트','대체 처리','손목 높이로 추정했습니다.');
 log.success('analysis');
 final answer=await log.explainSaved('방금 오류');
 check(answer!.contains('관절 기록이 부족'),'generic recent error');
 check(answer.contains('대체 처리'),'fallback retained');
 check(answer.contains('마지막 기록: analysis · 완료'),'completion distinguished');
 final restored=AssistantOperationLog(storage:file);
 check((await restored.explainSaved('왜 분석 안됨'))!.contains('손목 높이'),'disk restored');
 check(await restored.explainSaved('촬영해줘')==null,'normal command');
 log.begin();
 check(!(await log.explainSaved('방금 오류'))!.contains('손목 높이'),'new operation isolated');
 log.reportFaults({'head_trail_check':{'status':'unavailable','reason':'insufficient_joint_samples'}});
 check((await log.explainSaved('스웨이 측정 불가'))!.contains('필요한 관절 표본'),'fault explanation');
 await file.writeAsString(jsonEncode([{'at':'2020-01-01T00:00:00','stage':'old','level':'오류','message':'stale'}]));
 check(!(await AssistantOperationLog(storage:file).explainSaved('방금 오류'))!.contains('stale'),'stale excluded');
 await file.writeAsString('broken');
 check((await AssistantOperationLog(storage:file).explainSaved('로그'))!.contains('찾지 못'),'corrupt file tolerated');
 print('9 diagnostic journal checks passed');
 } finally { await dir.delete(recursive:true); }
}
