import 'dart:convert';
import 'package:image/image.dart' as img;
import 'package:ai_golf_coach/services/club_tracking_service.dart';
import 'package:ai_golf_coach/services/over_the_top_service.dart';

void check(bool value,String message){if(!value)throw StateError(message);}
Map<String,dynamic> pose(int t)=>{'t_ms':t,'width':400,'height':400,'pose_count':1,
  'landmarks':[for(final e in <String,List<double>>{
    'leftWrist':[199,240],'rightWrist':[201,240],
    'leftShoulder':[170,180],'rightShoulder':[210,180],
    'leftHip':[170,280],'rightHip':[210,280],
    'leftElbow':[160,220],'rightElbow':[180,220],
  }.entries){'name':e.key,'x':e.value[0],'y':e.value[1],'likelihood':.99}]};
img.Image blank()=>img.fill(img.Image(width:400,height:400),color:img.ColorRgb8(100,100,100));
void main(){
  final bg=blank(),image=blank();
  img.drawLine(image,x1:200,y1:240,x2:300,y2:140,color:img.ColorRgb8(245,245,245),thickness:2);
  final positive=ClubTrackingService.detect(image,pose(100),background:bg);
  check(positive['status']=='line_candidate','synthetic shaft not found: ${jsonEncode(positive)}');
  check(ClubTrackingService.angleDistance((positive['angle_deg'] as num).toDouble(),315)<5,'wrong shaft orientation');
  check(positive['identity_verified']==false&&positive['head_detected']==false,'line mistaken for verified head');
  check(ClubTrackingService.detect(image,pose(100),background:image)['status']=='unavailable','static line accepted');
  check(ClubTrackingService.detect(bg,pose(100),background:bg)['status']=='unavailable','blank accepted');
  final competing=blank();
  img.drawLine(competing,x1:200,y1:240,x2:260,y2:180,color:img.ColorRgb8(225,225,225),thickness:2);
  img.drawLine(competing,x1:210,y1:240,x2:240,y2:240,color:img.ColorRgb8(255,255,255),thickness:2);
  final supported=ClubTrackingService.detect(competing,pose(100),background:bg,nearGrip:true);
  check(ClubTrackingService.angleDistance((supported['angle_deg'] as num).toDouble(),315)<6,'short bright patch outranked long shaft');
  check(!supported.containsKey('ranked_candidates'),'verbose diagnostics enabled by default');
  final extended=blank();
  img.drawLine(extended,x1:200,y1:240,x2:310,y2:130,color:img.ColorRgb8(245,245,245),thickness:2);
  final extendedResult=ClubTrackingService.detect(extended,pose(100),background:bg,nearGrip:true);
  check(extendedResult['extension_supported']==true,'visible distal extension not supported');
  check((extendedResult['length_px'] as num)<=85,'extension invented a measured shaft endpoint');
  final staticDistal=blank();
  img.drawLine(staticDistal,x1:263,y1:177,x2:310,y2:130,color:img.ColorRgb8(245,245,245),thickness:2);
  final staticResult=ClubTrackingService.detect(extended,pose(100),background:staticDistal,nearGrip:true);
  check(staticResult['extension_supported']==false,'static distal background treated as moving shaft');
  final missing=pose(100)..['landmarks']=[];
  check(ClubTrackingService.detect(image,missing,background:bg)['status']=='unavailable','missing hands');
  final stream=[for(final t in [100,133,166]){...positive,'t_ms':t,'frame_signature':'$t'}];
  ClubTrackingService.checkContinuity(stream);
  check(stream.every((r)=>r['temporally_supported']==true),'continuous shaft rejected');
  final duplicated=[for(final t in [100,116,133]){...positive,'t_ms':t}];
  ClubTrackingService.checkContinuity(duplicated);
  check(duplicated.every((r)=>r['temporally_supported']==false),'duplicate decoded frames counted');
  final isolated=[{...positive,'t_ms':100},{...positive,'t_ms':300},{...positive,'t_ms':500}];
  ClubTrackingService.checkContinuity(isolated);
  check(isolated.every((r)=>r['temporally_supported']==false),'gaps bridged');
  Map<String,dynamic> hypothesis(double angle)=>{
    ...positive,'angle_deg':angle,'score':.85,
  };
  final ambiguous=[
    {...positive,'t_ms':100,'frame_signature':'a','angle_deg':244.0},
    {...positive,'t_ms':133,'frame_signature':'b','status':'ambiguous','angle_deg':66.0,
      'hypotheses':[hypothesis(66),hypothesis(242)]},
    {...positive,'t_ms':166,'frame_signature':'c','angle_deg':240.0},
  ];
  ClubTrackingService.checkContinuity(ambiguous);
  check(ambiguous[1]['angle_deg']==242.0&&ambiguous[1]['temporally_supported']==true,'bidirectional choice');
  check(ambiguous[1]['identity_verified']==false,'temporal evidence claimed identity');
  final unsupported=[
    {...positive,'t_ms':100,'frame_signature':'a','angle_deg':244.0},
    {...positive,'t_ms':133,'frame_signature':'b','status':'ambiguous','angle_deg':66.0,
      'hypotheses':[hypothesis(66)]},
    {...positive,'t_ms':166,'frame_signature':'c','angle_deg':240.0},
  ];
  ClubTrackingService.checkContinuity(unsupported);
  check(unsupported[1]['status']=='ambiguous','invented unobserved shaft');
  final chain=[
    {...positive,'t_ms':100,'frame_signature':'q1','angle_deg':0.0,'status':'line_candidate'},
    {...positive,'t_ms':133,'frame_signature':'q2','angle_deg':170.0,'status':'ambiguous','hypotheses':[hypothesis(170),hypothesis(10)]},
    {...positive,'t_ms':166,'frame_signature':'q3','angle_deg':180.0,'status':'ambiguous','hypotheses':[hypothesis(180),hypothesis(20)]},
    {...positive,'t_ms':199,'frame_signature':'q4','angle_deg':30.0,'status':'line_candidate'},
  ];
  ClubTrackingService.checkContinuity(chain);
  check(chain[1]['tentative_path_candidate']['angle_deg']==10&&chain[2]['tentative_path_candidate']['angle_deg']==20,'debug path not retained');
  check(chain[1]['angle_deg']==170&&chain[1]['status']=='ambiguous'&&chain[1]['t_ms']==133,'tentative path changed measured geometry');
  check(chain[1]['identity_verified']==false&&chain[2]['temporally_supported']==false,'tentative path accepted for measurement');
  check(chain[1]['tentative_path_candidate']['measurement_eligible']==false,'tentative eligibility');
  final fork=[
    {...positive,'t_ms':100,'frame_signature':'f1','angle_deg':0.0,'status':'line_candidate'},
    {...positive,'t_ms':133,'frame_signature':'f2','status':'ambiguous','hypotheses':[hypothesis(10),hypothesis(20)]},
    {...positive,'t_ms':166,'frame_signature':'f3','status':'ambiguous','hypotheses':[hypothesis(20),hypothesis(30)]},
    {...positive,'t_ms':199,'frame_signature':'f4','angle_deg':40.0,'status':'line_candidate'},
  ];
  ClubTrackingService.checkContinuity(fork);
  check(fork[1]['status']=='ambiguous'&&fork[2]['status']=='ambiguous','arbitrary path selected');
  final extendedAnchors=[
    {...positive,'t_ms':100,'frame_signature':'e1','status':'ambiguous','angle_deg':274.0,'hypotheses':[hypothesis(224),hypothesis(274),hypothesis(250)]},
    {...positive,'t_ms':133,'frame_signature':'e2','angle_deg':228.0,'extension_supported':true},
    {...positive,'t_ms':166,'frame_signature':'e3','angle_deg':238.0,'extension_supported':true},
  ];
  ClubTrackingService.checkContinuity(extendedAnchors);
  check(extendedAnchors[0]['angle_deg']==224&&extendedAnchors[0]['temporally_supported']==true,'observed candidate not linked to image-extended anchors');
  check(extendedAnchors[0]['t_ms']==100,'hypothesis overwrote timestamp');
  final competingAnchors=[
    {...positive,'t_ms':100,'frame_signature':'c1','status':'ambiguous','angle_deg':274.0,'hypotheses':[hypothesis(224),hypothesis(220)]},
    {...positive,'t_ms':133,'frame_signature':'c2','angle_deg':228.0,'extension_supported':true},
    {...positive,'t_ms':166,'frame_signature':'c3','angle_deg':238.0,'extension_supported':true},
  ];
  ClubTrackingService.checkContinuity(competingAnchors);
  check(competingAnchors[0]['status']=='ambiguous','multiple plausible observed lines arbitrarily resolved');
  Map<String,dynamic> candidate(int t,double x)=>{
    ...positive,'t_ms':t,'temporally_supported':true,'angle_deg':315,
    'grip':{'x':x,'y':240.0},'length_px':100.0,'torso_length_px':100.0};
  final samples=[for(final t in [100,133,166,233,266,299])
    {'t_ms':t,'width':400,'height':400,'shaft_candidate':candidate(t,t>200?230:200)}];
  Map run(List<Map<String,dynamic>> rows,{bool rear=true,int? sign=1})=>OverTheTopService.measure(
    samples:rows,addressMs:0,topMs:200,impactMs:400,rear:rear,ballSign:sign,eventsConfirmed:true);
  final measured=run(samples);
  check(measured['status']=='experimental_observation','matched comparison failed');
  check(((measured['peak']['value'] as num)-.3).abs()<1e-6,'normalization');
  check(measured['diagnosis']==null&&measured['release_enabled']==false&&!measured.containsKey('grade'),'unvalidated diagnosis leaked');
  check(run(samples,rear:false)['reason']=='rear_view_required','view gate');
  check(run(samples,sign:null)['reason']=='ball_direction_unknown','direction gate');
  check((run(samples,sign:null)['pairs'] as List).length==3,'unknown direction lost visual pairs');
  final mismatched=[for(final row in samples){...row,'width':800}];
  check((run(mismatched)['pairs'] as List).isEmpty,'mismatched coordinates paired');
  final repeated=[for(final row in samples){...row,'shaft_candidate':{...row['shaft_candidate'] as Map,'duplicate_frame_of_t_ms':100}}];
  check((run(repeated)['pairs'] as List).isEmpty,'duplicate frames paired');
  check((measured['pairs'] as List).every((p)=>p['backswing'] is Map&&p['downswing'] is Map),'pair drawings absent');
  final shortOnly=[for(final row in samples){...row,'shaft_candidate':null,
    'near_shaft_candidate':{...row['shaft_candidate'] as Map,'length_px':40.0}}];
  final shortResult=run(shortOnly);
  check(shortResult['comparison_source']=='near_grip'&&shortResult['matched_pairs']==3,'short observed ray pairing');
  check(shortResult['diagnosis']==null,'short ray classified');
  check(run([])['status']=='unavailable','empty interpreted as normal');
  final scaleFull={...positive,'temporally_supported':true};
  final scaleNear={...positive,'temporally_supported':true};
  ClubTrackingService.compareScales(scaleFull,scaleNear);
  check(scaleNear['multi_scale_supported']==true,'consistent image searches rejected');
  scaleFull['angle_deg']=120;
  ClubTrackingService.compareScales(scaleFull,scaleNear);
  check(scaleNear['multi_scale_supported']==false,'different rays confirmed');
  scaleFull['angle_deg']=scaleNear['angle_deg'];scaleFull['width']=999;
  ClubTrackingService.compareScales(scaleFull,scaleNear);
  check(scaleNear['multi_scale_supported']==false,'mismatched geometry confirmed');
  print('CLUB_TRACKING_CHECK_PASSED');
}
