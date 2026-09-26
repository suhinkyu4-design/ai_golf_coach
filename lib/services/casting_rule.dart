/// App screening of projected forearm/shaft opening, not anatomical wrist angle.
class CastingRule {
  // Positive-only screen: a missing top/crossing must never imply normal lag.
  // Every accepted image must show an already-open forearm/shaft while hands
  // descend above the pelvis. The assumed angle margin protects pixel noise.
  static Map<String,dynamic>? _earlyOpen(Map report,int top,int impact) {
    final rows=<Map>[for(final p in report['observations'] as List? ?? [])if(p is Map)p]
      ..sort((a,b)=>(a['t_ms'] as int).compareTo(b['t_ms'] as int));
    for(var j=0;j+2<rows.length;j++) {
      final run=rows.sublist(j,j+3);
      if(run.any((p)=>p['t_ms']<top||p['t_ms']>=impact||p['shaft_image_supported']!=true||
        p['frame_signature'] is! String||p['sequence_index'] is! int||
        !['angle_deg','angle_margin_assumed_deg','forearm_length_ratio','wrist_y','wrist_hip_ratio','torso_length_px']
          .every((k)=>p[k] is num&&(p[k] as num).isFinite)||
        p['angle_deg']>180||p['angle_margin_assumed_deg']<0||p['angle_margin_assumed_deg']>20||
        p['forearm_length_ratio']<.25||p['forearm_length_ratio']>1.1||p['torso_length_px']<=0||
        p['wrist_hip_ratio']>=-.1||p['angle_deg']-p['angle_margin_assumed_deg']<120))continue;
      if(run.map((p)=>p['frame_signature']).toSet().length!=3)continue;
      var continuous=true;
      for(var k=1;k<3;k++) {
        final a=run[k-1],b=run[k];
        if(b['t_ms']-a['t_ms']<=0||b['t_ms']-a['t_ms']>60||b['sequence_index']-a['sequence_index']!=1||
          b['wrist_y']<=a['wrist_y']||((b['angle_deg'] as num)-(a['angle_deg'] as num)).abs()>35)continuous=false;
      }
      if(!continuous||run.last['t_ms']-run.first['t_ms']<50||
        (run.last['wrist_y']-run.first['wrist_y'])/run[1]['torso_length_px']<.3)continue;
      final angles=run.map((p)=>(p['angle_deg'] as num).toDouble()).toList()..sort();
      return {'status':'rule_classified','reason':null,'release_enabled':true,'grade':'casting','label':'캐스팅 의심',
        'assessment_basis':'persistent_open_angle_before_hip','angle_change_measured':false,
        'measurement':'early_downswing_projected_open_angle','value':angles[1],'early_down_angle_deg':angles[1],
        'top_angle_deg':null,'halfway_angle_deg':null,'opening_change_deg':null,
        't_ms':run[1]['t_ms'],'evidence_times_ms':run.map((p)=>p['t_ms']).toList(),'observation_count':3,
        'angle_margin_basis':'assumed_endpoint_error_2_percent_torso',
        'note':'손이 골반 높이에 오기 전, 팔·샤프트가 크게 펴진 상태를 연속 확인한 앱 기준입니다. 실제 손목각이나 릴리즈 시작 시점을 확정한 것은 아닙니다.'};
    }
    return null;
  }
  static String reasonMessage(String? reason)=>const {
    'halfway_not_observed':'손이 골반 높이로 내려오는 구간을 확인하지 못했습니다.',
    'top_angle_sequence_unavailable':'백스윙 탑 주변의 팔·샤프트 각도가 연속으로 보이지 않습니다.',
    'halfway_angle_sequence_unavailable':'손이 골반 높이에 오는 구간의 팔·샤프트 각도가 연속으로 보이지 않습니다.',
    'forearm_or_shaft_projection_unreliable':'팔이 겹쳐 짧게 보이거나 샤프트 추적 근거가 부족합니다.',
    'initial_set_angle_not_observed':'처음 코킹된 각도를 확인하지 못해 풀림 여부를 비교하지 않았습니다.',
    'angle_sequence_gap':'각도 추적이 끊겨 릴리즈 과정을 비교하지 않았습니다.',
    'angle_jump':'각도가 급격히 튀어 판정에서 제외했습니다.',
    'changing_forearm_projection':'팔이 보이는 길이가 크게 달라져 각도 비교를 보류했습니다.',
  }[reason]??'캐스팅을 판정할 연속 영상 근거가 부족합니다.';

  static Map<String,dynamic> evaluate(Map report,{required int? top,required int? impact,required String view}) {
    final out=<String,dynamic>{'status':'unavailable','reason':null,'release_enabled':false,
      'diagnosis':null,'diagnosis_validated':false,'threshold_basis':'app_projected_casting_rule_v1',
      'threshold_deg':120,'warning_threshold_deg':100,'minimum_opening_deg':20,
      'note':'팔과 샤프트의 2D 영상각 변화에 대한 앱 기준입니다. 실제 손목 관절각이나 3D 릴리즈를 측정한 값은 아닙니다.'};
    Map<String,dynamic> reject(String r){out['reason']=r;return out;}
    if(top==null||impact==null||top<0||impact<=top)return reject('invalid_events');
    if(!['rear','faceOn'].contains(view))return reject('unsupported_view');
    final early=_earlyOpen(report,top,impact);
    if(early!=null){out.addAll(early);out.remove('minimum_opening_deg');out.remove('warning_threshold_deg');out['threshold_basis']='app_persistent_projected_open_angle_v2';return out;}
    final half=report['halfway_t_ms'];
    if(half is! int||half<=top||half>=impact)return reject('halfway_not_observed');
    final rows=<Map>[for(final p in report['observations'] as List? ?? [])if(p is Map)p]
      ..sort((a,b)=>(a['t_ms'] as int).compareTo(b['t_ms'] as int));
    bool reliable(Map p)=>p['shaft_image_supported']==true&&p['frame_signature'] is String&&
      p['angle_deg'] is num&&(p['angle_deg'] as num).isFinite&&p['angle_deg']>=0&&p['angle_deg']<=180&&
      p['forearm_length_ratio'] is num&&(p['forearm_length_ratio'] as num).isFinite&&
      p['forearm_length_ratio']>=(view=='rear' ? .40 : .25);
    final starts=rows.where((p)=>(p['t_ms'] as int)>=top-80&&(p['t_ms'] as int)<=top+50).toList();
    final ends=rows.where((p)=>((p['t_ms'] as int)-half).abs()<=50&&(p['t_ms'] as int)<impact).toList();
    if(starts.length<3)return reject('top_angle_sequence_unavailable');
    if(ends.length<3)return reject('halfway_angle_sequence_unavailable');
    final first=starts.take(3).toList(),last=ends.take(3).toList();
    if((first.last['t_ms'] as int)>=(last.first['t_ms'] as int))return reject('distinct_phase_angles_required');
    final window=rows.where((p)=>p['t_ms']>=first.first['t_ms']&&p['t_ms']<=last.last['t_ms']).toList();
    if(window.any((p)=>!reliable(p)))return reject('forearm_or_shaft_projection_unreliable');
    if(window.map((p)=>p['frame_signature']).toSet().length!=window.length)return reject('duplicate_decoded_frame');
    for(var i=1;i<window.length;i++) {
      final a=window[i-1],b=window[i];
      if((b['t_ms'] as int)-(a['t_ms'] as int)>60||a['sequence_index'] is! int||b['sequence_index'] is! int||
        (b['sequence_index'] as int)-(a['sequence_index'] as int)!=1)return reject('angle_sequence_gap');
      if(((b['angle_deg'] as num)-(a['angle_deg'] as num)).abs()>35)return reject('angle_jump');
    }
    final lengths=window.map((p)=>(p['forearm_length_ratio'] as num).toDouble()).toList()..sort();
    if(lengths.last/lengths.first>1.5)return reject('changing_forearm_projection');
    double median(List<Map> points){final a=points.map((p)=>(p['angle_deg'] as num).toDouble()).toList()..sort();return a[1];}
    final begin=median(first),end=median(last),opening=end-begin;
    // Without a visibly set starting angle, absence of additional opening is not normal lag.
    if(begin>100)return reject('initial_set_angle_not_observed');
    final grade=end>=120-1e-8&&opening>=20-1e-8?'casting':end>=100-1e-8||opening>=20-1e-8?'warning':'within_rule';
    out.addAll({'status':'rule_classified','reason':null,'release_enabled':true,'grade':grade,
      'assessment_basis':'top_to_hip_opening','angle_change_measured':true,
      'label':grade=='casting'?'캐스팅 의심':grade=='warning'?'캐스팅 주의':'캐스팅 기준 이내',
      'value':opening,'top_angle_deg':begin,'halfway_angle_deg':end,'opening_change_deg':opening,
      'top_angle_t_ms':first[1]['t_ms'],'halfway_angle_t_ms':last[1]['t_ms'],
      't_ms':half,'evidence_times_ms':window.map((p)=>p['t_ms']).toList(),'observation_count':window.length,
      'measurement':'projected_forearm_shaft_opening_to_observed_hip_height'});
    return out;
  }
}
