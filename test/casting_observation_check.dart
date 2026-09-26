import 'dart:math' as math;
import 'package:ai_golf_coach/services/casting_observation_service.dart';
import 'package:ai_golf_coach/services/club_tracking_service.dart';
import 'package:image/image.dart' as img;

void check(bool v,String m){if(!v)throw StateError(m);}
Map<String,dynamic> frame(int t,{bool mirror=false,bool crossing=true,bool bad=false}){
  final y=crossing?650+(t-1250)*.2:600.0;
  final angle=70+(t-1000)*.2;
  double x(double v)=>mirror?999-v:v;
  final grip={'x':x(450),'y':y};
  final end={'x':x(450+130*math.cos((angle-90)*math.pi/180)),
    'y':y+130*math.sin((angle-90)*math.pi/180)};
  return {'t_ms':t,'width':1000,'height':1000,'pose_count':1,'landmarks':[
    for(final e in <String,List<double>>{
      'leftWrist':[448,y],'rightWrist':[452,y],
      'leftElbow':[448,y-100],'rightElbow':[552,y],
      'leftShoulder':[425,400],'rightShoulder':[475,400],
      'leftHip':[425,650],'rightHip':[475,650],
    }.entries){'name':e.key,'x':x(e.value[0]),'y':e.value[1],
      'likelihood':bad && e.key == 'leftElbow' ? 0.1 : 0.99}],
    'near_shaft_candidate':{'t_ms':t,'status':'line_candidate','temporally_supported':true,
      'coordinate_space':'upright_image_pixels','width':1000,'height':1000,
      'grip':grip,'shaft_end':end,'identity_verified':false,'frame_signature':'$t'}};
}
Map run(List<Map<String,dynamic>> rows,{String lead='left'})=>CastingObservationService.measure(
  samples:rows,topMs:1000,impactMs:1400,lead:lead,view:'rear',eventsConfirmed:true);
void main(){
  final rows=[for(var t=920;t<=1382;t+=33)frame(t)];
  final r=run(rows);
  check(r['status']=='experimental_observation','angle sequence: $r');
  check((r['opening_change_deg'] as num)>30,'opening not measured');
  check(r['halfway_t_ms']==1250,'actual crossing not selected');
  check(r['diagnosis']==null&&r['release_enabled']==false&&!r.containsKey('grade'),'diagnosis leaked');
  check((r['visible_segments'] as List).isNotEmpty,'visible run missing');
  final supportedRows=[for(var t=920;t<=1382;t+=33)frame(t)];
  for(final row in supportedRows){row['near_shaft_candidate']['extension_supported']=true;}
  final classified=run(supportedRows);
  check(classified['status']=='rule_classified'&&classified['grade']=='casting','supported release not classified: $classified');
  final noCross=run([for(var t=920;t<=1382;t+=33)frame(t,crossing:false)]);
  check(noCross['selected_segment']!=null && noCross['diagnosis']==null,'segment requires halfway');
  final broken=[for(var t=920;t<=1382;t+=33)frame(t)];
  broken.firstWhere((p)=>p['t_ms']==1184)['near_shaft_candidate']=null;
  check((run(broken)['visible_segments'] as List).every((p)=>p['start_t_ms']>1184 || p['end_t_ms']<1184),'bridged rejected frame');
  final duplicate=[for(var t=920;t<=1382;t+=33)frame(t)];
  for(final p in duplicate){if((p['t_ms'] as int)>1118)p['near_shaft_candidate']['duplicate_frame_of_t_ms']=1118;}
  check(run(duplicate)['selected_segment']==null,'duplicate images increased run');
  final refinedRows=[for(var t=920;t<=1382;t+=33)frame(t)];
  final refinedRow=refinedRows.firstWhere((r)=>r['t_ms']==1085);
  refinedRow['casting_landmarks']=[for(final p in refinedRow['landmarks'] as List)Map<String,dynamic>.from(p)];
  final landmarks=refinedRow['landmarks'] as List;
  final wrist=landmarks.firstWhere((p)=>p['name']=='leftWrist');
  landmarks.firstWhere((p)=>p['name']=='leftElbow')['y']=(wrist['y'] as num)-5;
  refinedRow['arm_refinement']=<String,dynamic>{'status':'accepted'};
  final refinedResult=run(refinedRows);
  final refinedAngle=(refinedResult['observations'] as List).firstWhere((p)=>p['t_ms']==1085);
  check(refinedAngle['arm_source']=='crop_with_neighbor_checks'&&
    ((refinedAngle['angle_deg'] as num)-87).abs()<1e-6,'accepted crop not used');
  refinedRow['arm_refinement']['status']='rejected';
  check(!(run(refinedRows)['observations'] as List).any((p)=>p['t_ms']==1085),'rejected crop used');
  final mirrored=run([for(var t=920;t<=1382;t+=33)frame(t,mirror:true)]);
  check(((mirrored['opening_change_deg'] as num)-(r['opening_change_deg'] as num)).abs()<1e-6,'mirror changed angle');
  final right=run(rows,lead:'right');
  check(right['lead_side']=='right'&&right['top_angle_deg']!=r['top_angle_deg'],'lead arm selection');
  check(run([for(var t=920;t<=1382;t+=33)frame(t,crossing:false)])['reason']=='halfway_not_observed','fabricated halfway');
  check(run([for(var t=920;t<=1382;t+=33)frame(t,bad:true)])['status']=='unavailable','low confidence accepted');
  final gapped=[for(final row in rows)if((row['t_ms'] as int)<1050||(row['t_ms'] as int)>1230)row];
  check(run(gapped)['status']=='unavailable','occlusion interpolated');
  final isolatedHalf=[for(var t=920;t<=1382;t+=33)frame(t)];
  for(final row in isolatedHalf){
    if([1151,1184,1217,1283,1316,1349].contains(row['t_ms']))row['near_shaft_candidate']=null;
  }
  final isolatedResult=run(isolatedHalf);
  check(isolatedResult['reason']=='halfway_angle_sequence_unavailable',
    'isolated halfway angle confused with absent shaft: $isolatedResult');
  check(isolatedResult['halfway_raw_angle_deg'] is num&&!isolatedResult.containsKey('grade'),
    'single frame was classified');
  // A short visible shaft is usable for orientation, but not as a club head.
  final bg=img.fill(img.Image(width:400,height:400),color:img.ColorRgb8(100,100,100));
  final image=img.Image.from(bg);
  img.drawLine(image,x1:200,y1:240,x2:230,y2:210,color:img.ColorRgb8(245,245,245),thickness:2);
  final pose={'t_ms':100,'width':400,'height':400,'pose_count':1,'landmarks':[
    for(final e in <String,List<double>>{'leftWrist':[199,240],'rightWrist':[201,240],
      'leftShoulder':[170,180],'rightShoulder':[210,180],
      'leftHip':[170,280],'rightHip':[210,280]}.entries)
      {'name':e.key,'x':e.value[0],'y':e.value[1],'likelihood':.99}]};
  final short=ClubTrackingService.detect(image,pose,background:bg,nearGrip:true);
  check(short['status']=='line_candidate','short shaft lost: $short');
  check(short['head_detected']==false,'short shaft promoted to head');
  check(ClubTrackingService.angleDistance((short['angle_deg'] as num).toDouble(),315)<5,'clear original shaft changed');
  check(ClubTrackingService.detect(image,pose,background:image,nearGrip:true)['status']=='unavailable','static short line');
  final offsetImage=img.Image.from(bg);
  img.drawLine(offsetImage,x1:207,y1:247,x2:247,y2:207,color:img.ColorRgb8(245,245,245),thickness:2);
  final shifted=ClubTrackingService.detect(offsetImage,pose,background:bg,nearGrip:true);
  check(shifted['status']=='line_candidate','offset grip shaft lost: $shifted');
  check((shifted['grip_offset_px'] as num).abs()>0,'grip offset not searched');
  print('CASTING_OBSERVATION_CHECK_PASSED');
}
