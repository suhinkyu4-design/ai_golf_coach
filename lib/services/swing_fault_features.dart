import 'dart:math' as math;
import '../models/swing_model.dart';
import 'over_the_top_service.dart';
import 'casting_observation_service.dart';

/// Image-plane observations, not validated fault diagnoses.
class SwingFaultFeatures {
  static const definitions = <String, List<String>>{
    'standing_up': ['얼리 스탠드업', 'rear', '상체 기울기 감소', 'deg'],
    'early_extension': ['얼리 익스텐션', 'rear', '공 방향 골반 이동', 'torso_ratio'],
    'sway': ['스웨이', 'faceOn', '타깃 반대 방향 골반 이동', 'torso_ratio'],
    'slide': ['슬라이드', 'faceOn', '탑 대비 타깃 방향 골반 이동', 'torso_ratio'],
    'reverse_spine': ['리버스 스파인 앵글', 'faceOn', '탑의 타깃 방향 상체 기울기', 'deg'],
    'chicken_wing': ['치킨윙', 'either', '임팩트 이후 리드 팔꿈치 굽힘 증가', 'deg'],
    'overswing': ['오버스윙', 'either', '탑에서 그립 대비 헤드 하강', 'torso_ratio'],
    'casting': ['캐스팅', 'faceOn', '초기 다운스윙 팔·샤프트 각도 증가', 'deg'],
    'over_the_top': ['오버더탑', 'rear', '같은 손 높이에서 클럽 궤적 차이', 'torso_ratio'],
  };
  static Map<String, dynamic> analyze(
      {required SwingModel swing,
      required Map<String, dynamic> reviewed,
      required List<Map<String, dynamic>> samples,
      required bool confirmed,
      int? targetImageSign,
      int? ballImageSign}) {
    final rows = <Map<String, dynamic>>[];
    final out = <String, dynamic>{
      'version': 'fault_features_1.0',
      'club': swing.club.toLowerCase(),
      'coordinate_space': 'upright_image_pixels',
      'timestamp_basis': 'requested_closest_frame_ms',
      'diagnosis_validated': false,
      'camera_motion_verified': false,
      'reference_profile': null,
      'club_identification_status': swing.club == 'unknown' ? 'not_identified' : 'supplied',
      'patterns': rows
    };
    final a = swing.eventsMs['address'],
        t = swing.eventsMs['top'],
        i = swing.eventsMs['impact'],
        z = swing.eventsMs['finish'];
    final eventsOK = a != null &&
        t != null &&
        i != null &&
        z != null &&
        0 <= a &&
        a < t &&
        t < i &&
        i < z &&
        z <= swing.durationMs;
    final rear =
        swing.view == SwingView.rear || swing.view == SwingView.targetLine;
    final lead = swing.handedness == Handedness.right ? 'left' : 'right',
        trail = swing.handedness == Handedness.right ? 'right' : 'left';
    FrameGeometry? frame(String phase) {
      final r = reviewed[phase], time = swing.eventsMs[phase];
      if (r is! Map ||
          time == null ||
          (r['t_ms'] != time &&
              !(time == swing.durationMs && r['t_ms'] == time - 1)))
        return null;
      final reference = reviewed['address'];
      if (phase != 'address' &&
          reference is Map &&
          (r['width'] != reference['width'] ||
              r['height'] != reference['height'])) return null;
      return FrameGeometry.read(r);
    }

    final base = frame('address'), top = frame('top'), impact = frame('impact');
    out['head_trail_check'] = headTrailCheck(base, top, rear: rear,
      trail: trail, confirmed: confirmed && eventsOK, targetImageSign: targetImageSign);
    final scale = base?.torsoLength;
    final unique = <int, FrameGeometry>{};
    final requestedTimes = <int>{};
    out['duplicate_requested_samples'] = samples.where(FrameGeometry.isDuplicate).length;
    if (eventsOK && base != null) {
      for (final raw in samples) {
        if (FrameGeometry.isDuplicate(raw)) continue;
        final time = raw['t_ms'];
        if (time is int && time >= a && time <= z) requestedTimes.add(time);
        final f = FrameGeometry.read(raw);
        if (f != null && f.t >= a && f.t <= z && f.w == base.w && f.h == base.h)
          unique.putIfAbsent(f.t, () => f);
      }
    }
    final ordered = unique.values.toList()..sort((x, y) => x.t.compareTo(y.t));
    int? target = [-1, 1].contains(targetImageSign) ? targetImageSign : null;
    final lf = base?.joint('${lead}Ankle'), rf = base?.joint('${trail}Ankle');
    if (target == null &&
        !rear &&
        scale != null &&
        lf != null &&
        rf != null &&
        (lf.x - rf.x).abs() > .1 * scale) target = (lf.x - rf.x).sign.toInt();
    final inferredBall = rear ? inferBallSide(base) : <String, dynamic>{'sign': null, 'reason': 'rear_view_required'};
    final suppliedBall = [-1, 1].contains(ballImageSign);
    final ball = suppliedBall ? ballImageSign : inferredBall['sign'] as int?;
    out.addAll({
      'target_image_sign': target,
      'target_direction_basis':
          targetImageSign == null ? 'lead_trail_ankle_inference' : 'supplied',
      'ball_image_sign': ball,
      'ball_direction_basis': suppliedBall ? 'supplied' : ball != null ? 'address_pose_inference' : 'unavailable',
      'ball_direction_evidence': inferredBall
    });
    for (final entry in definitions.entries) {
      final id = entry.key, d = entry.value;
      final points = <Map<String, dynamic>>[];
      final row = <String, dynamic>{
        'id': id,
        'label': d[0],
        'view': d[1],
        'metric': d[2],
        'unit': d[3],
        'status': 'unavailable',
        'reason': null,
        'diagnosis': null,
        'observations': points,
        'assessment_blockers': [
          'reference_not_validated',
          'camera_motion_not_verified'
        ]
      };
      rows.add(row);
      void reject(String reason) {
        row['reason'] = reason;
      }

      if (!['driver', '7i', 'unknown'].contains(swing.club.toLowerCase())) {
        reject('unsupported_club');
        continue;
      }
      if (!confirmed || !eventsOK) {
        reject('reviewed_events_required');
        continue;
      }
      if (swing.view == SwingView.unknown ||
          (d[1] == 'rear' && !rear) ||
          (d[1] == 'faceOn' && swing.view != SwingView.faceOn)) {
        reject('different_view_required');
        continue;
      }
      if (base == null ||
          scale == null ||
          scale < .01 * math.sqrt(base.w * base.w + base.h * base.h)) {
        reject('baseline_unavailable');
        continue;
      }
      if (['sway', 'slide', 'reverse_spine'].contains(id) && target == null) {
        reject('target_direction_unknown');
        continue;
      }
      if (['early_extension', 'over_the_top'].contains(id) && ball == null) {
        reject('ball_direction_unknown');
        continue;
      }
      final back = ordered.where((f) => f.t > a && f.t <= t).toList();
      final down = ordered.where((f) => f.t > t && f.t < i).toList();
      final follow =
          ordered.where((f) => f.t > i && f.t <= math.min(z, i + 150)).toList();
      void add(FrameGeometry f, double? v,
          {Map<String, dynamic> extra = const {}}) {
        if (v != null && v.isFinite)
          points.add({'t_ms': f.t, 'value': v, ...extra});
      }

      final backCount =
          requestedTimes.where((time) => time > a && time <= t).length;
      final downCount =
          requestedTimes.where((time) => time > t && time < i).length;
      var expected = 0;
      switch (id) {
        case 'standing_up':
          final throughImpact = ordered.where((f) => f.t > t && f.t <= i);
          expected = requestedTimes.where((time) => time > t && time <= i).length;
          for (final f in throughImpact) {
            if (base.torsoTilt != null && f.torsoTilt != null)
              add(f, base.torsoTilt!.abs() - f.torsoTilt!.abs());
          }
          break;
        case 'early_extension':
        case 'sway':
        case 'slide':
          final seq = id == 'sway' ? back : down;
          expected = id == 'sway' ? backCount : downCount;
          final origin = id == 'slide' ? top?.hip : base.hip;
          final sign = id == 'early_extension'
              ? ball!
              : (id == 'sway' ? -target! : target!);
          for (final f in seq) {
            if (origin != null && f.hip != null)
              add(f, sign * (f.hip!.x - origin.x) / scale);
          }
          break;
        case 'reverse_spine':
          expected = 1;
          if (top != null && top.torsoTilt != null)
            add(top, target! * top.torsoTilt!);
          break;
        case 'chicken_wing':
          expected = requestedTimes
              .where((time) => time > i && time <= math.min(z, i + 150))
              .length;
          final initial = impact?.elbow(lead);
          for (final f in follow) {
            final angle = f.elbow(lead), elbow = f.joint('${lead}Elbow');
            if (initial != null &&
                angle != null &&
                elbow != null &&
                f.shoulder != null)
              add(f, initial - angle, extra: {
                'elbow_angle_deg': angle,
                'elbow_to_shoulder_midpoint_ratio':
                    (elbow - f.shoulder!).magnitude / scale
              });
          }
          break;
        case 'overswing':
          expected = 1;
          if (top?.head != null && top?.grip != null)
            add(top!, (top.head!.y - top.grip!.y) / scale);
          break;
        case 'casting':
          final early = down.where((f) => f.t <= t + (i - t) ~/ 2).toList();
          expected = requestedTimes
              .where((time) => time > t && time <= t + (i - t) ~/ 2)
              .length;
          final initial = top?.shaftAngle(lead);
          for (final f in early) {
            final angle = f.shaftAngle(lead);
            if (initial != null && angle != null)
              add(f, angle - initial,
                  extra: {'forearm_shaft_angle_deg': angle});
          }
          break;
        case 'over_the_top':
          expected = downCount;
          for (final f in down) {
            final grip = f.grip, head = f.head;
            if (grip == null || head == null) continue;
            final matches = back
                .where((b) =>
                    b.grip != null &&
                    b.head != null &&
                    (b.grip!.y - grip.y).abs() <= .05 * scale)
                .toList()
              ..sort((x, y) => (x.grip!.y - grip.y)
                  .abs()
                  .compareTo((y.grip!.y - grip.y).abs()));
            if (matches.isEmpty) continue;
            final b = matches.first;
            add(f, ball! * (head.x - b.head!.x) / scale, extra: {
              'matched_backswing_t_ms': b.t,
              'grip_outward_difference_ratio':
                  ball * (grip.x - b.grip!.x) / scale
            });
          }
          break;
      }
      row.addAll({
        'expected_samples': expected,
        'valid_samples': points.length,
        'coverage': expected == 0 ? 0.0 : points.length / expected
      });
      final single = ['reverse_spine', 'overswing'].contains(id);
      if (points.length < (single ? 1 : 3) ||
          expected == 0 ||
          points.length / expected < .7) {
        reject(['overswing', 'casting', 'over_the_top'].contains(id)
            ? 'verified_club_track_required'
            : 'insufficient_joint_samples');
        continue;
      }
      final smooth = <Map<String, dynamic>>[];
      for (var j = 0; j < points.length; j++) {
        if (!single && (j == 0 || j == points.length - 1)) continue;
        if (!single &&
            ((points[j]['t_ms'] as int) - (points[j - 1]['t_ms'] as int) >
                    100 ||
                (points[j + 1]['t_ms'] as int) - (points[j]['t_ms'] as int) >
                    100)) continue;
        final values = single
            ? [points[j]['value'] as double]
            : [
                points[j - 1]['value'] as double,
                points[j]['value'] as double,
                points[j + 1]['value'] as double
              ];
        values.sort();
        smooth.add(
            {'t_ms': points[j]['t_ms'], 'value': values[values.length ~/ 2]});
      }
      if (smooth.isEmpty) {
        reject('sampling_gaps_too_large');
        continue;
      }
      row['peak'] = smooth.reduce(
          (x, y) => (x['value'] as double) >= (y['value'] as double) ? x : y);
      row['status'] = 'measured_not_classified';
      row['smoothing'] = single ? 'none_keyframe' : 'median3_max_gap_100ms';
    }
    out['casting_check'] = CastingObservationService.measure(samples: samples,
      topMs: t, impactMs: i, lead: lead, view: swing.view.name,
      eventsConfirmed: confirmed && eventsOK);
    out['over_the_top_check'] = OverTheTopService.measure(samples: samples,
      addressMs: a, topMs: t, impactMs: i, rear: rear, ballSign: ball,
      eventsConfirmed: confirmed && eventsOK);
    out['trail_knee_check'] = trailKneeCheck(base, top, trail: trail, confirmed: confirmed && eventsOK);
    out['head_up_check'] = headUpCheck(base, samples, topMs: t, impactMs: i, confirmed: confirmed && eventsOK);
    out['early_extension_check'] = earlyExtensionCheck(base, impact, rear: rear, confirmed: confirmed && eventsOK, ballSign: ball);
    out['chicken_wing_check'] = classifyChickenWing(rows.firstWhere((r) => r['id'] == 'chicken_wing'));
    out['standing_up_check'] = classifyStandingUp(rows.firstWhere((r) => r['id'] == 'standing_up'));
    return out;
  }

  /// Initial image-plane knee extension rule, not a clinical lockout diagnosis.
  static Map<String,dynamic> trailKneeCheck(FrameGeometry? address, FrameGeometry? top,
      {required String trail, required bool confirmed}) {
    final out=<String,dynamic>{'status':'unavailable','reason':null,'diagnosis':null,
      'assessment':'observation_only','side':trail,'camera_motion_verified':false};
    if(!confirmed || address==null || top==null) {
      out['reason']=!confirmed?'reviewed_events_required':'baseline_unavailable';return out;
    }
    if(!['left','right'].contains(trail) || address.w!=top.w || address.h!=top.h) {
      out['reason']='insufficient_joint_samples';return out;
    }
    double? knee(FrameGeometry f)=>f.angle(f.joint('${trail}Hip'),f.joint('${trail}Knee'),f.joint('${trail}Ankle'));
    final a=knee(address), b=knee(top);
    if(a==null || b==null){out['reason']='insufficient_joint_samples';return out;}
    final value=math.max(0.0,b-a);
    out.addAll({'status':'measured_not_classified','value':value,'signed_change_deg':b-a,
      'address_angle_deg':a,'top_angle_deg':b,'t_ms':top.t,
      'label':'뒷무릎 움직임 · 참고 수치',
      'note':'자연스러운 무릎 펴짐을 포함하는 참고 수치입니다. 독립적인 오류 판정에 사용하지 않습니다.'});
    return out;
  }

  /// Vertical head rise proxy using image coordinates and address torso length.
  static Map<String, dynamic> headUpCheck(FrameGeometry? address,
      List<Map<String, dynamic>> samples, {int? topMs, int? impactMs, required bool confirmed}) {
    final out = <String, dynamic>{'status': 'unavailable', 'reason': null,
      'diagnosis': null, 'threshold_basis': 'initial_head_rise_proxy_rule',
      'warning_threshold': .10, 'threshold': .20, 'normalization': 'address_torso_length',
      'head_rotation_measured': false, 'camera_motion_verified': false};
    if (!confirmed || topMs == null || impactMs == null || topMs >= impactMs) {
      out['reason'] = 'reviewed_events_required'; return out;
    }
    final head = address?.midpoint('leftEye', 'rightEye'), scale = address?.torsoLength;
    if (address == null || head == null || scale == null ||
        scale < .01 * math.sqrt(address.w * address.w + address.h * address.h)) {
      out['reason'] = 'baseline_unavailable'; return out;
    }
    final requested = <int>{};
    final points = <int,double>{};
    for(final raw in samples) {
      final time = raw['t_ms'];
      if(time is! int || time <= topMs || time > impactMs) continue;
      if(FrameGeometry.isDuplicate(raw))continue;
      requested.add(time);
      final f=FrameGeometry.read(raw), h=FrameGeometry.read(raw)?.midpoint('leftEye','rightEye');
      if(f != null && h != null && f.w == address.w && f.h == address.h)
        points[time]=(head.y-h.y)/scale;
    }
    out.addAll({'valid_samples':points.length,'expected_samples':requested.length});
    if(points.length<3 || requested.isEmpty || points.length/requested.length<.7) {
      out['reason']='insufficient_joint_samples';return out;
    }
    final times=points.keys.toList()..sort();
    double? peak; int? peakTime;
    for(var j=1;j<times.length-1;j++) {
      if(times[j]-times[j-1]>100 || times[j+1]-times[j]>100)continue;
      final v=[points[times[j-1]]!,points[times[j]]!,points[times[j+1]]!]..sort();
      if(peak == null || v[1]>peak){peak=v[1];peakTime=times[j];}
    }
    if(peak == null){out['reason']='sampling_gaps_too_large';return out;}
    final value=math.max(0.0,peak);
    final grade=value>=.20?'head_up':value>=.10?'warning':'within_rule';
    out.addAll({'status':'rule_classified','grade':grade,'value':value,'signed_ratio':peak,
      't_ms':peakTime,'label':grade=='head_up'?'헤드업 감지':grade=='warning'?'헤드업 주의':'헤드업 기준 이내',
      'note':'어드레스보다 머리가 높아지는 움직임을 판정합니다. 고개 회전이나 시선 이동은 측정하지 않습니다.'});
    return out;
  }

  /// Elbow-only application rule. Wrist cupping is not measured.
  static Map<String, dynamic> classifyChickenWing(Map row) {
    final out = <String, dynamic>{'status': 'unavailable', 'reason': row['reason'],
      'diagnosis': null, 'threshold_basis': 'initial_elbow_proxy_rule',
      'warning_threshold': 15.0, 'threshold': 30.0, 'window_ms': 150,
      'unit': 'deg', 'wrist_cupping_measured': false};
    final peak = row['peak'];
    if (row['status'] != 'measured_not_classified' || peak is! Map ||
        peak['value'] is! num || !(peak['value'] as num).isFinite) return out;
    final value = math.max(0.0, (peak['value'] as num).toDouble());
    final grade = value >= 30 ? 'chicken_wing' : value >= 15 ? 'warning' : 'within_rule';
    out.addAll({'status': 'rule_classified', 'grade': grade,
      'label': grade == 'chicken_wing' ? '치킨윙 감지' : grade == 'warning' ? '치킨윙 주의' : '치킨윙 기준 이내',
      'value': value, 'signed_change_deg': peak['value'], 't_ms': peak['t_ms'],
      'note': '임팩트 직후 리드 팔꿈치 굽힘 증가로 판단하는 앱 근사 기준입니다. 손목 형태와 3D 팔 회전은 측정하지 않습니다.'});
    return out;
  }

  /// Hip-centre proxy, not a silhouette/tush-line measurement.
  static Map<String, dynamic> earlyExtensionCheck(FrameGeometry? address,
      FrameGeometry? impact, {required bool rear, required bool confirmed,
      int? ballSign}) {
    final out = <String, dynamic>{'status': 'unavailable', 'reason': null,
      'diagnosis': null, 'threshold_basis': 'user_selected_proxy_rule',
      'warning_threshold': .10, 'threshold': .25,
      'normalization': 'address_projected_heel_to_toe_length',
      'measurement': 'hip_midpoint_forward_displacement',
      'tush_line_measured': false, 'camera_motion_verified': false};
    if (!confirmed || !rear || address == null || impact == null) {
      out['reason'] = !confirmed ? 'reviewed_events_required' : !rear ? 'different_view_required' : 'baseline_unavailable';
      return out;
    }
    if (![-1, 1].contains(ballSign)) { out['reason'] = 'ball_direction_unknown'; return out; }
    final h0 = address.hip, h1 = impact.hip;
    if (h0 == null || h1 == null || address.w != impact.w || address.h != impact.h) {
      out['reason'] = 'insufficient_joint_samples'; return out;
    }
    double length = 0;
    String? foot;
    for (final side in ['left','right']) {
      final heel = address.joint('${side}Heel'), toe = address.joint('${side}FootIndex');
      if (heel != null && toe != null && (heel - toe).magnitude > length) {
        length = (heel - toe).magnitude; foot = side;
      }
    }
    if (length < .01 * math.sqrt(address.w * address.w + address.h * address.h)) {
      out['reason'] = 'foot_length_unavailable'; return out;
    }
    final signed = ballSign! * (h1.x - h0.x) / length;
    final value = math.max(0.0, signed);
    final grade = value >= .25 ? 'early_extension' : value >= .10 ? 'warning' : 'within_rule';
    out.addAll({'status': 'rule_classified', 'grade': grade,
      'label': grade == 'early_extension' ? '배치기 감지' : grade == 'warning' ? '배치기 주의' : '배치기 기준 이내',
      'value': value, 'signed_ratio': signed, 't_ms': impact.t,
      'baseline_pixels': length, 'normalization_foot': foot,
      'ball_image_sign': ballSign,
      'torso_tilt_reduction_deg': address.torsoTilt != null && impact.torsoTilt != null
        ? address.torsoTilt!.abs() - impact.torsoTilt!.abs() : null,
      'note': '골반 관절 중심 이동을 이용한 배치기 근사 판정입니다. 엉덩이 외곽선 이탈을 직접 측정한 값은 아닙니다.'});
    return out;
  }

  /// Initial application thresholds, not validated population reference values.
  static Map<String, dynamic> classifyStandingUp(Map row) {
    final out = <String, dynamic>{'status': 'unavailable', 'reason': row['reason'],
      'diagnosis': null, 'threshold_basis': 'initial_app_rule',
      'warning_threshold': 5.0, 'threshold': 10.0, 'unit': 'deg',
      'camera_motion_verified': false};
    final peak = row['peak'];
    if (row['status'] != 'measured_not_classified' || peak is! Map ||
        peak['value'] is! num || !(peak['value'] as num).isFinite) return out;
    final value = math.max(0.0, (peak['value'] as num).toDouble());
    final grade = value >= 10 ? 'standing_up' : value >= 5 ? 'warning' : 'within_rule';
    out.addAll({'status': 'rule_classified', 'grade': grade,
      'label': grade == 'standing_up' ? '얼리 스탠드업 감지' : grade == 'warning'
        ? '얼리 스탠드업 주의' : '얼리 스탠드업 기준 이내',
      'value': value, 'signed_change_deg': peak['value'], 't_ms': peak['t_ms'],
      'note': '어드레스 대비 상체 기울기 감소. 화면상 어깨·골반 중심선 기준이며 촬영 각도와 몸통 회전의 영향을 받습니다.'});
    return out;
  }

  /// Screen-side heuristic only: does not locate a ball or measure camera angle.
  static Map<String, dynamic> inferBallSide(FrameGeometry? frame) {
    final result = <String, dynamic>{'sign': null, 'reason': null,
      'method': 'address_wrists_and_torso', 'ball_detected': false};
    final hip = frame?.hip, shoulder = frame?.shoulder;
    final left = frame?.joint('leftWrist'), right = frame?.joint('rightWrist');
    final scale = frame?.torsoLength;
    if (frame == null || hip == null || shoulder == null || left == null ||
        right == null || scale == null ||
        scale < .01 * math.sqrt(frame.w * frame.w + frame.h * frame.h)) {
      result['reason'] = 'address_joints_unreliable';
      return result;
    }
    final dl = (left.x - hip.x) / scale, dr = (right.x - hip.x) / scale;
    final lean = (shoulder.x - hip.x) / scale;
    result.addAll({'left_wrist_offset': dl, 'right_wrist_offset': dr,
      'shoulder_offset': lean});
    // Engineering ambiguity gates, not golf fault thresholds.
    if (dl.abs() < .15 || dr.abs() < .15 || dl.sign != dr.sign ||
        lean.abs() < .05 || lean.sign != dl.sign ||
        left.y <= shoulder.y || right.y <= shoulder.y ||
        (left - right).magnitude > .6 * scale) {
      result['reason'] = 'address_direction_ambiguous';
      return result;
    }
    result['sign'] = dl.sign.toInt();
    return result;
  }

  /// User-selected application rule. Not a population-validated threshold.
  static Map<String, dynamic> headTrailCheck(FrameGeometry? address,
      FrameGeometry? top, {required bool rear, required String trail,
      required bool confirmed, int? targetImageSign}) {
    final out = <String, dynamic>{
      'status': 'unavailable', 'reason': null, 'diagnosis': null,
      'threshold': .50, 'warning_threshold': .25,
      'threshold_basis': 'user_selected_app_rule',
      'normalization': 'address_projected_ear_width',
      'camera_motion_verified': false, 'candidate': null,
    };
    if (!confirmed || address == null || top == null) {
      out['reason'] = !confirmed ? 'reviewed_events_required' : 'baseline_unavailable';
      return out;
    }
    final h0 = address.midpoint('leftEye', 'rightEye');
    final h1 = top.midpoint('leftEye', 'rightEye');
    final earL = address.joint('leftEar'), earR = address.joint('rightEar');
    if (h0 == null || h1 == null ||
        address.w != top.w || address.h != top.h) {
      out['reason'] = 'head_width_unavailable';
      return out;
    }
    out.addAll({'head_position_measured':true, 't_ms':top.t,
      'horizontal_displacement_px':h1.x-h0.x,
      'vertical_displacement_px':h1.y-h0.y,
      'head_center_basis':'paired_eye_midpoint'});
    var width = earL == null || earR == null ? 0.0 : (earL.x - earR.x).abs();
    var warning = .25, threshold = .50;
    final minimumWidth = .01 * math.sqrt(address.w * address.w + address.h * address.h);
    if (width < minimumWidth) {
      final sl = address.joint('leftShoulder'), sr = address.joint('rightShoulder');
      width = sl == null || sr == null ? 0.0 : (sl.x - sr.x).abs();
      warning = .07; threshold = .12;
      out.addAll({'normalization': 'address_projected_shoulder_width', 'warning_threshold': warning, 'threshold': threshold});
    }
    if (width < minimumWidth) {
      out['ear_width_px']=earL == null || earR == null ? null : (earL.x-earR.x).abs();
      out['shoulder_width_px']=width;
      out['minimum_reference_width_px']=minimumWidth;
      out['reason'] = 'projected_reference_width_too_small';
      return out;
    }
    int? target = [-1, 1].contains(targetImageSign) ? targetImageSign : null;
    final lead = trail == 'right' ? 'left' : 'right';
    final leadFoot = address.joint('${lead}Ankle'), trailFoot = address.joint('${trail}Ankle');
    if (target == null && leadFoot != null && trailFoot != null &&
        (leadFoot.x - trailFoot.x).abs() >= .01 * address.w) {
      target = (leadFoot.x - trailFoot.x).sign.toInt();
    }
    if (target == null) {
      out['reason'] = 'target_direction_unknown';
      return out;
    }
    final ratio = -target * (h1.x - h0.x) / width;
    final grade = ratio >= threshold ? 'sway' : ratio >= warning ? 'warning' : 'within_rule';
    out.addAll({'status': 'rule_classified', 'value': ratio,
      'grade': grade, 'label': grade == 'sway' ? '스웨이 감지' : grade == 'warning' ? '스웨이 주의' : '스웨이 기준 이내',
      'candidate': ratio >= threshold, 't_ms': top.t,
      'normalization_label': out['normalization'] == 'address_projected_ear_width' ? '머리 너비 추정값' : '어깨 너비',
      'baseline_pixels': width, 'target_image_sign': target,
      'direction_basis': [-1, 1].contains(targetImageSign) ? 'supplied' : 'address_ankles',
      'note': '사용자 지정 기준입니다. 머리 또는 어깨 너비로 정규화하며 촬영 각도·고개 회전·카메라 흔들림의 영향을 받습니다.'});
    return out;
  }

}

class FrameGeometry {
  final int t;
  final double w, h;
  final Map raw;
  FrameGeometry(this.t, this.w, this.h, this.raw);
  static bool isDuplicate(Map raw) {
    // Closest-frame extraction can return one decoded image at several
    // requested timestamps. These are not independent motion observations.
    for (final key in ['shaft_candidate', 'near_shaft_candidate']) {
      final track = raw[key];
      if (track is Map && track['duplicate_frame_of_t_ms'] != null) return true;
    }
    return false;
  }

  static FrameGeometry? read(Map raw) {
    if (isDuplicate(raw)) return null;
    final t = raw['t_ms'], w = raw['width'], h = raw['height'];
    if (t is! int ||
        w is! num ||
        h is! num ||
        !w.isFinite ||
        !h.isFinite ||
        w <= 0 ||
        h <= 0 ||
        (raw['pose_count'] != null && raw['pose_count'] != 1)) return null;
    return FrameGeometry(t, w.toDouble(), h.toDouble(), raw);
  }

  math.Point<double>? point(Map p) {
    final x = p['x'], y = p['y'];
    if (x is! num ||
        y is! num ||
        !x.isFinite ||
        !y.isFinite ||
        x < 0 ||
        y < 0 ||
        x >= w ||
        y >= h) return null;
    return math.Point(x.toDouble(), y.toDouble());
  }

  math.Point<double>? joint(String name) {
    final list = raw['landmarks'];
    if (list is! List) return null;
    final found =
        list.whereType<Map>().where((p) => p['name'] == name).toList();
    if (found.length != 1) return null;
    final c = found.single['likelihood'];
    if (c is! num || !c.isFinite || c < .7 || c > 1) return null;
    return point(found.single);
  }

  math.Point<double>? midpoint(String a, String b) {
    final p = joint(a), q = joint(b);
    return p == null || q == null ? null : (p + q) * .5;
  }

  math.Point<double>? get hip => midpoint('leftHip', 'rightHip');
  math.Point<double>? get shoulder => midpoint('leftShoulder', 'rightShoulder');
  double? get torsoLength =>
      hip == null || shoulder == null ? null : (shoulder! - hip!).magnitude;
  double? get torsoTilt => torsoLength == null ||
          torsoLength! < .01 * math.sqrt(w * w + h * h)
      ? null
      : math.atan2(shoulder!.x - hip!.x, hip!.y - shoulder!.y) * 180 / math.pi;
  double? angle(
      math.Point<double>? a, math.Point<double>? b, math.Point<double>? c) {
    if (a == null || b == null || c == null) return null;
    final u = a - b, v = c - b, m = .01 * math.sqrt(w * w + h * h);
    if (u.magnitude < m || v.magnitude < m) return null;
    return math.acos(((u.x * v.x + u.y * v.y) / (u.magnitude * v.magnitude))
            .clamp(-1.0, 1.0)) *
        180 /
        math.pi;
  }

  double? elbow(String side) => angle(
      joint('${side}Shoulder'), joint('${side}Elbow'), joint('${side}Wrist'));
  math.Point<double>? clubPoint(String key) {
    final c = raw['club'];
    if (c is! Map ||
        c['identity_verified'] != true ||
        c['t_ms'] != t ||
        c['coordinate_space'] != 'upright_image_pixels' ||
        c[key] is! Map) return null;
    return point(c[key] as Map);
  }

  math.Point<double>? get head => clubPoint('head');
  math.Point<double>? get grip => clubPoint('grip');
  double? shaftAngle(String side) => angle(joint('${side}Elbow'), grip, head);
}
