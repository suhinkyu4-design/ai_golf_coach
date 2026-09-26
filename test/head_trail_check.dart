import 'package:ai_golf_coach/services/swing_fault_features.dart';
FrameGeometry frame(double delta,{bool mirror=false,bool low=false}) => FrameGeometry.read({
 't_ms':delta==0?0:1000,'width':1000,'height':1000,'landmarks':[
 for(final name in ['leftEye','rightEye','leftEar','rightEar','leftAnkle','rightAnkle'])
 {'name':name,'x': mirror ? 999-x(name,delta) : x(name,delta),
 'y':name.endsWith('Ankle')?800.0:200.0,'likelihood':low?0.2:0.99}]})!;
double x(String name,double delta) => name=='leftAnkle'?200.0:name=='rightAnkle'?400.0:
 (name=='leftEar'?250.0:name=='rightEar'?350.0:300.0)+delta;
void main(){
 for(final mirror in [false,true]) {
  for(final test in [[-20.0,'within_rule'],[24.9,'within_rule'],[25.0,'warning'],[49.9,'warning'],[50.0,'sway']]) {
   final out=SwingFaultFeatures.headTrailCheck(frame(0,mirror:mirror),frame(test[0] as double,mirror:mirror),rear:true,trail:'right',confirmed:true);
   if(out['grade']!=test[1] || out['diagnosis']!=null)throw StateError('rule boundary/mirror');
  }
 }
 final lefty=SwingFaultFeatures.headTrailCheck(frame(0),frame(-50),rear:true,trail:'left',confirmed:true);
 if(lefty['grade']!='sway')throw StateError('lefty direction');
 final override=SwingFaultFeatures.headTrailCheck(frame(0),frame(-50),rear:true,trail:'right',confirmed:true,targetImageSign:1);
 if(override['grade']!='sway')throw StateError('direction override');
 if(SwingFaultFeatures.headTrailCheck(frame(0,low:true),frame(50),rear:true,trail:'right',confirmed:true)['status']!='unavailable')throw StateError('low quality');
 final raw=Map<String,dynamic>.from(frame(0).raw);
 raw['landmarks']=List<dynamic>.from((raw['landmarks'] as List).where((p)=>!p['name'].endsWith('Ear')))
 ..addAll([{'name':'leftShoulder','x':250.0,'y':400.0,'likelihood':.99},
 {'name':'rightShoulder','x':350.0,'y':400.0,'likelihood':.99}]);
 for(final t in [[6.9,'within_rule'],[7.0,'warning'],[12.0,'sway']]) {
  final out=SwingFaultFeatures.headTrailCheck(FrameGeometry.read(raw),frame(t[0] as double),rear:true,trail:'right',confirmed:true);
  if(out['grade']!=t[1] || out['normalization']!='address_projected_shoulder_width')throw StateError('shoulder fallback boundary');
 }
 print('HEAD_SWAY_RULE_CHECK_PASSED');
}
