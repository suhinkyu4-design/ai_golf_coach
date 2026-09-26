import 'dart:io';
import 'dart:convert';
import 'package:image/image.dart' as img;
import 'package:ai_golf_coach/services/impact_detection_service.dart';
void check(bool value,String message) {if(!value) throw StateError(message);}
Future<void> main() async {
 final temp=await Directory.systemTemp.createTemp('impact_v2_');
 try {
  final samples=List.generate(10,(i)=><String,dynamic>{'t_ms':i*100,'width':200,'height':300,'landmarks':[
   {'name':'leftWrist','x':90.0,'y':[160.0,160.0,120.0,60.0,80.0,120.0,150.0,160.0,150.0,150.0][i],'likelihood':.99},
   {'name':'leftAnkle','x':75.0,'y':220.0,'likelihood':.99}]});
  Future<List<Map<String,dynamic>>> make(String name,{bool departure=true,bool club=true,bool distractor=false,bool blur=false}) async {
   final frames=<Map<String,dynamic>>[];
   for(int i=0;i<17;i++) {
    final im=img.Image(width:200,height:300);img.fill(im,color:img.ColorRgb8(35,55,35));
    if(distractor) img.fillCircle(im,x:40,y:225,radius:4,color:img.ColorRgb8(255,255,255));
    if(!departure || i<8) img.fillCircle(im,x:140,y:225,radius:4,color:img.ColorRgb8(235,235,235));
    if(blur && i==8) {
     img.fillRect(im,x1:134,y1:215,x2:145,y2:234,color:img.ColorRgb8(175,175,175));
    }
    if(club && i>=6 && i<=10) {
     final x=140+(i-8)*9;
     img.drawLine(im,x1:x-12,y1:167,x2:x,y2:236,color:img.ColorRgb8(175,175,175),thickness:3);
    }
    final path='${temp.path}/${name}_$i.png';await File(path).writeAsBytes(img.encodePng(im));
    frames.add({'path':path,'t_ms':200+i*32,'width':200,'height':300});
   }
   return frames;
  }
  final positive=await ImpactDetectionService.analyzeWithDiagnostics(frames:await make('hit'),samples:samples);
  check(positive['diagnostics']['status']=='selected','positive failed: ${positive['diagnostics']}');
  final r=positive['result'] as Map;
  check((r['t_ms'] as int)>positive['diagnostics']['top_ms'],'candidate precedes top');
  check((r['interval_end_ms'] as int)-(r['interval_start_ms'] as int)<=32,'lost dense timing');
  final distracted=await ImpactDetectionService.analyzeWithDiagnostics(frames:await make('distractor',distractor:true),samples:samples);
  check(distracted['result']!=null&&distracted['result']['ball_x']>100,'static brighter dot hid actual ball');
  final blurred=await ImpactDetectionService.analyzeWithDiagnostics(frames:await make('blur',club:false,blur:true),samples:samples);
  check(blurred['result']!=null,'moderately elongated impact blur rejected');
  final stationary=await ImpactDetectionService.analyzeWithDiagnostics(frames:await make('stationary',departure:false,club:false),samples:samples);
  check(stationary['result']==null,'stationary ball incorrectly selected');
  final noClub=await ImpactDetectionService.analyzeWithDiagnostics(frames:await make('no_club',club:false),samples:samples);
  check(noClub['diagnostics']['reason']=='ball_departure_without_nearby_club_trace','departure alone is insufficient');
  final coarse=await make('coarse');for(int i=0;i<coarse.length;i++) {coarse[i]['t_ms']=i*100;}
  final sparse=await ImpactDetectionService.analyzeWithDiagnostics(frames:coarse,samples:samples);
  check(sparse['diagnostics']['reason']=='dense_frames_required','coarse timing accepted');
  final missing=await ImpactDetectionService.analyzeWithDiagnostics(frames:[],samples:[]);
  check(missing['diagnostics']['reason']=='insufficient_frames','missing input unhandled');
  final noPose=samples.map((s)=>{...s,'landmarks':<dynamic>[]}).toList();
  final absent=await ImpactDetectionService.analyzeWithDiagnostics(frames:await make('no_pose'),samples:noPose);
  check(absent['result']==null,'missing joints produced candidate');
  List<Map<String,dynamic>> phases(List<double> ys) => List.generate(ys.length,(i)=>{
    't_ms':i*140,'width':200,'height':300,'landmarks':[
      {'name':'leftWrist','x':90.0,'y':ys[i],'likelihood':.99}]});
  final higherFinish=ImpactDetectionService.scanWindow(phases(
    [160,160,160,160,160,160,160,150,110,75,90,160,100,45,35,35,35,40,45,50]));
  check(higherFinish?['top_ms']==1260,'finish mistaken for backswing top');
  final noReturn=ImpactDetectionService.scanWindow(phases(
    [160,160,160,160,160,150,120,90,60,40,30,30,35,40,45]));
  check(noReturn==null,'high held finish without downswing accepted');
  final delayed=phases([for(var i=0;i<100;i++)160,160,160,120,60,80,120,150,160,150,150]);
  final late=ImpactDetectionService.scanWindow(delayed);
  check(late!=null&&late['address_ms']!>12000&&late['top_ms']!>14000,'long preparation selected as address');
  final gestures=phases([160,160,120,60,80,120,150,160,160,160,160,120,60,80,120,150,160]);
  for(var i=0;i<gestures.length;i++) {
    final joints=gestures[i]['landmarks'] as List;
    joints.addAll(<Map<String,Object>>[
      {'name':'rightWrist','x':i<8?190.0:92.0,'y':(joints.first as Map)['y'] as Object,'likelihood':.99},
      {'name':'leftShoulder','x':90.0,'y':80.0,'likelihood':.99},
      {'name':'leftHip','x':90.0,'y':180.0,'likelihood':.99}]);
  }
  final gesturePhase=ImpactDetectionService.scanWindow(gestures);
  check(gesturePhase!=null&&gesturePhase['top_ms']!>=1680&&gesturePhase['top_ms']!<=1820,'single-hand gesture selected: $gesturePhase');
  final twoSamples=<Map<String,dynamic>>[
    ...samples,
    ...samples.map((r)=>{...r,'t_ms':(r['t_ms'] as int)+2000}),
  ];
  final windows=ImpactDetectionService.scanWindows(twoSamples);
  check(windows.length==2,'two swing cycles not separated: $windows');
  final practiceFrames=await make('practice',departure:false);
  final hitFrames=(await make('second_hit')).map((r)=>{...r,'t_ms':(r['t_ms'] as int)+2000}).toList();
  final reports=<Map<String,dynamic>>[];
  for(final w in windows) {
    reports.add(await ImpactDetectionService.analyzeWithDiagnostics(
      frames:[...practiceFrames,...hitFrames],samples:twoSamples,window:w));
  }
  final selected=ImpactDetectionService.selectSwing(windows,reports);
  check(selected['result']!=null && selected['result']['t_ms']>2000,'practice chosen instead of actual hit');
  check(selected['diagnostics']['selected_window']['top_ms']==windows.last['top_ms'],'wrong cycle provenance');
  final threeWindows=ImpactDetectionService.scanWindows([
    ...twoSamples,...samples.map((r)=>{...r,'t_ms':(r['t_ms'] as int)+4000})]);
  check(threeWindows.length==3,'three swings not separated');
  final third=ImpactDetectionService.selectSwing(threeWindows,[stationary,stationary,positive]);
  check(third['diagnostics']['selected_window']['top_ms']==threeWindows.last['top_ms'],'two practices not skipped');
  final followthrough=ImpactDetectionService.scanWindows(phases(
    [160,160,120,60,80,120,160,80,40,50,80,120,160]));
  check(followthrough.length==1,'brief impact low hands re-armed followthrough');
  final none=ImpactDetectionService.selectSwing(windows,[stationary,stationary]);
  check(none['result']==null&&none['diagnostics']['selected_window']==null,'ambiguous practices got pose fallback');
  final both=ImpactDetectionService.selectSwing(windows,[positive,positive]);
  check(both['result']==null&&both['diagnostics']['reason']=='multiple_visual_hits','two hits arbitrarily ranked');
  final single=ImpactDetectionService.selectSwing([windows.first],[stationary]);
  check(single['diagnostics']['selection_basis']=='single_swing_pose_fallback','single swing fallback lost');
  final occluded=await make('occluded');
  final restore=await make('restored',departure:false);
  for(var i=12;i<occluded.length;i++)occluded[i]=restore[i];
  final blocked=await ImpactDetectionService.analyzeWithDiagnostics(frames:occluded,samples:samples);
  check(blocked['result']==null&&blocked['diagnostics']['reason']=='ball_reappeared_after_occlusion','temporary occlusion called hit');
  check(ImpactDetectionService.scanWindows(phases(
    [160,160,160,150,110,75,90,160,100,45,35,35,35,40,45,50])).length==1,'followthrough counted as another cycle');
  jsonEncode([positive,stationary,noClub,sparse,missing,absent]);
  stdout.writeln('PASS: impact v4 multi-swing selection, ambiguity, occlusion and existing scenarios; phase reversal, finish rejection, timing, no-ball-motion, no-club, sparse, empty, missing pose');
 } finally {await temp.delete(recursive:true);}
}
