import 'package:ai_golf_coach/services/swing_fault_features.dart';
FrameGeometry frame({bool mirror=false, bool low=false, bool ambiguous=false}) {
 final points={'leftHip':[290.0,500.0], 'rightHip':[310.0,500.0],
 'leftShoulder':[350.0,300.0], 'rightShoulder':[370.0,300.0],
 'leftWrist':[ambiguous?300.0:380.0,490.0], 'rightWrist':[ambiguous?300.0:390.0,490.0]};
 return FrameGeometry.read({'t_ms':0,'width':1000,'height':1000,'landmarks':[
 for(final p in points.entries) {'name':p.key,'x':mirror?999-p.value[0]:p.value[0],
 'y':p.value[1],'likelihood':low && p.key=='leftWrist' ? 0.2 : 0.99}]})!;
}
void main(){
 for(final mirrored in [false,true]) {
  if(SwingFaultFeatures.inferBallSide(frame(mirror:mirrored))['sign']!=(mirrored?-1:1))throw StateError('direction');
 }
 for(final f in [frame(low:true),frame(ambiguous:true)]) {
  if(SwingFaultFeatures.inferBallSide(f)['sign']!=null)throw StateError('must abstain');
 }
 print('BALL_SIDE_CHECK_PASSED');
}
