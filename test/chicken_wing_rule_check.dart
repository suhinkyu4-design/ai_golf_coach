import 'dart:math' as math;
import 'package:ai_golf_coach/models/swing_model.dart';
import 'package:ai_golf_coach/services/swing_fault_features.dart';
Map<String,dynamic> frame(int t,{String bent='left',bool late=false,bool mirror=false,bool low=false}) {
 final pts=<String,List<double>>{};
 for(final side in ['left','right']) {
 final x=side=='left'?400.0:550.0;
 final angle=(side==bent && (late?t>950:t>800)?130.0:170.0)*math.pi/180;
 pts['${side}Shoulder']=[x,300];pts['${side}Hip']=[x,600];
 pts['${side}Elbow']=[x,400];pts['${side}Wrist']=[x+100*math.sin(angle),400-100*math.cos(angle)];
 }
 return {'t_ms':t,'width':1000,'height':1000,'landmarks':[for(final p in pts.entries)
 {'name':p.key,'x':mirror?999-p.value[0]:p.value[0],'y':p.value[1],
 'likelihood':low && p.key.endsWith('Wrist')?0.2:0.99}]};
}
Map run({Handedness hand=Handedness.right,String bent='left',bool late=false,bool mirror=false,bool low=false}) {
 final swing=SwingModel(swingId:'t',createdAt:DateTime(2026),videoPath:'',view:SwingView.rear,
 handedness:hand,club:'unknown',durationMs:1200,fps:60,eventsMs:{'address':100,'top':500,'impact':800,'finish':1100});
 return SwingFaultFeatures.analyze(swing:swing,reviewed:{for(final e in swing.eventsMs.entries)
 e.key:frame(e.value,bent:bent,late:late,mirror:mirror,low:low)},samples:[for(var t=510;t<=1100;t+=10)
 frame(t,bent:bent,late:late,mirror:mirror,low:low)],confirmed:true)['chicken_wing_check'] as Map;
}
void main(){
 for(final c in [[14.99,'within_rule'],[15.0,'warning'],[29.99,'warning'],[30.0,'chicken_wing']]) {
 if(SwingFaultFeatures.classifyChickenWing({'status':'measured_not_classified','peak':{'value':c[0],'t_ms':900}})['grade']!=c[1])throw StateError('threshold');
 }
 for(final mirror in [false,true])if(run(mirror:mirror)['grade']!='chicken_wing')throw StateError('rear/mirror');
 if(run(hand:Handedness.left,bent:'right')['grade']!='chicken_wing')throw StateError('left handed');
 if(run(bent:'right')['grade']!='within_rule')throw StateError('trail arm ignored');
 if(run(late:true)['grade']!='within_rule')throw StateError('finish ignored');
 if(run(low:true)['status']!='unavailable')throw StateError('occluded wrist');
 print('CHICKEN_WING_RULE_CHECK_PASSED');
}
