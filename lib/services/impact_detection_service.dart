import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:image/image.dart' as img;

class ImpactDetectionResult {
  final int tMs;
  final double confidence, ballX, ballY;
  final String method;
  final List<int> candidateTimesMs;
  final int? intervalStartMs, intervalEndMs;
  final double? clubX, clubY, clubBallDistance;
  const ImpactDetectionResult({required this.tMs, required this.confidence,
    required this.ballX, required this.ballY, required this.method,
    required this.candidateTimesMs, this.intervalStartMs, this.intervalEndMs,
    this.clubX, this.clubY, this.clubBallDistance});
  Map<String, dynamic> toJson() => {
    't_ms': tMs, 'confidence': confidence, 'ball_x': ballX, 'ball_y': ballY,
    'method': method, 'candidate_times_ms': candidateTimesMs,
    'interval_start_ms': intervalStartMs, 'interval_end_ms': intervalEndMs,
    'club_x': clubX, 'club_y': clubY, 'club_ball_distance_px': clubBallDistance,
  };
}

class ImpactDetectionService {
  static const debugVersion = 'impact-debug-v4';

  // Coarse joints locate a search window only; they do not gate impact height.
  static Map<String, int>? scanWindow(List<Map<String, dynamic>> samples) {
    final windows=scanWindows(samples);
    return windows.isEmpty ? null : windows.first;
  }

  static List<Map<String,int>> scanWindows(List<Map<String,dynamic>> samples) {
    final usable = samples.where((s) => _joint(s, const {'leftWrist', 'rightWrist'}) != null)
      .toList()..sort((a,b) => (a['t_ms'] as int).compareTo(b['t_ms'] as int));
    if (usable.length < 5) return [];
    final ys = usable.map((s) => _joint(s, const {'leftWrist', 'rightWrist'})!.y).toList();
    final smooth = List.generate(ys.length, (i) {
      final from = math.max(0, i - 1), to = math.min(ys.length - 1, i + 1);
      return ys.sublist(from, to + 1).reduce((a,b) => a+b) / (to-from+1);
    });
    bool handsTogether(Map<String,dynamic> row) {
      final left=_joint(row, const {'leftWrist'}),right=_joint(row,const {'rightWrist'});
      final shoulder=_joint(row,const {'leftShoulder','rightShoulder'});
      final hip=_joint(row,const {'leftHip','rightHip'});
      // With both hands visible, reject single-hand gestures before the swing.
      if(left==null||right==null||shoulder==null||hip==null)return true;
      final torso=math.sqrt(math.pow(shoulder.x-hip.x,2)+math.pow(shoulder.y-hip.y,2));
      return torso>0 && math.sqrt(math.pow(left.x-right.x,2)+math.pow(left.y-right.y,2))<=torso*.55;
    }
    final windows=<Map<String,int>>[];
    int addressFloor=0;
    double? previousAddressY;
    // Search locally before each reversal so long preparation does not become address.
    for (int top=1; top<usable.length-1; top++) {
      if(!handsTogether(usable[top]))continue;
      int? localAddress;
      for(int i=top-1;i>=addressFloor;i--) {
        if((usable[top]['t_ms'] as int)-(usable[i]['t_ms'] as int)>3000)break;
        if(!handsTogether(usable[i]))continue;
        if(localAddress==null||smooth[i]>smooth[localAddress])localAddress=i;
      }
      if(localAddress==null)continue;
      final address=localAddress;
      final height=(usable[address]['height'] as num).toDouble();
      final amplitude=smooth[address]-smooth[top];
      // Re-arm only after hands return near address height; a high finish is
      // not another backswing. Separate cycles cannot reuse the old address.
      if(previousAddressY!=null) {
        if(smooth[address]<previousAddressY-height*.08)continue;
        // Re-arm after a fresh address dwell, not the brief low-hand impact.
        int? dwellStart;
        int? previousTime;
        bool reset=false;
        for(var i=addressFloor;i<top;i++) {
          final time=usable[i]['t_ms'] as int;
          if(ys[i]<previousAddressY-height*.08 || !handsTogether(usable[i])) {
            dwellStart=null;previousTime=null;continue;
          }
          if(previousTime!=null && time-previousTime>300)dwellStart=null;
          dwellStart ??= time;
          previousTime=time;
          if(time-dwellStart>=200){reset=true;break;}
        }
        if(!reset)continue;
      }
      if(amplitude<height*.06 || smooth[top]>smooth[top-1] ||
          smooth[top]>=smooth[top+1]) continue;
      final topMs=usable[top]['t_ms'] as int;
      // Sub-400 ms address-to-top cycles in phone video are usually a hand
      // gesture, frame jitter, or a fragment at the beginning of the clip.
      if(topMs-(usable[address]['t_ms'] as int)<400) continue;
      for(int j=top+1;j<usable.length;j++) {
        final returnMs=usable[j]['t_ms'] as int;
        if(returnMs-topMs>1000) break;
        if(ys[j]<smooth[top]+amplitude*.65) continue;
        windows.add({'address_ms':usable[address]['t_ms'] as int,'top_ms':topMs,
          'return_ms':returnMs,'start_ms':math.max(0,topMs-100),
          'end_ms':math.min(usable.last['t_ms'] as int,returnMs+350)});
        previousAddressY=smooth[address];
        addressFloor=j+1;
        top=j;
        break;
      }
    }
    // A short pre-shot hand movement can resemble a complete swing after dense
    // refinement.  Only discard it when another complete, longer motion exists;
    // this keeps a genuinely fast single swing measurable.
    if (windows.length > 1) {
      final complete = windows.where((window) =>
        window['return_ms']! - window['address_ms']! >= 700).toList();
      if (complete.isNotEmpty) return complete;
    }
    return windows;
  }

  /// Select only unique visual hit evidence across cycles. Scores are not
  /// calibrated probabilities and must not rank two competing hit candidates.
  static Map<String,dynamic> selectSwing(List<Map<String,int>> windows,
      List<Map<String,dynamic>> reports) {
    final hits=<int>[for(var i=0;i<reports.length;i++)if(reports[i]['result']!=null)i];
    final index=hits.length==1 ? hits.single : (hits.isEmpty&&windows.length==1 ? 0 : null);
    final selected=index==null ? null : windows[index];
    final report=index==null ? null : reports[index];
    return {'result':hits.length==1 ? report!['result'] : null,
      'diagnostics':<String,dynamic>{
        if(report!=null)...Map<String,dynamic>.from(report['diagnostics'] as Map),
        'version':debugVersion,'swing_candidate_count':windows.length,
        'selected_window':selected,'selection_basis':hits.length==1 ? 'unique_visual_hit' :
          (index!=null ? 'single_swing_pose_fallback' : 'ambiguous_multiple_swings'),
        if(index==null)'status':'no_candidate',
        if(index==null)'reason':hits.length>1 ? 'multiple_visual_hits' : 'no_unique_hit_among_swings',
        'swing_candidates':[for(var i=0;i<windows.length;i++){
          ...windows[i],'visual_hit':reports[i]['result']!=null,
          'diagnostics':reports[i]['diagnostics']}],
      }};
  }

  static Future<Map<String, dynamic>> analyzeWithDiagnostics({
    required List<Map<String, dynamic>> frames,
    required List<Map<String, dynamic>> samples,
    Map<String,int>? window,
  }) async {
    final debug=<String,dynamic>{'version':debugVersion,'status':'running',
      'frame_count':frames.length,'sample_count':samples.length,
      'ball_detector':'compact_neutral_component_with_temporal_tracking',
      'club_head_detector':'moving_elongated_club_trace_candidate',
      'club_identity_verified':false, 'confidence_is_calibrated':false,
      'timestamp_note':'requested closest-frame times; actual decoded PTS unavailable',
      'selection_rule':'after_top_and_ball_departure_and_nearest_visible_club_trace'};
    final timer=Stopwatch()..start();
    ImpactDetectionResult? result;
    try { result=await detectImpact(frames:frames,samples:samples,diagnostics:debug,window:window); }
    catch(e,stack) { debug.addAll({'status':'error','reason':'exception','error':'$e','stack':'$stack'}); }
    debug['elapsed_ms']=timer.elapsedMilliseconds;
    return {'result':result?.toJson(),'diagnostics':debug};
  }

  static Future<ImpactDetectionResult?> detectImpact({
    required List<Map<String,dynamic>> frames,
    required List<Map<String,dynamic>> samples,
    Map<String,dynamic>? diagnostics,
    Map<String,int>? window,
  }) async {
    final debug=diagnostics ?? <String,dynamic>{};
    ImpactDetectionResult? reject(String reason) {
      debug.addAll({'status':'no_candidate','reason':reason}); return null;
    }
    if(frames.length<5 || samples.length<5) return reject('insufficient_frames');
    window ??= scanWindow(samples);
    if(window==null) return reject('insufficient_pose_or_invalid_top');
    debug.addAll(window);
    final topMs=window['top_ms']!;
    final ordered=List<Map<String,dynamic>>.from(frames)
      ..sort((a,b)=>(a['t_ms'] as int).compareTo(b['t_ms'] as int));
    final startMs=window['start_ms']!,endMs=window['end_ms']!;
    final scan=ordered.where((f)=>(f['t_ms'] as int)>=startMs &&
      (f['t_ms'] as int)<=endMs).toList();
    if(scan.length<5) return reject('insufficient_impact_frames');
    debug['frame_times_ms']=scan.map((f)=>f['t_ms']).toList();
    final gaps=List.generate(scan.length-1,(i)=>(scan[i+1]['t_ms'] as int)-(scan[i]['t_ms'] as int));
    debug['sample_gaps_ms']=gaps;
    // Reject coarse scans rather than pretend a subframe estimate is measured.
    if(gaps.reduce(math.max)>85) return reject('dense_frames_required');
    final referenceSample=samples.reduce((a,b)=>
      ((a['t_ms'] as int)-topMs).abs()<((b['t_ms'] as int)-topMs).abs()?a:b);
    final ankle=_joint(referenceSample,const {'leftAnkle','rightAnkle'});
    if(ankle==null) return reject('ankles_unavailable_for_ball_search');
    Future<img.Image> read(Map<String,dynamic> f) async {
      final decoded=img.decodeImage(await File(f['path'] as String).readAsBytes());
      if(decoded==null) throw const FormatException('Frame image decode failed');
      return decoded.height>640 ? img.copyResize(decoded,height:640) : decoded;
    }
    var reference=await read(scan.first);
    final w=reference.width,h=reference.height;
    final scaleX=w/(referenceSample['width'] as num), scaleY=h/(referenceSample['height'] as num);
    final ax=ankle.x*scaleX,ay=ankle.y*scaleY;
    final roi=_Region((ax-w*.65).round(),(ay-h*.025).round(),
      (ax+w*.65).round(),(ay+h*.08).round()).bounded(w,h);
    debug['ball_search_roi']=roi.json;
    final confirm=await read(scan[1]);
    if(confirm.width!=w || confirm.height!=h) return reject('inconsistent_frame_dimensions');
    // Retry with a brighter core if mat highlights merge with the white ball.
    // Keep the selected threshold fixed throughout this track.
    final stable=<_Ball>[];
    final candidateThresholds=<_Ball,double>{};
    for(final threshold in [0.0,175.0]) {
      final initial=_balls(reference,roi,minLuminance:threshold)
        .where((b)=>_distance(b.x,b.y,ax,ay)>w*.055).toList();
      final nextBalls=_balls(confirm,roi,minLuminance:threshold);
      final matched=initial.where((b)=>nextBalls.any((n)=>
        _distance(b.x,b.y,n.x,n.y)<w*.02));
      for(final b in matched) {
        if(stable.any((s)=>_distance(s.x,s.y,b.x,b.y)<=math.max(2.0,math.min(s.radius,b.radius))))continue;
        stable.add(b);candidateThresholds[b]=threshold;
      }
    }
    stable.sort((a,b)=>b.score.compareTo(a.score));
    debug['ball_thresholds_tested']=[0,175];
    debug['ball_candidates']=stable.take(12).map((b)=>b.json).toList();
    if(stable.isEmpty) return reject('no_stable_ball_candidate');
    // Decode once per window; cap resolution to bound memory while comparing
    // all compact bright candidates rather than trusting the top shape score.
    final decodedFrames=<img.Image>[reference,confirm];
    for(var i=2;i<scan.length;i++)decodedFrames.add(await read(scan[i]));
    Future<ImpactDetectionResult?> track(_Ball seed,Map<String,dynamic> debug) async {
      final minLuminance=candidateThresholds[seed]!;
      debug['ball_min_luminance']=minLuminance;
      ImpactDetectionResult? reject(String reason) {
        debug.addAll({'status':'no_candidate','reason':reason});return null;
      }

    var bx=seed.x,by=seed.y;
    debug['ball_candidate']={...seed.json,'width':w,'height':h,'roi':roi.json,
      'verified_ball':false,'reference':'pre_downswing_tracked_ball'};
    debug['ball_reference_ms']=scan.first['t_ms'];
    final rows=<Map<String,dynamic>>[];
    debug['candidates']=rows;
    int stableCount=0,missingCount=0;
    int? departureIndex;
    for(int i=0;i<scan.length;i++) {
      final f=scan[i];
      final current=i==0?reference:(i==1?confirm:decodedFrames[i]);
      if(current.width!=w || current.height!=h) return reject('inconsistent_frame_dimensions');
      final tracked=_balls(current,_Region((bx-w*.02).round(),(by-h*.012).round(),
        (bx+w*.02).round(),(by+h*.012).round()).bounded(w,h),minLuminance:minLuminance)
        ..sort((a,b)=>_distance(a.x,a.y,bx,by).compareTo(_distance(b.x,b.y,bx,by)));
      final displacement=tracked.isEmpty?null:_distance(tracked.first.x,tracked.first.y,bx,by);
      // Do not switch the stationary ball track to a passing white club/reflection.
      final present=tracked.isNotEmpty && displacement!<=math.max(4.0,seed.radius*1.2);
      if(present) {
        bx=tracked.first.x;by=tracked.first.y;
        stableCount++;missingCount=0;
      } else { missingCount++; }
      final row=<String,dynamic>{'index':i,'t_ms':f['t_ms'], 'after_top':(f['t_ms'] as int)>topMs,
        'ball_present':present,'tracked_component_displacement_px':displacement,'ball_x':bx,'ball_y':by,'ball_missing_streak':missingCount,
        'club_candidate':null,'club_ball_distance_px':null,
        'rejected':(f['t_ms'] as int)<=topMs?'before_or_at_top':null};
      rows.add(row);
      if(departureIndex==null && missingCount==2 && stableCount>=3 && (f['t_ms'] as int)>topMs) {
        departureIndex=i-1;
      }
    }
    if(departureIndex==null) return reject('ball_departure_not_confirmed');
    final departure=departureIndex;
    if(rows.skip(departure).any((r)=>r['ball_present']==true))return reject('ball_reappeared_after_occlusion');
    if((rows.last['t_ms'] as int)-(rows[departure]['t_ms'] as int)<100)return reject('ball_departure_followup_too_short');
    final before=math.max(0,departure-1);
    debug.addAll({'departure_index':departure,'last_ball_present_ms':rows[before]['t_ms'],
      'first_ball_absent_ms':rows[departure]['t_ms']});
    // Only test club imagery once a sustained departure exists. Static
    // distractors need no expensive club scan on every frame of every track.
    for(var i=before;i<=departure;i++) {
      if(i==0)continue;
      final row=rows[i];
      final trace=_clubTrace(decodedFrames[i],decodedFrames[i-1],
        (row['ball_x'] as num).toDouble(),(row['ball_y'] as num).toDouble(),seed.radius);
      row['club_candidate']=trace;
      row['club_ball_distance_px']=trace?['distance_px'];
    }
    // The image can show a blurred shaft/head; expose the nearest visible trace point,
    // never label it as a verified club-head center.
    final eligible=rows.sublist(before,math.min(rows.length,departure+1)).where((r)=>
      r['after_top']==true && r['club_candidate']!=null &&
      (r['club_ball_distance_px'] as num)<=math.max(18.0,seed.radius*4)).toList()
      ..sort((a,b)=>(a['club_ball_distance_px'] as num).compareTo(b['club_ball_distance_px'] as num));
    if(eligible.isEmpty) return reject('ball_departure_without_nearby_club_trace');
    final best=eligible.first,trace=best['club_candidate'] as Map<String,dynamic>;
    final selected=best['t_ms'] as int;
    final confidence=(.55+.25*(1-(best['club_ball_distance_px'] as num)/math.max(18,seed.radius*4)))
      .clamp(0.0,.8).toDouble();
    debug.addAll({'status':'selected','reason':'ball_departure_with_nearest_club_trace',
      'selected_ms':selected,'selected_index':best['index'],'reported_confidence':confidence,
      'club_ball_distance_px':best['club_ball_distance_px'], 'club_candidate':trace,
      'interval_start_ms':rows[before]['t_ms'],'interval_end_ms':rows[departure]['t_ms']});
    return ImpactDetectionResult(tMs:selected,confidence:confidence,ballX:(best['ball_x'] as num).toDouble(),ballY:(best['ball_y'] as num).toDouble(),
      method:'tracked_ball_departure_and_club_trace',candidateTimesMs:eligible.map((r)=>r['t_ms'] as int).toList(),
      intervalStartMs:rows[before]['t_ms'] as int,intervalEndMs:rows[departure]['t_ms'] as int,
      clubX:(trace['x'] as num).toDouble(),clubY:(trace['y'] as num).toDouble(),
      clubBallDistance:(best['club_ball_distance_px'] as num).toDouble());
    }
    final tracks=<Map<String,dynamic>>[];
    final hits=<ImpactDetectionResult>[];
    final hitDiagnostics=<Map<String,dynamic>>[];
    for(final seed in stable.take(12)) {
      final diagnostics=<String,dynamic>{};
      final hit=await track(seed,diagnostics);
      tracks.add(diagnostics);
      if(hit!=null){hits.add(hit);hitDiagnostics.add(diagnostics);}
    }
    debug['ball_tracks']=tracks;
    if(hits.length==1){debug.addAll(hitDiagnostics.single);return hits.single;}
    if(hits.length>1)return reject('multiple_ball_departure_candidates');
    if(tracks.length==1){debug.addAll(tracks.single);return null;}
    return reject('no_unique_ball_departure_with_club_trace');
  }

  static math.Point<double>? _joint(Map<String,dynamic> sample,Set<String> names) {
    double x=0,y=0;int n=0;
    for(final l in sample['landmarks'] as List? ?? const []) {
      if(l is! Map || !names.contains(l['name'])) continue;
      final xx=l['x'],yy=l['y'],likelihood=l['likelihood'];
      if(xx is! num || yy is! num || !xx.isFinite || !yy.isFinite ||
        (likelihood is num && likelihood<.5)) continue;
      x+=xx;y+=yy;n++;
    }
    return n==0?null:math.Point(x/n,y/n);
  }

  static double _distance(double x,double y,double xx,double yy)=>math.sqrt((x-xx)*(x-xx)+(y-yy)*(y-yy));
  static double _bright(img.Pixel p)=>.299*p.r+.587*p.g+.114*p.b;
  static bool _neutral(img.Pixel p,double minimum,double saturation) {
    final hi=math.max(p.r,math.max(p.g,p.b)).toDouble(),lo=math.min(p.r,math.min(p.g,p.b));
    return hi>minimum && (hi-lo)/(hi+1)<saturation;
  }

  static List<_Ball> _balls(img.Image im,_Region roi,{double minLuminance=0}) {
    // Luminance separates the white ball core from warm mat highlights;
    // a max-channel threshold joins the ball to the mat in brighter footage.
    final blobs=_components(roi,(x,y)=>_neutral(im.getPixel(x,y),150,.38) &&
      _bright(im.getPixel(x,y))>minLuminance);
    final result=<_Ball>[];
    final maxDiameter=math.max(8,(im.width*.026).round());
    for(final blob in blobs) {
      final bw=blob.maxX-blob.minX+1,bh=blob.maxY-blob.minY+1;
      final fill=blob.points.length/(bw*bh);
      if(bw<3 || bh<3 || bw>maxDiameter || bh>maxDiameter || fill<.5 || bw/bh<.55 || bw/bh>1.8) continue;
      final x=blob.sumX/blob.points.length,y=blob.sumY/blob.points.length;
      double inside=0,ring=0;int count=0;
      for(final p in blob.points) { inside+=_bright(im.getPixel(p%im.width,p~/im.width)); }
      inside/=blob.points.length;
      for(int yy=math.max(0,blob.minY-3);yy<=math.min(im.height-1,blob.maxY+3);yy++) {
        for(int xx=math.max(0,blob.minX-3);xx<=math.min(im.width-1,blob.maxX+3);xx++) {
          if(xx>=blob.minX && xx<=blob.maxX && yy>=blob.minY && yy<=blob.maxY) continue;
          ring+=_bright(im.getPixel(xx,yy));count++;
        }
      }
      final contrast=inside-(count==0?inside:ring/count);
      if(contrast<22) continue;
      final roundness=math.min(bw,bh)/math.max(bw,bh);
      final score=fill*2+roundness*1.5+inside/255+contrast/128;
      result.add(_Ball(x,y,math.max(bw,bh)/2,score));
    }
    return result;
  }

  static Map<String,dynamic>? _clubTrace(img.Image im,img.Image prev,double bx,double by,double radius) {
    final roi=_Region((bx-im.width*.25).round(),(by-im.height*.19).round(),
      (bx+im.width*.20).round(),(by+im.height*.06).round()).bounded(im.width,im.height);
    final blobs=_components(roi,(x,y) {
      final p=im.getPixel(x,y),q=prev.getPixel(x,y);
      return _neutral(p,65,.50) && math.max((p.r-q.r).abs(),math.max((p.g-q.g).abs(),(p.b-q.b).abs()))>18;
    });
    Map<String,dynamic>? best;
    for(final b in blobs) {
      final n=b.points.length;if(n<10) continue;
      final xx=b.sumXX/n-math.pow(b.sumX/n,2),yy=b.sumYY/n-math.pow(b.sumY/n,2),xy=b.sumXY/n-b.sumX*b.sumY/(n*n);
      final delta=math.sqrt((xx-yy)*(xx-yy)+4*xy*xy);
      final major=(xx+yy+delta)/2,minor=math.max(1.0,(xx+yy-delta)/2);
      final length=math.sqrt(math.max(0,major))*3.46,elongation=major/minor;
      // Permit a moderately widened impact blur while retaining motion, length,
      // vertical extent and sustained ball-departure requirements.
      if(length<im.height*.027 || elongation<2.5 || b.maxY-b.minY<im.height*.02) continue;
      var distance=double.infinity;double cx=0,cy=0;
      for(final point in b.points) {
        final x=(point%im.width).toDouble(),y=(point~/im.width).toDouble();
        final d=_distance(x,y,bx,by);
        if(d<distance) {distance=d;cx=x;cy=y;}
      }
      if(best==null || distance<(best['distance_px'] as num)) {
        best={'x':cx,'y':cy,'distance_px':distance,'length_px':length,'elongation':elongation,
          'pixel_count':n,'head_center_verified':false,'kind':'nearest_moving_elongated_trace_point'};
      }
    }
    return best;
  }

  // 8-connected components. Pixel indexes use full-image stride supplied by region.
  static List<_Blob> _components(_Region roi,bool Function(int,int) isOn) {
    final rw=roi.right-roi.left+1,rh=roi.bottom-roi.top+1;
    if(rw<=0 || rh<=0) return [];
    final mask=Uint8List(rw*rh);
    for(int y=0;y<rh;y++) {for(int x=0;x<rw;x++) {if(isOn(x+roi.left,y+roi.top)) mask[y*rw+x]=1;}}
    final blobs=<_Blob>[];
    for(int i=0;i<mask.length;i++) {
      if(mask[i]!=1) continue;
      final stack=<int>[i];mask[i]=0;final b=_Blob();
      while(stack.isNotEmpty) {
        final p=stack.removeLast(),x=p%rw,y=p~/rw;
        b.add(x+roi.left,y+roi.top,roi.stride);
        for(int dy=-1;dy<=1;dy++) {for(int dx=-1;dx<=1;dx++) {
          final nx=x+dx,ny=y+dy;if(nx<0||nx>=rw||ny<0||ny>=rh) continue;
          final ni=ny*rw+nx;if(mask[ni]==1) {mask[ni]=0;stack.add(ni);}
        }}
      }
      blobs.add(b);
    }
    return blobs;
  }
}

class _Region {
  final int left,top,right,bottom,stride;
  _Region(this.left,this.top,this.right,this.bottom,[this.stride=0]);
  _Region bounded(int w,int h)=>_Region(left.clamp(0,w-1),top.clamp(0,h-1),right.clamp(0,w-1),bottom.clamp(0,h-1),w);
  Map<String,int> get json=>{'x_min':left,'x_max':right,'y_min':top,'y_max':bottom};
}
class _Ball {
  final double x,y,radius,score;
  _Ball(this.x,this.y,this.radius,this.score);
  Map<String,dynamic> get json=>{'x':x,'y':y,'radius':radius,'score':score};
}
class _Blob {
  final points=<int>[];
  int minX=1<<30,minY=1<<30,maxX=0,maxY=0;
  double sumX=0,sumY=0,sumXX=0,sumYY=0,sumXY=0;
  void add(int x,int y,int stride) {
    points.add(y*stride+x);minX=math.min(minX,x);maxX=math.max(maxX,x);
    minY=math.min(minY,y);maxY=math.max(maxY,y);
    sumX+=x;sumY+=y;sumXX+=x*x;sumYY+=y*y;sumXY+=x*y;
  }
}
