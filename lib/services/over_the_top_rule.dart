import 'dart:math' as math;

/// Rear-view shaft-plane screening rule, not a measured clubhead path or 3D diagnosis.
/// Thresholds are app heuristics; coaching references provide the geometric concept only.
class OverTheTopRule {
  static Map<String,dynamic> evaluate(List<Map<String,dynamic>> samples,
      {required int address,required int top,required int impact,required bool rear,required int? ballSign}) {
    final out=<String,dynamic>{'status':'unavailable','reason':'shaft_plane_evidence_missing',
      'diagnosis':null,'diagnosis_validated':false,'release_enabled':false,
      'threshold_basis':'app_projected_shaft_plane_rule_v1','threshold':.10,'warning_threshold':.05,
      'measurement':'downswing_outside_backswing_shaft_reference',
      'note':'후방 영상의 샤프트 기준선 비교입니다. 앱 기준이며 실제 클럽 헤드 경로나 3D 궤도를 측정한 것은 아닙니다.',
      'slot_pairs':<Map<String,dynamic>>[]};
    Map<String,dynamic> reject(String r){out['reason']=r;return out;}
    if(!rear)return reject('rear_view_required');
    if(![-1,1].contains(ballSign))return reject('ball_direction_unknown');
    if(address<0||address>=top||top>=impact)return reject('invalid_events');
    final candidates=<Map<String,dynamic>>[];
    final times=<int>{},images=<String>{};
    for(final s in samples) {
      final c=s['near_shaft_candidate'];
      if(c is! Map||c['t_ms'] is! int||c['t_ms']!=s['t_ms']||
          c['status']!='line_candidate'||c['temporally_supported']!=true||
          c['duplicate_frame_of_t_ms']!=null||c['coordinate_space']!='upright_image_pixels'||
          c['width']!=s['width']||c['height']!=s['height']||
          c['width'] is! num||c['height'] is! num||
          !['angle_deg','length_px','torso_length_px'].every((k)=>c[k] is num&&(c[k] as num).isFinite)||
          (c['torso_length_px'] as num)<=0||(c['length_px'] as num)<(c['torso_length_px'] as num)*.35||
          !['grip','shaft_end'].every((k)=>c[k] is Map&&['x','y'].every((a)=>c[k][a] is num&&(c[k][a] as num).isFinite)&&
            c[k]['x']>=0&&c[k]['y']>=0&&c[k]['x']<c['width']&&c[k]['y']<c['height']))continue;
      if(c['extension_supported']!=true&&c['image_supported_track']!=true)continue;
      if(!times.add(c['t_ms'] as int))continue;
      if(c['frame_signature'] is String&&!images.add(c['frame_signature'] as String))continue;
      // Upper backswing / initial downswing shaft must point upwards, away from grip.
      final radians=(c['angle_deg'] as num)*math.pi/180;
      if(math.sin(radians)>-.35)continue;
      candidates.add(Map<String,dynamic>.from(c));
    }
    candidates.sort((a,b)=>(a['t_ms'] as int).compareTo(b['t_ms'] as int));
    final back=candidates.where((c)=>c['t_ms']>address&&c['t_ms']<top&&c['extension_supported']==true).toList();
    // A consistent rising run defines an observed upper reference, not one isolated line.
    Map<String,dynamic>? reference;
    for(var j=0;j+2<back.length;j++) {
      final a=back[j],b=back[j+1],c=back[j+2];
      final scale=(a['torso_length_px'] as num).toDouble();
      final dt1=(b['t_ms'] as int)-(a['t_ms'] as int),dt2=(c['t_ms'] as int)-(b['t_ms'] as int);
      double turn(Map x,Map y)=>(((x['angle_deg'] as num)-(y['angle_deg'] as num)+540)%360-180).abs().toDouble();
      if(dt1>100||dt2>100||dt1+dt2<50||turn(a,b)>20||turn(b,c)>20||
          b['grip']['y']>a['grip']['y']||c['grip']['y']>b['grip']['y']||
          (a['grip']['y'] as num)-(c['grip']['y'] as num)<scale*.12)continue;
      reference=a;
      out['reference_support_times_ms']=[a['t_ms'],b['t_ms'],c['t_ms']];
      break;
    }
    if(reference==null)return reject('backswing_reference_unavailable');
    final ref=reference,scale=(ref['torso_length_px'] as num).toDouble();
    final angle=(ref['angle_deg'] as num)*math.pi/180,ux=math.cos(angle),uy=math.sin(angle);
    final rg=ref['grip'] as Map;
    final down=candidates.where((c)=>c['t_ms']>top&&c['t_ms']<=impact&&
      c['width']==ref['width']&&c['height']==ref['height']&&
      ((c['grip']['y'] as num)-(rg['y'] as num)).abs()<=scale*.6).toList();
    // Require a continuous descending run with visible hand displacement.
    List<Map<String,dynamic>>? run;
    for(var j=0;j+2<down.length;j++) {
      final a=down[j],b=down[j+1],c=down[j+2];
      final dt1=(b['t_ms'] as int)-(a['t_ms'] as int),dt2=(c['t_ms'] as int)-(b['t_ms'] as int);
      if(dt1>60||dt2>60||dt1+dt2<50||
        b['grip']['y']<a['grip']['y']||c['grip']['y']<b['grip']['y']||
        (c['grip']['y'] as num)-(a['grip']['y'] as num)<scale*.2)continue;
      run=[a,b,c];break;
    }
    if(run==null)return reject('continuous_downswing_plane_unavailable');
    final pairs=out['slot_pairs'] as List<Map<String,dynamic>>;
    for(final c in run) {
      // Signed perpendicular distance to an observed shaft reference line.
      // Compare grip and a point on the actually observed ray; never invent a head.
      final distance=math.min((ref['length_px'] as num).toDouble(),(c['length_px'] as num).toDouble());
      final cg=c['grip'] as Map,ca=(c['angle_deg'] as num)*math.pi/180;
      double side(double x,double y)=>ballSign!*(x-(rg['x'] as num)-(y-(rg['y'] as num))*ux/uy)*uy.abs()/scale;
      final grip=side((cg['x'] as num).toDouble(),(cg['y'] as num).toDouble());
      final shaft=side((cg['x'] as num)+math.cos(ca)*distance,(cg['y'] as num)+math.sin(ca)*distance);
      pairs.add({'t_ms':c['t_ms'],'backswing_t_ms':ref['t_ms'],'backswing':ref,'downswing':c,
        'grip_outward_ratio':grip,'shaft_outward_ratio':shaft,'plane_outward_ratio':(grip+shaft)/2,
        'comparison_distance_px':distance,'hand_height_difference_px':((cg['y'] as num)-(rg['y'] as num)).abs(),
        'shaft_angle_difference_deg':((c['angle_deg'] as num)-(ref['angle_deg'] as num)+540)%360-180});
    }
    final values=pairs.map((p)=>p['plane_outward_ratio'] as double).toList()..sort();
    final value=values[1];
    final grade=value>=.10?'over_the_top':value>=.05?'warning':'within_rule';
    out.addAll({'status':'rule_classified','reason':null,'release_enabled':true,'grade':grade,'value':value,
      'label':grade=='over_the_top'?'오버더탑 의심':grade=='warning'?'오버더탑 주의':'오버더탑 기준 이내',
      'reference_t_ms':ref['t_ms'],'t_ms':run[1]['t_ms'],'observation_count':3,
      'smoothing':'median_of_three_descending_image_supported_shafts','camera_motion_verified':false});
    return out;
  }
}
