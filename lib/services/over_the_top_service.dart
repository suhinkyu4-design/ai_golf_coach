import 'dart:math' as math;
import 'over_the_top_rule.dart';

/// Compares observed shaft rays at matched hand heights, not guessed club heads.
/// Experimental evidence only until shaft identity and rule accuracy are validated.
class OverTheTopService {
  static Map<String,dynamic> measure({required List<Map<String,dynamic>> samples,
      required int? addressMs, required int? topMs, required int? impactMs,
      required bool rear, required int? ballSign, required bool eventsConfirmed}) {
    Map<String,dynamic> run(String key)=>_measureTrack(samples:samples,addressMs:addressMs,
      topMs:topMs,impactMs:impactMs,rear:rear,ballSign:ballSign,eventsConfirmed:eventsConfirmed,key:key);
    final full=run('shaft_candidate'),near=run('near_shaft_candidate');
    final fullCount=(full['pairs'] as List).length,nearCount=(near['pairs'] as List).length;
    // Compare like with like; never join rays from different tracking regions.
    final selected=nearCount>fullCount?near:full;
    selected['available_pairs_by_source']={'full_ray':fullCount,'near_grip':nearCount};
    if(eventsConfirmed&&addressMs!=null&&topMs!=null&&impactMs!=null) {
      final rule=OverTheTopRule.evaluate(samples,address:addressMs,top:topMs,impact:impactMs,rear:rear,ballSign:ballSign);
      selected['slot_check']=rule;
      selected['slot_pairs']=rule['slot_pairs'];
      if(rule['status']=='rule_classified') {
        selected['pair_comparison_status']=selected['status'];
        selected.addAll({for(final key in ['status','reason','grade','label','value','t_ms','note','release_enabled',
          'threshold_basis','threshold','warning_threshold','observation_count','reference_t_ms'])key:rule[key]});
      }
    }
    return selected;
  }
  static Map<String,dynamic> _measureTrack({required List<Map<String,dynamic>> samples,
      required int? addressMs,required int? topMs,required int? impactMs,
      required bool rear,required int? ballSign,required bool eventsConfirmed,required String key}) {
    final near=key=='near_shaft_candidate';
    final out=<String,dynamic>{
      'comparison_source':near?'near_grip':'full_ray',
      'version':'over_top_shaft_observations_3','status':'unavailable',
      'diagnosis':null,'diagnosis_validated':false,'release_enabled':false,
      'measurement':'matched_hand_height_shaft_ray_difference',
      'head_detected':false,'identity_verified':false,'pairs':<Map<String,dynamic>>[],
      'timestamp_basis':'requested_closest_frame_ms',
    };
    Map<String,dynamic> reject(String reason) {out['reason']=reason;return out;}
    if(!eventsConfirmed||addressMs==null||topMs==null||impactMs==null||
        addressMs<0||addressMs>=topMs||topMs>=impactMs)return reject('invalid_events');
    if(!rear)return reject('rear_view_required');
    final directionKnown=[-1,1].contains(ballSign);
    final rows=<int,Map>{};
    for(final s in samples) {
      final c=s[key];
      if(c is Map && c['t_ms']==s['t_ms'] && c['status']=='line_candidate' &&
          c['coordinate_space']=='upright_image_pixels' && c['temporally_supported']==true &&
          c['duplicate_frame_of_t_ms']==null && c['width']==s['width'] && c['height']==s['height'] &&
          c['width'] is num && c['height'] is num &&
          ['angle_deg','length_px','torso_length_px'].every((key)=>c[key] is num && (c[key] as num).isFinite) &&
          ['grip','shaft_end'].every((key)=>c[key] is Map &&
            ['x','y'].every((axis)=>c[key][axis] is num && (c[key][axis] as num).isFinite) &&
            c[key]['x']>=0 && c[key]['y']>=0 && c[key]['x']<c['width'] && c[key]['y']<c['height'])) {
        rows.putIfAbsent(s['t_ms'] as int,()=>c);
      }
    }
    // Do not cut off actual descent when the player pauses at the top.
    final earlyEnd=impactMs;
    final expected=samples.where((s)=>(s['t_ms'] as int)>topMs&&(s['t_ms'] as int)<=earlyEnd)
        .where((s)=>s[key] is! Map||s[key]['duplicate_frame_of_t_ms']==null)
        .map((s)=>s['t_ms']).toSet().length;
    final back=rows.values.where((r)=>r['t_ms']>addressMs&&r['t_ms']<topMs).toList();
    final down=rows.values.where((r)=>r['t_ms']>topMs&&r['t_ms']<=earlyEnd).toList()
      ..sort((a,b)=>(a['t_ms'] as int).compareTo(b['t_ms'] as int));
    final pairs=out['pairs'] as List<Map<String,dynamic>>;
    for(final d in down) {
      final scale=(d['torso_length_px'] as num).toDouble();
      if(!scale.isFinite||scale<=0)continue;
      final dg=d['grip'] as Map;
      final matches=back.where((b)=>b['width']==d['width']&&b['height']==d['height']&&
        ((b['grip']['y'] as num)-(dg['y'] as num)).abs()<=scale*.06).toList()
        ..sort((a,b)=>((a['grip']['y'] as num)-(dg['y'] as num)).abs()
          .compareTo(((b['grip']['y'] as num)-(dg['y'] as num)).abs()));
      if(matches.isEmpty)continue;
      final b=matches.first;
      // Compare a common visible shaft distance; no extrapolation past detected line.
      final distance=math.min((b['length_px'] as num).toDouble(),
          (d['length_px'] as num).toDouble()).clamp(0.0,scale*.75);
      if(distance<scale*(near ? .35 : .5))continue;
      double xAt(Map c)=>(c['grip']['x'] as num).toDouble()+
        math.cos((c['angle_deg'] as num)*math.pi/180)*distance;
      pairs.add({'t_ms':d['t_ms'],'backswing_t_ms':b['t_ms'],
        'shaft_outward_ratio':directionKnown ? ballSign!*(xAt(d)-xAt(b))/scale : null,
        'grip_outward_ratio':directionKnown ? ballSign!*((dg['x'] as num)-(b['grip']['x'] as num))/scale : null,
        'backswing':Map<String,dynamic>.from(b),'downswing':Map<String,dynamic>.from(d),
        'hand_height_difference_px':((dg['y'] as num)-(b['grip']['y'] as num)).abs(),
        'shaft_angle_difference_deg':((d['angle_deg'] as num)-(b['angle_deg'] as num)+540)%360-180,
        'comparison_distance_px':distance});
    }
    out.addAll({'candidate_frames':rows.length,'matched_pairs':pairs.length,
      'backswing_candidate_frames':back.length,'downswing_candidate_frames':down.length,
      'expected_down_frames':expected,'coverage':expected==0?0.0:pairs.length/expected});
    if(!directionKnown)return reject('ball_direction_unknown');
    if(back.isEmpty)return reject('backswing_shaft_unavailable');
    if(down.isEmpty)return reject('downswing_shaft_unavailable');
    if(pairs.length<3||expected==0||pairs.length/expected<.7)return reject('insufficient_continuous_shaft_pairs');
    final smooth=<Map<String,dynamic>>[];
    for(var j=1;j<pairs.length-1;j++) {
      if((pairs[j]['t_ms'] as int)-(pairs[j-1]['t_ms'] as int)>100||
          (pairs[j+1]['t_ms'] as int)-(pairs[j]['t_ms'] as int)>100)continue;
      final values=pairs.sublist(j-1,j+2).map((p)=>p['shaft_outward_ratio'] as double).toList()..sort();
      smooth.add({'t_ms':pairs[j]['t_ms'],'value':values[1]});
    }
    if(smooth.isEmpty)return reject('sampling_gaps_too_large');
    out.addAll({'status':'experimental_observation','reason':'club_identity_and_rule_validation_required',
      'peak':smooth.reduce((a,b)=>(a['value'] as double)>(b['value'] as double)?a:b),
      'note':'샤프트 후보의 영상상 경로 비교이며 오버더탑 판정이 아닙니다.'});
    return out;
  }
}
