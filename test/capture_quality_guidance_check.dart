import '../lib/services/capture_quality_guidance.dart';
void main() {
 void check(bool ok) { if(!ok) throw StateError('guidance regression'); }
 check(CaptureQualityGuidance.assess([])['poor']==true);
 check(CaptureQualityGuidance.failureHelp([{'landmarks':[]}])!.contains('초점'));
 final frame={'landmarks':[for(final name in ['leftShoulder','rightShoulder','leftHip','rightHip','leftWrist','rightWrist','leftAnkle','rightAnkle']) {'name':name,'likelihood':.9}]};
 check(CaptureQualityGuidance.failureHelp([frame,frame])==null);
 check(CaptureQualityGuidance.assess([frame,{},{}])['poor']==true);
 check(CaptureQualityGuidance.advice.contains('직접 측정한 결과는 아닙니다'));
 print('5 capture guidance checks passed');
}
