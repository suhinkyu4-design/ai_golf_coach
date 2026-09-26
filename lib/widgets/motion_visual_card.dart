import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/swing_fault_features.dart';
import 'correction_guide_card.dart';

class MotionVisualCard extends StatefulWidget {
  final String videoPath, leadSide;
  final Map report;
  const MotionVisualCard({super.key, required this.videoPath, required this.report, required this.leadSide});
  @override
  State<MotionVisualCard> createState() => _MotionVisualCardState();
}
class _MotionVisualCardState extends State<MotionVisualCard> {
  static const channel = MethodChannel('com.metaoffice.aigolfcoatch/frame_extractor');
  static const kinds = {'head_trail_check':'스웨이','early_extension_check':'배치기','standing_up_check':'상체 들림','chicken_wing_check':'치킨윙','head_up_check':'헤드업'};
  String selected = 'head_trail_check';
  String? imagePath, error;
  FrameGeometry? baseline, observed;
  bool showAddress = false;
  int generation = 0;
  final owned = <String>{};
  Map get rules => widget.report['fault_features'] as Map? ?? {};
  Map get rule => rules[selected] as Map? ?? {};
  @override void initState() { super.initState(); _selectInitial(); _load(); }
  @override void didUpdateWidget(covariant MotionVisualCard old) {
    super.didUpdateWidget(old);
    if(old.videoPath != widget.videoPath || !identical(old.report,widget.report)) { _selectInitial(); _load(); }
  }
  void _selectInitial() {
    final available=kinds.keys.where((k)=>(rules[k] as Map?)?['status']=='rule_classified').toList();
    selected=available.firstWhere((k)=> !['within_rule','warning'].contains(rules[k]['grade']),
      orElse:()=>available.firstWhere((k)=>rules[k]['grade']=='warning',orElse:()=>available.isEmpty?kinds.keys.first:available.first));
  }
  Future<void> _delete(String path) async { try { await File(path).delete(); } catch (_) {} }
  Future<void> _load() async {
    final token=++generation;
    setState(() {imagePath=null; error=null; baseline=null; observed=null;});
    final acquired=<String>[];
    try {
      final evidence=widget.report['motion_evidence'] as Map?;
      final reviewed=evidence?['reviewed'] as Map?;
      final a=reviewed?[selected=='chicken_wing_check'?'impact':'address'];
      final t=rule['t_ms'];
      if(rule['status']!='rule_classified' || a is! Map || t is! int) throw StateError('이 동작의 비교 위치를 측정하지 못했습니다. 정상 판정이 아닙니다.');
      final frames=<Map>[...?(reviewed?.values.whereType<Map>()), ...?((evidence?['samples'] as List?)?.whereType<Map>())];
      final targets=frames.where((r)=>r['t_ms']==t && FrameGeometry.read(r)!=null);
      if(targets.isEmpty) throw StateError('판정 시점과 일치하는 관절 기록이 없습니다.');
      final base=FrameGeometry.read(a), target=FrameGeometry.read(targets.first);
      if(base==null || target==null || base.w!=target.w || base.h!=target.h) throw StateError('영상 좌표를 맞출 수 없어 비교선을 표시하지 않습니다.');
      final at=showAddress?base:target;
      final extracted=await channel.invokeMethod<List<dynamic>>('extractFrames',{'videoPath':widget.videoPath,'startMs':at.t,'endMs':at.t,'sampleCount':2});
      for(final row in extracted??[]) { if(row is Map && row['path'] is String) acquired.add(row['path'] as String); }
      if(extracted==null || extracted.isEmpty) throw StateError('영상 장면을 불러오지 못했습니다.');
      final frame=extracted.first as Map;
      if(frame['width']!=at.w || frame['height']!=at.h) throw StateError('영상 크기가 관절 좌표와 달라 비교선을 표시하지 않습니다.');
      if(!mounted || token!=generation)return;
      owned.addAll(acquired);
      setState(() {baseline=base;observed=target;imagePath=frame['path'] as String;});
    } catch(e) { if(mounted&&token==generation)setState(()=>error=e is StateError?e.message.toString():'비교 장면을 불러오지 못했습니다.'); }
    finally {
      for(final p in acquired) {if(!mounted||token!=generation)await _delete(p);}
      if(mounted&&token==generation) {final stale=owned.where((p)=>p!=imagePath).toList();owned.removeAll(stale);for(final p in stale){await _delete(p);}}
    }
  }
  @override void dispose(){generation++;for(final p in owned){_delete(p);}super.dispose();}
  @override Widget build(BuildContext context) {
    final c=Theme.of(context).colorScheme;
    final ready=rule['status']=='rule_classified';
    final normal=ready&&rule['grade']=='within_rule';
    final color=!ready?c.onSurfaceVariant:normal?c.primary:Theme.of(context).brightness==Brightness.dark?Colors.amber:const Color(0xFF9A4600);
    final explanation=selected=='head_trail_check'?'어드레스와 백스윙 탑의 머리 위치를 비교합니다.':selected=='early_extension_check'?'어드레스와 임팩트의 골반 중심 위치를 비교합니다. 엉덩이 외곽선은 아닙니다.':selected=='standing_up_check'?'어드레스와 관찰 시점의 상체 기울기를 비교합니다.':selected=='chicken_wing_check'?'관찰 시점의 리드 팔꿈치 굽힘을 확인해 보세요.':'어드레스와 관찰 시점의 머리 높이를 비교합니다.';
    return Card(child: Padding(padding:const EdgeInsets.all(16),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
      Text('내 동작 한눈에 보기',style:Theme.of(context).textTheme.titleLarge),const SizedBox(height:12),
      Wrap(spacing:6,runSpacing:4,children:[for(final e in kinds.entries) ChoiceChip(label:Text(e.value),selected:selected==e.key,
        labelStyle:TextStyle(color:selected==e.key?c.onPrimary:c.onSurface),selectedColor:c.primary,
        checkmarkColor:c.onPrimary,onSelected:(_){selected=e.key;showAddress=false;_load();})]),
      const SizedBox(height:12),Text(ready?(rule['label'] as String? ?? kinds[selected]!):'${kinds[selected]} · 측정 불가',style:Theme.of(context).textTheme.titleMedium?.copyWith(color:color)),
      const SizedBox(height:8),Text(explanation),const SizedBox(height:12),
      if(error!=null) Padding(padding:const EdgeInsets.symmetric(vertical:24),child:Text(error!))
      else if(imagePath==null) const SizedBox(height:180,child:Center(child:CircularProgressIndicator()))
      else ...[
        Row(children:[Expanded(child:TextButton(onPressed:(){showAddress=true;_load();},child:Text(showAddress?'● ${selected=='chicken_wing_check'?'임팩트':'어드레스'}':selected=='chicken_wing_check'?'임팩트':'어드레스'))),
          Expanded(child:TextButton(onPressed:(){showAddress=false;_load();},child:Text(!showAddress?'● 관찰 시점':'관찰 시점')))]),
        LayoutBuilder(builder: (context, constraints) => SizedBox(height:math.min(340.0, constraints.maxWidth*baseline!.h/baseline!.w),child:Center(child:AspectRatio(aspectRatio:baseline!.w/baseline!.h,
          child:ClipRRect(borderRadius:BorderRadius.circular(12),child:Stack(fit:StackFit.expand,children:[
            Image.file(File(imagePath!),fit:BoxFit.fill,errorBuilder:(_,__,___)=>const Center(child:Text('장면을 열지 못했습니다.'))),
            CustomPaint(painter:_MotionPainter(baseline!,observed!,selected,widget.leadSide,showAddress)),
          ])))))),
        const SizedBox(height:8),Text('흰 점선: ${selected=='chicken_wing_check'?'임팩트':'어드레스'} · 주황 실선: 관찰 위치',style:Theme.of(context).textTheme.bodySmall),
        Text('${((showAddress?baseline!.t:observed!.t)/1000).toStringAsFixed(3)}초 · 영상 좌표 기준',style:Theme.of(context).textTheme.bodySmall),
      ],
      CorrectionGuideCard(kind:selected,rule:rule,leftHanded:widget.leadSide=='right'),
    ])));
  }
}
class _MotionPainter extends CustomPainter {
  final FrameGeometry base, target;
  final String kind, lead;
  final bool address;
  _MotionPainter(this.base,this.target,this.kind,this.lead,this.address);
  @override void paint(Canvas canvas,Size size) {
    Offset? point(math.Point<double>? p)=>p==null?null:Offset(p.x/base.w*size.width,p.y/base.h*size.height);
    final ref=Paint()..color=Colors.white..strokeWidth=2.5..style=PaintingStyle.stroke;
    final mark=Paint()..color=const Color(0xFFFFB44C)..strokeWidth=3..style=PaintingStyle.stroke;
    void line(Offset? a,Offset? b,Paint paint,{bool dashed=false}) {if(a==null||b==null)return;if(!dashed){canvas.drawLine(a,b,Paint()..color=Colors.black54..strokeWidth=5);canvas.drawLine(a,b,paint);return;}final d=(b-a).distance;if(d<.1)return;for(double i=0;i<d;i+=10){canvas.drawLine(a+(b-a)*(i/d),a+(b-a)*(math.min(i+5,d)/d),paint);}}
    if(kind=='head_trail_check'||kind=='head_up_check'||kind=='early_extension_check') {
      final hip=kind=='early_extension_check';
      final a=point(hip?base.hip:base.midpoint('leftEye','rightEye'));
      final b=point(hip?target.hip:target.midpoint('leftEye','rightEye'));
      if(a==null||b==null)return;
      for(var i=0;i<12;i++)canvas.drawArc(Rect.fromCircle(center:a,radius:12),i*math.pi/6,math.pi/12,false,ref);
      if(hip)line(Offset(a.dx,math.max(0,a.dy-55)),Offset(a.dx,math.min(size.height,a.dy+55)),ref,dashed:true);
      if(!address){canvas.drawCircle(b,10,mark);line(a,b,mark);final v=b-a;if(v.distance>8){final u=v/v.distance;final n=Offset(-u.dy,u.dx);line(b,b-u*9+n*5,mark);line(b,b-u*9-n*5,mark);}}
    } else if(kind=='standing_up_check') {
      line(point(base.hip),point(base.shoulder),ref,dashed:true);
      if(!address)line(point(target.hip),point(target.shoulder),mark);
    } else {
      void arm(FrameGeometry f,Paint p,bool dashed){final a=point(f.joint('${lead}Shoulder')),b=point(f.joint('${lead}Elbow')),c=point(f.joint('${lead}Wrist'));line(a,b,p,dashed:dashed);line(b,c,p,dashed:dashed);if(b!=null&&!dashed)canvas.drawCircle(b,9,p);}
      arm(base,ref,true);if(!address)arm(target,mark,false);
    }
  }
  @override bool shouldRepaint(covariant _MotionPainter old)=>true;
}
