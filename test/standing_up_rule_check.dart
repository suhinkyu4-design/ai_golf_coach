import 'dart:math' as math;
import 'package:ai_golf_coach/models/swing_model.dart';
import 'package:ai_golf_coach/services/swing_fault_features.dart';
Map<String,dynamic> frame(int t,double angle,{bool mirror=false}) {
 final x=400+100*math.sin(angle*math.pi/180), y=600-100*math.cos(angle*math.pi/180);
 return {'t_ms':t,'width':1000,'height':1000,'landmarks':[
 for(final side in ['left','right'])
 for(final joint in ['Hip','Shoulder'])
 {'name':'$side$joint','x':mirror?999-(joint=='Hip'?400.0:x):(joint=='Hip'?400.0:x),
 'y':joint=='Hip'?600.0:y,'likelihood':.99}]};
}
Map run({double drop=0,bool spike=false,bool mirror=false,bool late=false,bool duplicates=false}) {
 final swing=SwingModel(swingId:'t',createdAt:DateTime(2026),videoPath:'',view:SwingView.rear,
 handedness:Handedness.right,club:'unknown',durationMs:1200,fps:60,
 eventsMs:{'address':100,'top':500,'impact':800,'finish':1100});
 final samples=[for(var t=510;t<=1100;t+=10)
 frame(t,30-((late?t>800:t<=800)?(spike?(t==650?drop:0):drop):0),mirror:mirror)];
 if(duplicates)for(final row in samples)if((row['t_ms'] as int)%20==0)row['shaft_candidate']={'duplicate_frame_of_t_ms':(row['t_ms'] as int)-10};
 return SwingFaultFeatures.analyze(swing:swing,reviewed:{
 for(final e in swing.eventsMs.entries)e.key:frame(e.value,30,mirror:mirror)},
 samples:samples,confirmed:true)['standing_up_check'] as Map;
}
void main(){
 for(final item in [[-3.0,'within_rule'],[4.99,'within_rule'],[5.0,'warning'],[9.99,'warning'],[10.0,'standing_up']]) {
 final result=SwingFaultFeatures.classifyStandingUp({'status':'measured_not_classified','peak':{'value':item[0],'t_ms':700}});
 if(result['grade']!=item[1])throw StateError('boundary');
 }
 for(final m in [false,true]) {
 if(run(drop:15,mirror:m)['grade']!='standing_up')throw StateError('sustained mirrored');
 }
 if(run(drop:20,spike:true)['grade']!='within_rule')throw StateError('isolated spike');
 if(run(drop:20,late:true)['grade']!='within_rule')throw StateError('finish extension is normal timing');
 if(SwingFaultFeatures.classifyStandingUp({'status':'unavailable','reason':'insufficient_joint_samples'})['status']!='unavailable')throw StateError('missing');
 if(run(drop:15,duplicates:true)['grade']!='standing_up'||run(drop:0,duplicates:true)['grade']!='within_rule')throw StateError('duplicate request coverage');
 print('STANDING_UP_RULE_CHECK_PASSED');
}
