import 'dart:io';
import 'dart:math' as math;
import 'package:image/image.dart' as img;
import 'swing_fault_features.dart';

/// Experimental shaft observations. A visible line end is NOT a club head.
/// Never promote these candidates to FrameGeometry's verified club channel.
class ClubTrackingService {
  static const version = 'shaft_candidates_8';

  static Map<String, dynamic> detect(img.Image image, Map<String, dynamic> row,
      {img.Image? background, bool nearGrip = false, bool includeDiagnostics = false}) {
    // Closest-frame extraction can return the same decoded image for several
    // requested times. Such duplicates are not independent tracking evidence.
    var signature=2166136261;
    for(var y=0;y<image.height;y+=math.max(1,image.height~/32)) {
      for(var x=0;x<image.width;x+=math.max(1,image.width~/32)) {
        final p=image.getPixel(x,y);
        for(final value in [p.r.toInt(),p.g.toInt(),p.b.toInt()]) {
          signature=((signature^value)*16777619)&0xffffffff;
        }
      }
    }
    final out = <String, dynamic>{
      'version': version, 't_ms': row['t_ms'], 'status': 'unavailable',
      'tracking_region': nearGrip ? 'near_grip' : 'full_ray',
      'frame_signature':signature.toRadixString(16),
      'coordinate_space': 'upright_image_pixels', 'identity_verified': false,
      'head_detected': false, 'reason': 'hands_unavailable',
    };
    final f = FrameGeometry.read(row);
    if (f == null || image.width != f.w || image.height != f.h) {
      out['reason'] = 'invalid_frame_geometry'; return out;
    }
    final left = f.joint('leftWrist'), right = f.joint('rightWrist');
    final torso = f.torsoLength;
    if (left == null || right == null || torso == null || torso < image.height*.01 ||
        left.distanceTo(right) > torso * .4) return out;
    final grip = math.Point((left.x + right.x)/2, (left.y + right.y)/2);
    // Preserve more pixels around the grip: a thin shaft can disappear when
    // shrinking a full portrait frame to 640px. Short mode never searches for
    // a distant club head and keeps its radial search within one torso length.
    final factor = math.min(1.0, (nearGrip ? 1280 : 640) / image.height);
    final small = factor < 1 ? img.copyResize(image,
        width: (image.width*factor).round(), height: (image.height*factor).round()) : image;
    final sx = small.width / image.width, sy = small.height / image.height;
    // Resize only the image, retaining original coordinates in all outputs.
    final scale = torso * sy, gx = grip.x*sx, gy = grip.y*sy;
    final bg = background == null ? null : img.copyResize(background,
        width: small.width, height: small.height);
    double lum(img.Image im, double x, double y) {
      final p = im.getPixel(x.round().clamp(0, im.width-1), y.round().clamp(0, im.height-1));
      return p.r*.299 + p.g*.587 + p.b*.114;
    }
    bool inside(double x, double y) => x >= 5 && y >= 5 && x < small.width-5 && y < small.height-5;
    var candidates = <Map<String, dynamic>>[];
    final centeredCandidates = <Map<String,dynamic>>[];
    for (var degrees = 0; degrees < 360; degrees += 2) {
      final angle = degrees*math.pi/180, ux = math.cos(angle), uy = math.sin(angle);
      // A forearm running back toward an elbow is not shaft evidence.
      var arm = false;
      for (final side in ['left', 'right']) {
        final elbow = f.joint('${side}Elbow');
        if (elbow == null) continue;
        final dx = elbow.x-grip.x, dy = elbow.y-grip.y;
        final len = math.sqrt(dx*dx+dy*dy);
        if (len > torso*.2 && (dx*ux+dy*uy)/len > .94) arm = true;
      }
      if (arm) continue;
      Map<String,dynamic>? angleBest;
      // Keep one fixed lateral offset along the whole ray, rather than hopping
      // between unrelated pixels at each radius. Wrist coordinates are not the grip.
      final shifts = nearGrip ? [-.08, -.04, 0.0, .04, .08] : [0.0];
      for (final shift in shifts) {
      final offsetPx = (shift*scale).clamp(-12.0,12.0);
      final originX=gx-uy*offsetPx, originY=gy+ux*offsetPx;
      var hits=0, moving=0, total=0, gap=0;
      var lastHit=0.0, bestScore=0.0, bestLength=0.0, bestCoverage=0.0, bestMoving=0.0;
      final minLength = scale * (nearGrip ? .35 : .5);
      for (double radius=math.max(6, scale*(nearGrip ? .10 : .16));
          radius <= scale*(nearGrip ? .85 : 2.2); radius += 2) {
        final x=originX+ux*radius, y=originY+uy*radius;
        if (!inside(x,y)) break;
        total++;
        var contrast=0.0, changed=false;
        for (final offset in [-1.5, 0.0, 1.5]) {
          final cx=x-uy*offset, cy=y+ux*offset;
          final center=lum(small,cx,cy);
          final a=center-lum(small,cx-uy*4,cy+ux*4);
          final b=center-lum(small,cx+uy*4,cy-ux*4);
          final ridge=a*b > 0 ? math.min(a.abs(),b.abs()) : 0.0;
          if (ridge > contrast) {
            contrast=ridge;
            changed=bg != null && (center-lum(bg,cx,cy)).abs() >= 10;
          }
        }
        if (contrast >= 12) { hits++; gap=0; lastHit=radius; if(changed) moving++; }
        else { gap++; }
        if (radius >= minLength && hits >= 8) {
          final coverage=hits/total, motion=hits == 0 ? 0.0 : moving/hits;
          // A tiny high-contrast patch must not outrank a longer supported shaft.
          // Normalize near-grip support by the searched radius, keeping full rays unchanged.
          final extent=nearGrip ? math.min(1.0,lastHit/(scale*.85)) : 1.0;
          final score=coverage*.75*extent + math.min(1.0,lastHit/scale)*.25 - shift.abs()*.2;
          if (coverage >= .60 && motion >= .40 && lastHit >= minLength && score > bestScore) {
            bestScore=score;bestLength=lastHit;bestCoverage=coverage;bestMoving=motion;
          }
        }
        if (gap >= 6 && radius > minLength) break;
      }
      if (bestScore > 0) {
        // Independent pixels beyond the near-grip search help distinguish a
        // shaft from a short shirt/screen edge. Missing extension is not failure.
        var extensionSamples=0,extensionHits=0,extensionMoving=0;
        if(nearGrip) {
          for(double radius=scale*.9;radius<=scale*1.4;radius+=2) {
            final x=originX+ux*radius,y=originY+uy*radius;
            if(!inside(x,y))break;
            extensionSamples++;
            var ridgeBest=0.0,changed=false;
            for(final offset in [-1.5,0.0,1.5]) {
              final cx=x-uy*offset,cy=y+ux*offset,center=lum(small,x-uy*offset,y+ux*offset);
              final a=center-lum(small,cx-uy*4,cy+ux*4);
              final b=center-lum(small,cx+uy*4,cy-ux*4);
              final ridge=a*b>0?math.min(a.abs(),b.abs()):0.0;
              if(ridge>ridgeBest){ridgeBest=ridge;changed=bg!=null&&(center-lum(bg,cx,cy)).abs()>=10;}
            }
            if(ridgeBest>=12){extensionHits++;if(changed)extensionMoving++;}
          }
        }
        final extensionCoverage=extensionSamples==0?0.0:extensionHits/extensionSamples;
        final extensionMotion=extensionHits==0?0.0:extensionMoving/extensionHits;
        final extensionSupported=extensionSamples>=10&&extensionCoverage>=.60&&extensionMotion>=.40;
        if(extensionSupported)bestScore+=.20*extensionCoverage;
        final candidate = <String,dynamic>{
          'angle_deg': degrees, 'score': bestScore, 'coverage': bestCoverage,
          'extension_supported':extensionSupported,'extension_coverage':extensionCoverage,
          'extension_samples':extensionSamples,'extension_moving_fraction':extensionMotion,
          'moving_fraction': bestMoving, 'length_px': bestLength/sy,
          'grip': {'x':originX/sx, 'y':originY/sy},
          'grip_offset_px':offsetPx/sy,
          'shaft_end': {'x': (originX+ux*bestLength)/sx, 'y': (originY+uy*bestLength)/sy},
        };
        if (shift == 0) centeredCandidates.add(candidate);
        if (angleBest == null || bestScore > (angleBest['score'] as double)) angleBest=candidate;
      }
      }
      if (angleBest != null) candidates.add(angleBest);
    }
    centeredCandidates.sort((a,b)=>(b['score'] as double).compareTo(a['score'] as double));
    // Do not let the larger offset search replace a clear original observation.
    if(centeredCandidates.isNotEmpty) {
      final centerBest=centeredCandidates.first;
      final rival=centeredCandidates.where((c)=>angleDistance(
        (c['angle_deg'] as num).toDouble(),(centerBest['angle_deg'] as num).toDouble())>=18).toList();
      final clear=rival.isEmpty||(centerBest['score'] as double)-(rival.first['score'] as double)>=.06;
      if(clear) {
        candidates=centeredCandidates;
        out['origin_selection']='clear_centered_observation';
      } else {
        out['origin_selection']='offset_search_for_ambiguous_center';
      }
    } else {out['origin_selection']='offset_search_no_centered_line';}
    candidates.sort((a,b)=>(b['score'] as double).compareTo(a['score'] as double));
    if (candidates.isEmpty) { out['reason']='no_moving_shaft_line'; return out; }
    final best=candidates.first;
    final alternatives=candidates.where((c)=>angleDistance(
        (best['angle_deg'] as num).toDouble(),(c['angle_deg'] as num).toDouble())>=18).toList();
    final margin=alternatives.isEmpty ? 1.0 : (best['score'] as double)-(alternatives.first['score'] as double);
    final hypotheses=<Map<String,dynamic>>[];
    for(final candidate in candidates) {
      if ((best['score'] as double)-(candidate['score'] as double) > .12) continue;
      if (hypotheses.every((h)=>angleDistance((h['angle_deg'] as num).toDouble(),
          (candidate['angle_deg'] as num).toDouble())>=18)) hypotheses.add(candidate);
      if(hypotheses.length==4)break;
    }
    if(includeDiagnostics) out['ranked_candidates']=candidates;
    out['hypotheses']=hypotheses;
    out.addAll(best);
    out.addAll({'wrist_midpoint': {'x':grip.x,'y':grip.y}, 'ambiguity_margin':margin,
      'status': margin >= .06 ? 'line_candidate' : 'ambiguous',
      'reason': margin >= .06 ? 'temporal_check_pending' : 'competing_lines',
      'score_is_probability': false, 'torso_length_px':torso,
      'forearms': {for (final side in ['left', 'right'])
        if (f.joint('${side}Elbow') != null && f.joint('${side}Wrist') != null)
          side: {
            'elbow': {'x':f.joint('${side}Elbow')!.x,'y':f.joint('${side}Elbow')!.y},
            'wrist': {'x':f.joint('${side}Wrist')!.x,'y':f.joint('${side}Wrist')!.y},
          }},
      'width':row['width'],'height':row['height']});
    return out;
  }

  static double angleDistance(double a, double b) {
    final d=(a-b).abs()%360; return math.min(d,360-d);
  }

  /// No gap interpolation and no identity claims, including on smooth tracks.
  static void checkContinuity(List<Map<String,dynamic>> rows) {
    rows.sort((a,b)=>(a['t_ms'] as int).compareTo(b['t_ms'] as int));
    final distinct=<Map<String,dynamic>>[];
    Map<String,dynamic>? previous;
    for(final row in rows) {
      row['temporally_supported']=false;
      if(row['frame_signature']!=null&&row['frame_signature']==previous?['frame_signature']) {
        row['duplicate_frame_of_t_ms']=previous!['t_ms'];
        row['reason']='duplicate_decoded_frame';
        continue;
      }
      previous=row;distinct.add(row);
    }
    // Resolve an ambiguous observation only between two unambiguous anchors.
    // All choices must already have image support; never synthesize a shaft.
    final originals=[for(final row in distinct) row['status']];
    for(var j=1;j<distinct.length-1;j++) {
      final a=distinct[j-1],b=distinct[j],c=distinct[j+1];
      if(originals[j]!='ambiguous'||originals[j-1]!='line_candidate'||
          originals[j+1]!='line_candidate'||b['hypotheses'] is! List)continue;
      if((b['t_ms'] as int)-(a['t_ms'] as int)>100||
          (c['t_ms'] as int)-(b['t_ms'] as int)>100)continue;
      final aa=(a['angle_deg'] as num).toDouble(),cc=(c['angle_deg'] as num).toDouble();
      if(angleDistance(aa,cc)>30)continue;
      final viable=(b['hypotheses'] as List).whereType<Map>().where((h)=>
        angleDistance((h['angle_deg'] as num).toDouble(),aa)<=16&&
        angleDistance((h['angle_deg'] as num).toDouble(),cc)<=16).toList();
      if(viable.length!=1)continue;
      b['original_status']='ambiguous';b['original_angle_deg']=b['angle_deg'];
      for(final key in ['angle_deg','score','coverage','moving_fraction',
          'length_px','grip','grip_offset_px','shaft_end',
      'extension_supported','extension_coverage','extension_samples','extension_moving_fraction']) {
        if(viable.single.containsKey(key)) b[key]=viable.single[key];
      }
      b['status']='line_candidate';
      b['selection_method']='observed_candidate_between_two_angle_anchors';
    }
    // Record forced paths for debugging only. Temporal uniqueness does not
    // establish shaft identity: real video can force a background edge.
    bool compatible(Map a,Map b) {
      final dt=(b['t_ms'] as int)-(a['t_ms'] as int);
      if(dt<=0||dt>100)return false;
      if(angleDistance((a['angle_deg'] as num).toDouble(),(b['angle_deg'] as num).toDouble())>45)return false;
      final length=(b['length_px'] as num).toDouble();
      if(length<=0)return false;
      final ratio=(a['length_px'] as num)/length;
      if(ratio<.5||ratio>2)return false;
      final ag=a['grip'] as Map,bg=b['grip'] as Map;
      return math.Point((ag['x'] as num).toDouble(),(ag['y'] as num).toDouble())
        .distanceTo(math.Point((bg['x'] as num).toDouble(),(bg['y'] as num).toDouble()))
        < (a['torso_length_px'] as num)*.6;
    }
    const geometryKeys=['angle_deg','score','coverage','moving_fraction',
      'length_px','grip','grip_offset_px','shaft_end',
      'extension_supported','extension_coverage','extension_samples','extension_moving_fraction'];
    // One observed candidate may join TWO original, image-extended anchors.
    // Never cascade inferred anchors or select a path across several weak frames.
    double signedTurn(double a,double b)=>(b-a+540)%360-180;
    for(var j=0;j<distinct.length-2;j++) {
      final b=distinct[j],a=distinct[j+1],c=distinct[j+2];
      if(originals[j]!='ambiguous'||originals[j+1]!='line_candidate'||
          originals[j+2]!='line_candidate'||a['extension_supported']!=true||
          c['extension_supported']!=true||b['hypotheses'] is! List)continue;
      final dt1=(a['t_ms'] as int)-(b['t_ms'] as int),dt2=(c['t_ms'] as int)-(a['t_ms'] as int);
      if(dt1<=0||dt2<=0||dt1>50||dt2>50||!compatible(a,c))continue;
      final aa=(a['angle_deg'] as num).toDouble(),cc=(c['angle_deg'] as num).toDouble();
      final turn=signedTurn(aa,cc);
      if(turn.abs()>25)continue;
      final predicted=aa-turn*dt1/dt2;
      final viable=(b['hypotheses'] as List).whereType<Map>().where((h) {
        final angle=(h['angle_deg'] as num).toDouble();
        final before=signedTurn(angle,aa);
        return angleDistance(angle,predicted)<=12&&before*turn>=0&&
          compatible({...b,for(final key in geometryKeys)if(h.containsKey(key))key:h[key]},a);
      }).toList();
      if(viable.length!=1)continue;
      b['original_status']='ambiguous';b['original_angle_deg']=b['angle_deg'];
      for(final key in geometryKeys){if(viable.single.containsKey(key))b[key]=viable.single[key];}
      b['status']='line_candidate';
      b['selection_method']='observed_candidate_before_two_extended_anchors';
      b['image_supported_track']=true;
      b['anchor_times_ms']=[a['t_ms'],c['t_ms']];
    }
    for(var start=1;start<distinct.length-1;start++) {
      if(originals[start]!='ambiguous'||originals[start-1]!='line_candidate')continue;
      var end=start;
      while(end<distinct.length&&originals[end]=='ambiguous')end++;
      if(end>=distinct.length||end-start>8||originals[end]!='line_candidate'||
          (distinct[end]['t_ms'] as int)-(distinct[start-1]['t_ms'] as int)>350)continue;
      final layers=<List<Map<String,dynamic>>>[[distinct[start-1]]];
      for(var j=start;j<end;j++) {
        final row=distinct[j];
        layers.add([for(final h in (row['hypotheses'] as List? ?? []).whereType<Map>())
          {...row,for(final key in geometryKeys)if(h.containsKey(key))key:h[key]}]);
      }
      layers.add([distinct[end]]);
      if(layers.any((l)=>l.isEmpty))continue;
      final forward=List.generate(layers.length,(_)=><int>{}),backward=List.generate(layers.length,(_)=><int>{});
      forward.first.add(0);backward.last.add(0);
      for(var j=1;j<layers.length;j++) {
        for(var k=0;k<layers[j].length;k++) {
          if(forward[j-1].any((p)=>compatible(layers[j-1][p],layers[j][k])))forward[j].add(k);
        }
      }
      if(forward.last.isEmpty)continue;
      for(var j=layers.length-2;j>=0;j--) {
        for(var k=0;k<layers[j].length;k++) {
          if(backward[j+1].any((p)=>compatible(layers[j][k],layers[j+1][p])))backward[j].add(k);
        }
      }
      for(var j=1;j<layers.length-1;j++) {
        final viable=forward[j].intersection(backward[j]);
        if(viable.length!=1)continue;
        final row=distinct[start+j-1],observed=layers[j][viable.single];
        row['tentative_path_candidate']={
          for(final key in geometryKeys)if(observed.containsKey(key))key:observed[key],
          'selection_method':'candidate_forced_by_two_original_anchors',
          'anchor_times_ms':[distinct[start-1]['t_ms'],distinct[end]['t_ms']],
          'measurement_eligible':false,
          'reason':'temporal_path_does_not_verify_shaft_identity',
        };
      }
    }
    bool linked(Map a,Map b) {
      if(a['status']!='line_candidate'||b['status']!='line_candidate')return false;
      final dt=(b['t_ms'] as int)-(a['t_ms'] as int);
      if(dt<=0||dt>100)return false;
      if(angleDistance((a['angle_deg'] as num).toDouble(),(b['angle_deg'] as num).toDouble())>45)return false;
      final ratio=(a['length_px'] as num)/(b['length_px'] as num);
      if(ratio<.5||ratio>2)return false;
      final ag=a['grip'] as Map,bg=b['grip'] as Map;
      return math.Point((ag['x'] as num).toDouble(),(ag['y'] as num).toDouble())
        .distanceTo(math.Point((bg['x'] as num).toDouble(),(bg['y'] as num).toDouble()))
        < (a['torso_length_px'] as num)*.6;
    }
    final accepted=<int>{};
    for(var i=1;i<distinct.length-1;i++) {
      if(linked(distinct[i-1],distinct[i])&&linked(distinct[i],distinct[i+1]))accepted.addAll([i-1,i,i+1]);
    }
    for(var i=0;i<distinct.length;i++) {
      distinct[i]['temporally_supported']=accepted.contains(i);
      if(distinct[i]['status']=='line_candidate')distinct[i]['reason']=accepted.contains(i)?'unverified_shaft_candidate':'isolated_or_discontinuous';
    }
  }

  /// Agreement of the full/near image searches is supporting evidence, not
  /// independent detector confirmation or a verified club identity.
  static void compareScales(Map full,Map near) {
    near['multi_scale_supported']=false;
    if(full['status']!='line_candidate'||near['status']!='line_candidate'||
        full['temporally_supported']!=true||near['temporally_supported']!=true||
        full['duplicate_frame_of_t_ms']!=null||near['duplicate_frame_of_t_ms']!=null||
        full['t_ms']!=near['t_ms']||full['width']!=near['width']||full['height']!=near['height']||
        full['coordinate_space']!='upright_image_pixels'||near['coordinate_space']!='upright_image_pixels')return;
    if(!['torso_length_px','angle_deg','length_px'].every((k)=>full[k] is num&&near[k] is num&&
      (full[k] as num).isFinite&&(near[k] as num).isFinite))return;
    final scale=(near['torso_length_px'] as num).toDouble();
    if(scale<=0||(full['length_px'] as num)<scale*.6||(near['length_px'] as num)<scale*.35||
      angleDistance((full['angle_deg'] as num).toDouble(),(near['angle_deg'] as num).toDouble())>6)return;
    if(full['grip'] is! Map||near['grip'] is! Map)return;
    final a=full['grip'] as Map,b=near['grip'] as Map;
    if(!['x','y'].every((k)=>a[k] is num&&b[k] is num&&(a[k] as num).isFinite&&(b[k] as num).isFinite))return;
    final distance=math.Point((a['x'] as num).toDouble(),(a['y'] as num).toDouble())
      .distanceTo(math.Point((b['x'] as num).toDouble(),(b['y'] as num).toDouble()));
    near['multi_scale_supported']=distance<=scale*.12;
  }

  static Future<List<Map<String,dynamic>>> analyze(Map<String,dynamic> input) async {
    final frames=(input['frames'] as List).cast<Map>();
    final samples=(input['samples'] as List).cast<Map>();
    final paths={for(final f in frames) f['t_ms']:f['path'] as String};
    img.Image? background;
    final results=<Map<String,dynamic>>[];
    final nearResults=<Map<String,dynamic>>[];
    for(final raw in samples) {
      final path=paths[raw['t_ms']];
      if(path==null)continue;
      try {
        final image=img.decodeImage(await File(path).readAsBytes());
        if(image==null)continue;
        background ??= image;
        results.add(detect(image,Map<String,dynamic>.from(raw),background:background));
        nearResults.add(detect(image,Map<String,dynamic>.from(raw),
            background:background,nearGrip:true));
      } catch (_) {
        results.add({'t_ms':raw['t_ms'],'status':'unavailable','reason':'image_decode_failed',
          'identity_verified':false,'head_detected':false});
      }
    }
    checkContinuity(results);
    checkContinuity(nearResults);
    final nearByTime={for(final c in nearResults)c['t_ms']:c};
    for(final c in results){
      final near=nearByTime[c['t_ms']];
      if(near!=null)compareScales(c,near);
      c['near_grip_candidate']=near;
    }
    return results;
  }
}
