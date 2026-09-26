import 'dart:math' as math;
import 'swing_fault_features.dart';
import 'casting_rule.dart';

/// 2D forearm/near-shaft angle observations, not anatomical wrist cocking.
/// Candidate identity and view-dependent diagnostic cutoffs are not validated.
class CastingObservationService {
  static Map<String,dynamic> measure({required List<Map<String,dynamic>> samples,
      required int? topMs,required int? impactMs,required String lead,
      required String view,required bool eventsConfirmed}) {
    final report=_observe(samples:samples,topMs:topMs,impactMs:impactMs,lead:lead,view:view,eventsConfirmed:eventsConfirmed);
    final rule=CastingRule.evaluate(report,top:eventsConfirmed?topMs:null,impact:impactMs,view:view);
    report['rule_check']=rule;
    if(rule['status']=='rule_classified') {
      report['observation_status']=report['status'];
      report.addAll({for(final key in ['status','reason','release_enabled','grade','label','value','top_angle_deg',
        'halfway_angle_deg','top_angle_t_ms','halfway_angle_t_ms','opening_change_deg','t_ms','note','threshold_basis','observation_count',
        'early_down_angle_deg','assessment_basis','angle_change_measured','measurement'])key:rule[key]});
    }
    return report;
  }
  static Map<String,dynamic> _observe({required List<Map<String,dynamic>> samples,
      required int? topMs,required int? impactMs,required String lead,
      required String view,required bool eventsConfirmed}) {
    final out=<String,dynamic>{
      'version':'casting_observations_4','status':'unavailable','reason':null,
      'diagnosis':null,'release_enabled':false,'diagnosis_validated':false,
      'measurement':'projected_forearm_near_shaft_angle','unit':'deg',
      'angle_definition':'wrist_to_elbow_versus_grip_to_shaft_end',
      'view':view,'lead_side':lead,'shaft_identity_verified':false,
      'timestamp_basis':'requested_closest_frame_ms',
      'observations':<Map<String,dynamic>>[],
    };
    Map<String,dynamic> reject(String reason){out['reason']=reason;return out;}
    if(!eventsConfirmed||topMs==null||impactMs==null||topMs<0||impactMs<=topMs||
        !['left','right'].contains(lead))return reject('invalid_events');
    final unique=<int,Map<String,dynamic>>{};
    for(final row in samples){
      if(row['t_ms'] is int)unique.putIfAbsent(row['t_ms'] as int,()=>row);
    }
    final ordered=unique.values.toList()..sort((a,b)=>(a['t_ms'] as int).compareTo(b['t_ms'] as int));
    final observations=out['observations'] as List<Map<String,dynamic>>;
    Map<String,dynamic>? previousHeight;
    int? halfway;
    int expected=0,sequenceIndex=0;
    final rejectCounts=<String,int>{};
    void count(String reason){rejectCounts.update(reason,(v)=>v+1,ifAbsent:()=>1);}
    for(final row in ordered){
      final t=row['t_ms'] as int;
      if(t<topMs-80||t>impactMs)continue;
      final c=row['near_shaft_candidate'];
      if(c is Map&&c['duplicate_frame_of_t_ms']!=null)continue;
      sequenceIndex++;
      final f=FrameGeometry.read(row);
      if(f==null){count('invalid_pose');previousHeight=null;continue;}
      // Crossing is relative to this frame's moving pelvis, not top-frame hip Y.
      final wrists=f.midpoint('leftWrist','rightWrist'),hips=f.hip;
      if(t>=topMs){
        expected++;
        if(wrists!=null&&hips!=null){
          final relative=wrists.y-hips.y;
          if(halfway==null&&previousHeight!=null&&
              t-(previousHeight['t_ms'] as int)<=100&&
              (previousHeight['relative_y'] as double)<0&&relative>=0&&
              wrists.y>(previousHeight['wrist_y'] as double))halfway=t;
          previousHeight={'t_ms':t,'relative_y':relative,'wrist_y':wrists.y};
        }else{previousHeight=null;}
      }
      if(c is! Map||c['status']!='line_candidate'||c['temporally_supported']!=true||
          c['t_ms']!=t||c['coordinate_space']!='upright_image_pixels'||
          c['width']!=row['width']||c['height']!=row['height']){
        count('shaft_not_supported');continue;
      }
      final armFrame = row['arm_refinement']?['status']=='accepted' && row['casting_landmarks'] is List
        ? FrameGeometry.read({...row,'landmarks':row['casting_landmarks']}) ?? f : f;
      final elbow=armFrame.joint('${lead}Elbow'),wrist=armFrame.joint('${lead}Wrist');
      final grip=c['grip'] is Map?f.point(c['grip'] as Map):null;
      final end=c['shaft_end'] is Map?f.point(c['shaft_end'] as Map):null;
      final torso=f.torsoLength;
      if(elbow==null||wrist==null||grip==null||end==null||torso==null||torso<=0){
        count('lead_forearm_unavailable');continue;
      }
      final forearm=elbow-wrist,shaft=end-grip;
      // Foreshortened vectors amplify a few pixels of detector error.
      if(forearm.magnitude<torso*.25||shaft.magnitude<torso*.35||
          wrist.distanceTo(grip)>torso*.25){count('short_or_disconnected_vectors');continue;}
      final cosine=((forearm.x*shaft.x+forearm.y*shaft.y)/
        (forearm.magnitude*shaft.magnitude)).clamp(-1.0,1.0);
      observations.add({'t_ms':t,'angle_deg':math.acos(cosine)*180/math.pi,
        'sequence_index':sequenceIndex,'forearm_length_ratio':forearm.magnitude/torso,
        'shaft_image_supported':c['extension_supported']==true||c['image_supported_track']==true||c['multi_scale_supported']==true,
        'shaft_support_basis':c['extension_supported']==true?'distal_image':c['multi_scale_supported']==true?'two_search_regions':'extended_temporal_anchors',
        'wrist_y':wrists?.y,'torso_length_px':torso,
        'wrist_hip_ratio':wrists!=null&&hips!=null?(wrists.y-hips.y)/torso:null,
        // A conservative geometric margin assuming 2%-torso endpoint error.
        // This is an engineering guard, not a calibrated confidence interval.
        'angle_margin_assumed_deg':(math.asin((torso*.04/forearm.magnitude).clamp(0.0,1.0))+
          math.asin((torso*.04/shaft.magnitude).clamp(0.0,1.0)))*180/math.pi,
        'arm_source': identical(armFrame,f) ? 'original' : 'crop_with_neighbor_checks',
        'lead_elbow':{'x':elbow.x,'y':elbow.y},'lead_wrist':{'x':wrist.x,'y':wrist.y},
        'grip':c['grip'],'shaft_end':c['shaft_end'],
        'frame_signature':c['frame_signature']});
    }
    final smooth=<Map<String,dynamic>>[];
    for(var j=1;j<observations.length-1;j++){
      final a=observations[j-1],b=observations[j],c=observations[j+1];
      if((b['t_ms'] as int)-(a['t_ms'] as int)>100||
          (c['t_ms'] as int)-(b['t_ms'] as int)>100)continue;
      final angles=[a['angle_deg'] as double,b['angle_deg'] as double,c['angle_deg'] as double]..sort();
      smooth.add({'t_ms':b['t_ms'],'angle_deg':angles[1]});
    }
    out.addAll({'halfway_t_ms':halfway,'halfway_basis':'observed_wrists_crossing_current_hip_height',
      'valid_angle_frames':observations.length,'expected_down_frames':expected,
      'rejections':rejectCounts,'smoothed':smooth,
      'arm_refinement_attempts':samples.where((r)=>r['arm_refinement'] is Map).length,
      'arm_refinement_accepted':samples.where((r)=>r['arm_refinement']?['status']=='accepted').length});
    // Independent visible runs: never bridge a rejected unique image or phase.
    final byTime={for(final p in observations) p['t_ms']:p};
    final runs=<List<Map<String,dynamic>>>[];
    var current=<Map<String,dynamic>>[];
    void flush(){if(current.isNotEmpty)runs.add(current);current=[];}
    for(final row in ordered){
      final t=row['t_ms'] as int;
      if(t<topMs||t>impactMs)continue;
      if(row['near_shaft_candidate']?['duplicate_frame_of_t_ms']!=null)continue;
      final point=byTime[t];
      if(point==null){flush();continue;}
      if(current.isNotEmpty && t-(current.last['t_ms'] as int)>100)flush();
      current.add(point);
    }
    flush();
    final segments=<Map<String,dynamic>>[];
    double median(List<Map<String,dynamic>> points){
      final values=points.map((p)=>(p['angle_deg'] as num).toDouble()).toList()..sort();
      return values[values.length~/2];
    }
    for(final run in runs){
      // Non-overlapping 3-frame endpoint windows require at least six images.
      if(run.length<6)continue;
      final start=run.first['t_ms'] as int,end=run.last['t_ms'] as int;
      if(end-start<60)continue;
      final first=median(run.take(3).toList()),last=median(run.skip(run.length-3).toList());
      segments.add({'start_t_ms':start,'end_t_ms':end,'frame_count':run.length,
        'duration_ms':end-start,'start_angle_deg':first,'end_angle_deg':last,
        'change_deg':last-first,'start_fraction':(start-topMs)/(impactMs-topMs),
        'end_fraction':(end-topMs)/(impactMs-topMs),
        'includes_halfway':halfway!=null&&halfway>=start&&halfway<=end,
        'angle_basis':'median_of_three_distinct_observations_at_each_end'});
    }
    segments.sort((a,b)=>(b['duration_ms'] as int).compareTo(a['duration_ms'] as int));
    out['visible_segments']=segments;
    out['longest_visible_run_frames']=runs.fold<int>(0,(n,r)=>math.max(n,r.length));
    out['segment_status']=segments.isEmpty?'insufficient_continuous_observations':'experimental_observation';
    out['selected_segment']=segments.isEmpty?null:segments.first;
    if(halfway==null)return reject('halfway_not_observed');
    final halfwayTime = halfway;
    final rawHalf=observations.where((p)=>((p['t_ms'] as int)-halfwayTime).abs()<=50).toList()
      ..sort((a,b)=>((a['t_ms'] as int)-halfwayTime).abs().compareTo(((b['t_ms'] as int)-halfwayTime).abs()));
    if(rawHalf.isNotEmpty) {
      out['halfway_raw_angle_deg']=rawHalf.first['angle_deg'];
      out['halfway_raw_angle_t_ms']=rawHalf.first['t_ms'];
    }
    final topAngles=smooth.where((p)=>((p['t_ms'] as int)-topMs).abs()<=50).toList()
      ..sort((a,b)=>((a['t_ms'] as int)-topMs).abs().compareTo(((b['t_ms'] as int)-topMs).abs()));
    final halfAngles=smooth.where((p)=>((p['t_ms'] as int)-halfwayTime).abs()<=50&&
      (p['t_ms'] as int)>topMs).toList()
      ..sort((a,b)=>((a['t_ms'] as int)-halfwayTime).abs().compareTo(((b['t_ms'] as int)-halfwayTime).abs()));
    if(topAngles.isEmpty)return reject('top_angle_unavailable');
    if(halfAngles.isEmpty)return reject(rawHalf.isEmpty
        ? 'halfway_angle_unavailable' : 'halfway_angle_sequence_unavailable');
    final start=topAngles.first,end=halfAngles.first;
    if((end['t_ms'] as int)<=(start['t_ms'] as int))return reject('distinct_phase_angles_required');
    // No unsupported interpolation across an occluded transition.
    final window=smooth.where((p)=>(p['t_ms'] as int)>=(start['t_ms'] as int)&&
      (p['t_ms'] as int)<=(end['t_ms'] as int)).toList();
    if(window.length<3)return reject('insufficient_angle_sequence');
    for(var j=1;j<window.length;j++){
      if((window[j]['t_ms'] as int)-(window[j-1]['t_ms'] as int)>100)return reject('angle_sequence_gap');
    }
    final begin=start['angle_deg'] as double,finish=end['angle_deg'] as double;
    out.addAll({'status':'experimental_observation','reason':'view_and_shaft_validation_required',
      'top_angle_deg':begin,'top_angle_t_ms':start['t_ms'],
      'halfway_angle_deg':finish,'halfway_angle_t_ms':end['t_ms'],
      'opening_change_deg':finish-begin,
      'note':'전완과 샤프트 후보 사이의 2D 투영각 변화입니다. 캐스팅 정상·오류 판정은 아닙니다.'});
    return out;
  }
}
