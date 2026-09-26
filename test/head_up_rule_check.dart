import 'package:ai_golf_coach/services/swing_fault_features.dart';
Map<String,dynamic> frame(int t,double rise,{bool mirror=false,bool low=false})=>{
 't_ms':t,'width':1000,'height':1000,'landmarks':[
 for(final name in ['leftEye','rightEye','leftShoulder','rightShoulder','leftHip','rightHip'])
 {'name':name,'x':mirror?599.0:400.0,'y':name.endsWith('Eye')?200-rise:name.endsWith('Hip')?500.0:300.0,
 'likelihood':low?0.2:0.99}]};
Map run(double rise,{bool mirror=false,bool spike=false,bool late=false,bool low=false})=>
 SwingFaultFeatures.headUpCheck(FrameGeometry.read(frame(100,0,mirror:mirror)),[
 for(var t=810;t<=1100;t+=20)frame(t,(late?t>1000:true)?(spike?(t==850?rise:0):rise):0,mirror:mirror,low:low)],
 topMs:800,impactMs:1000,confirmed:true);
void main(){
 for(final c in [[-40.0,'within_rule'],[19.0,'within_rule'],[20.0,'warning'],[39.0,'warning'],[40.0,'head_up']]){
 for(final mirror in [false,true])if(run(c[0] as double,mirror:mirror)['grade']!=c[1])throw StateError('boundary/mirror');
 }
 if(run(80,spike:true)['grade']!='within_rule')throw StateError('spike');
 if(run(80,late:true)['grade']!='within_rule')throw StateError('postimpact');
 if(run(40,low:true)['status']!='unavailable')throw StateError('low quality');
 final repeated=[for(var t=810;t<=990;t+=20){...frame(t,80),
   'shaft_candidate':{'duplicate_frame_of_t_ms':810}}];
 final duplicateResult=SwingFaultFeatures.headUpCheck(FrameGeometry.read(frame(100,0)),repeated,
   topMs:800,impactMs:1000,confirmed:true);
 if(duplicateResult['status']!='unavailable')throw StateError('repeated decoded image counted as sustained head rise');
 if(FrameGeometry.read({...frame(900,80),'near_shaft_candidate':{'duplicate_frame_of_t_ms':810}})!=null)
   throw StateError('duplicate near-frame accepted as independent pose');
 for(final rise in [0.0,80.0]) {
   final upsampled=[for(var t=810;t<=990;t+=10){...frame(t,rise),
     if((t-810)%20!=0)'shaft_candidate':{'duplicate_frame_of_t_ms':t-10}}];
   final result=SwingFaultFeatures.headUpCheck(FrameGeometry.read(frame(100,0)),upsampled,
     topMs:800,impactMs:1000,confirmed:true);
   if(result['grade']!=(rise==0?'within_rule':'head_up'))throw StateError('30fps evidence penalized by duplicate requests');
 }
 print('HEAD_UP_RULE_CHECK_PASSED');
}
