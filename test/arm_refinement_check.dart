import 'dart:convert';
import 'package:ai_golf_coach/services/arm_refinement_service.dart';
void check(bool value,String reason){if(!value)throw StateError(reason);}
Map<String,dynamic> row(int t,{bool short=false,double ex=400})=>{
  't_ms':t,'width':1000,'height':1000,'pose_count':1,'landmarks':[
    for(final e in <String,List<double>>{
      'leftShoulder':[400,200],'rightShoulder':[450,200],
      'leftHip':[400,400],'rightHip':[450,400],
      'leftElbow':[ex,short?390:300],'leftWrist':[400,400],
    }.entries){'name':e.key,'x':e.value[0],'y':e.value[1],'likelihood':.99}]};
void main(){
  final target=row(133,short:true);
  final original=jsonEncode(target['landmarks']);
  target['arm_refinement']={'landmarks':row(133)['landmarks']};
  ArmRefinementService.select([row(100),target,row(166)],'left');
  check(target['arm_refinement']['status']=='accepted','valid crop rejected');
  check(jsonEncode(target['landmarks'])==original,'original joints overwritten');
  check(target['casting_landmarks'] is List,'casting observation missing');
  final bad=row(133,short:true)..['arm_refinement']={'landmarks':row(133,ex:800)['landmarks']};
  ArmRefinementService.select([row(100),bad,row(166)],'left');
  check(bad['arm_refinement']['status']=='rejected'&&!bad.containsKey('casting_landmarks'),'implausible arm accepted');
  final isolated=row(133,short:true)..['arm_refinement']={'landmarks':row(133)['landmarks']};
  ArmRefinementService.select([row(0),isolated,row(300)],'left');
  check(isolated['arm_refinement']['reason']=='two_original_anchors_required','missing neighbors accepted');
  check(ArmRefinementService.shortArm({'t_ms':1},'left'),'invalid anchor considered valid');
  final restored=ArmRefinementService.restore([{'name':'leftWrist','x':100.0,'y':200.0,'likelihood':.9}],
    {'x':30,'y':40,'scale_x':2.0,'scale_y':4.0}).single;
  check(restored['x']==80.0&&restored['y']==90.0,'crop coordinates mapped incorrectly');
  print('ARM_REFINEMENT_CHECK_PASSED');
}
