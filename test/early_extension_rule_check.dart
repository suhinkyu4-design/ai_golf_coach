import 'package:ai_golf_coach/services/swing_fault_features.dart';
FrameGeometry frame(double dx,{bool mirror=false,bool feet=true,bool low=false}) {
 final pts={'leftHip':[300.0+dx,500.0],'rightHip':[320.0+dx,500.0],
 'leftShoulder':[360.0+dx,300.0],'rightShoulder':[380.0+dx,300.0],
 if(feet)'leftHeel':[200.0,800.0],if(feet)'leftFootIndex':[300.0,800.0]};
 return FrameGeometry.read({'t_ms':dx==0?0:1000,'width':1000,'height':1000,'landmarks':[
 for(final p in pts.entries){'name':p.key,'x':mirror?999-p.value[0]:p.value[0],
 'y':p.value[1],'likelihood':low?0.2:0.99}]})!;
}
void main(){
 for(final mirror in [false,true]) {
 for(final c in [[-25.0,'within_rule'],[9.0,'within_rule'],[10.0,'warning'],[24.0,'warning'],[25.0,'early_extension']]) {
 final r=SwingFaultFeatures.earlyExtensionCheck(frame(0,mirror:mirror),frame(c[0] as double,mirror:mirror),rear:true,confirmed:true,ballSign:mirror?-1:1);
 if(r['grade']!=c[1] || r['tush_line_measured']!=false || r['diagnosis']!=null)throw StateError('threshold/mirror/proxy');
 }
 }
 for(final f in [frame(0,feet:false),frame(0,low:true)]) {
 if(SwingFaultFeatures.earlyExtensionCheck(f,frame(30),rear:true,confirmed:true,ballSign:1)['status']!='unavailable')throw StateError('missing');
 }
 if(SwingFaultFeatures.earlyExtensionCheck(frame(0),frame(30),rear:false,confirmed:true,ballSign:1)['reason']!='different_view_required')throw StateError('view');
 if(SwingFaultFeatures.earlyExtensionCheck(frame(0),frame(30),rear:true,confirmed:true)['reason']!='ball_direction_unknown')throw StateError('direction');
 print('EARLY_EXTENSION_RULE_CHECK_PASSED');
}
