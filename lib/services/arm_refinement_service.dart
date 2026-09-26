import 'dart:io';
import 'dart:math' as math;
import 'package:image/image.dart' as img;
import 'swing_fault_features.dart';

/// A second image observation, not interpolation of occluded arm coordinates.
class ArmRefinementService {
  static bool shortArm(Map row,String side) {
    final f=FrameGeometry.read(row);
    final e=f?.joint('${side}Elbow');
    final w=f?.joint('${side}Wrist'), scale=f?.torsoLength;
    return scale==null||scale<=0||e==null||w==null||e.distanceTo(w)<scale*.25;
  }
  static Future<Map<String,dynamic>?> prepare(Map<String,dynamic> input) async {
    final row=input['row'] as Map;
    final f=FrameGeometry.read(row);
    if(f==null||f.torsoLength==null)return null;
    final points=<math.Point<double>>[];
    for(final name in ['leftEye','rightEye','leftShoulder','rightShoulder',
        'leftElbow','rightElbow','leftWrist','rightWrist','leftHip','rightHip',
        'leftKnee','rightKnee','leftAnkle','rightAnkle','leftHeel','rightHeel']) {
      final p=f.joint(name);if(p!=null)points.add(p);
    }
    // Keep head and legs as context for the full-body pose model.
    if(points.length<10||f.joint('leftAnkle')==null||f.joint('rightAnkle')==null)return null;
    final source=img.decodeImage(await File(input['path'] as String).readAsBytes());
    if(source==null||source.width!=f.w||source.height!=f.h)return null;
    final pad=f.torsoLength!*.55;
    final x=(points.map((p)=>p.x).reduce(math.min)-pad).floor().clamp(0,source.width-1);
    final y=(points.map((p)=>p.y).reduce(math.min)-pad).floor().clamp(0,source.height-1);
    final right=(points.map((p)=>p.x).reduce(math.max)+pad).ceil().clamp(x+1,source.width);
    final bottom=(points.map((p)=>p.y).reduce(math.max)+pad).ceil().clamp(y+1,source.height);
    final width=right-x,height=bottom-y;
    if(width<40||height<80)return null;
    final cropped=img.copyCrop(source,x:x,y:y,width:width,height:height);
    final resized=img.copyResize(cropped,height:1280,interpolation:img.Interpolation.linear);
    final path='${input['path']}.arm_crop.jpg';
    await File(path).writeAsBytes(img.encodeJpg(resized,quality:95));
    return {'path':path,'x':x,'y':y,'scale_x':resized.width/width,'scale_y':resized.height/height};
  }
  static List<Map<String,dynamic>> restore(List<Map<String,dynamic>> points,Map crop)=>[
    for(final p in points){...p,'x':(p['x'] as num)/(crop['scale_x'] as num)+(crop['x'] as num),
      'y':(p['y'] as num)/(crop['scale_y'] as num)+(crop['y'] as num)}];

  static void select(List<Map<String,dynamic>> rows,String side) {
    final ordered=List<Map<String,dynamic>>.from(rows)..sort((a,b)=>(a['t_ms'] as int).compareTo(b['t_ms'] as int));
    for(final row in ordered){
      final detail=row['arm_refinement'];
      if(detail is! Map||detail['landmarks'] is! List)continue;
      detail['status']='rejected';
      detail['reason']='geometry_or_confidence';
      final base=FrameGeometry.read(row),scale=FrameGeometry.read(row)?.torsoLength;
      final refined=FrameGeometry.read({...row,'landmarks':detail['landmarks']});
      final strong=(detail['landmarks'] as List).whereType<Map>().where((p)=>
        ['${side}Elbow','${side}Wrist'].contains(p['name'])&&
        p['likelihood'] is num&&(p['likelihood'] as num)>=.8).length==2;
      if(!strong){detail['reason']='low_crop_joint_confidence';continue;}
      final e=refined?.joint('${side}Elbow'),w=refined?.joint('${side}Wrist');
      if(base==null||scale==null||scale<=0||e==null||w==null)continue;
      final length=e.distanceTo(w);
      if(length<scale*.25){detail['reason']='crop_forearm_still_short';continue;}
      if(length>scale*1.1){detail['reason']='crop_forearm_length_implausible';continue;}
      final originalW=base.joint('${side}Wrist');
      if(originalW==null||originalW.distanceTo(w)>scale*.2){detail['reason']='crop_wrist_shift_too_large';continue;}
      final shoulder=refined?.joint('${side}Shoulder'),originalShoulder=base.joint('${side}Shoulder');
      if(shoulder==null||originalShoulder==null||shoulder.distanceTo(originalShoulder)>scale*.2){
        detail['reason']='crop_shoulder_shift_too_large';continue;
      }
      Map<String,dynamic>? before,after;
      for(final neighbor in ordered){
        final dt=(neighbor['t_ms'] as int)-(row['t_ms'] as int);
        if(dt==0||dt.abs()>100||shortArm(neighbor,side))continue;
        if(dt<0)before=neighbor;
        if(dt>0){after=neighbor;break;}
      }
      if(before==null||after==null){detail['reason']='two_original_anchors_required';continue;}
      final a=FrameGeometry.read(before)!,b=FrameGeometry.read(after)!;
      final fraction=(base.t-a.t)/(b.t-a.t);
      final expectedE=a.joint('${side}Elbow')!*(1-fraction)+b.joint('${side}Elbow')!*fraction;
      final expectedW=a.joint('${side}Wrist')!*(1-fraction)+b.joint('${side}Wrist')!*fraction;
      if(e.distanceTo(expectedE)>scale*.25||w.distanceTo(expectedW)>scale*.2){
        detail['reason']='disagrees_with_original_neighbors';continue;
      }
      final names={'${side}Elbow','${side}Wrist'};
      // Preserve original joints for all existing fault rules.
      row['casting_landmarks']=[for(final p in row['landmarks'] as List)
        if(!names.contains(p['name']))p,
        for(final p in detail['landmarks'] as List)if(names.contains(p['name']))p];
      for(final entry in <String,dynamic>{'status':'accepted','reason':'crop_observation_matches_original_neighbors',
        'side':side,'forearm_length_px':length,'before_t_ms':a.t,'after_t_ms':b.t}.entries) {
        detail[entry.key]=entry.value;
      }
    }
  }
}
