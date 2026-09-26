import 'dart:io';
import '../lib/services/assistant_rules.dart';
void main() {
  final r=AssistantRules.fromJson(File('assets/assistant_rules.json').readAsStringSync());
  for(final q in ['촬영이 실패한 이유','카메라가 왜 안돼','녹화 오류가 났어']) {
    final d=r.resolve(q,hasAnalysis:false,busy:false);
    if(d.intent.action!='reply'||d.actions.length!=3||!d.message!.contains('알 수 없어요')) throw StateError(q);
    for(final choice in d.actions) {
      final f=r.resolve(choice,hasAnalysis:false,busy:false);
      if(f.intent.action!='reply'||f.message==d.message||f.message==null) throw StateError(choice);
    }
  }
  if(r.resolve('카메라 열어줘',hasAnalysis:false,busy:false).intent.action!='camera') throw StateError('regression');
  print('PASS troubleshooting questions, all follow-up buttons, camera command');
}
