import 'dart:math' as math;
import 'package:ai_golf_coach/services/swing_fault_features.dart';
FrameGeometry frame(double angle,{String side='right',bool mirror=false,bool low=false}) {
 final pts={'${side}Hip':[400.0,300.0],'${side}Knee':[400.0,400.0],
 '${side}Ankle':[400+100*math.sin(angle*math.pi/180),400-100*math.cos(angle*math.pi/180)]};
 return FrameGeometry.read({'t_ms':100,'width':1000,'height':1000,'landmarks':[
 for(final p in pts.entries){'name':p.key,'x':mirror?999-p.value[0]:p.value[0],'y':p.value[1],'likelihood':low?0.2:0.99}]})!;
}
void main(){
 for(final side in ['left','right'])for(final mirror in [false,true]) {
 for(final c in [[160.0,170.0,'within_rule'],[150.0,169.0,'warning'],[140.0,171.0,'trail_knee_extension'],[130.0,160.0,'warning'],[175.0,160.0,'within_rule']]) {
 final r=SwingFaultFeatures.trailKneeCheck(frame(c[0] as double,side:side,mirror:mirror),frame(c[1] as double,side:side,mirror:mirror),trail:side,confirmed:true);
 if(r['status']!='measured_not_classified' || r.containsKey('grade') || ((r['signed_change_deg'] as num)-((c[1] as double)-(c[0] as double))).abs()>1e-6)throw StateError('reference only/mirror/hand');
 }
 }
 if(SwingFaultFeatures.trailKneeCheck(frame(140,low:true),frame(175),trail:'right',confirmed:true)['status']!='unavailable')throw StateError('confidence');
 if(SwingFaultFeatures.trailKneeCheck(frame(140),frame(175),trail:'right',confirmed:false)['status']!='unavailable')throw StateError('events');
 print('TRAIL_KNEE_RULE_CHECK_PASSED');
}
