import '../widgets/coach_app_bar.dart';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../providers/swing_provider.dart';

class OverTopReviewScreen extends StatefulWidget {
  const OverTopReviewScreen({super.key});
  @override
  State<OverTopReviewScreen> createState()=>_OverTopReviewScreenState();
}
class _OverTopReviewScreenState extends State<OverTopReviewScreen> {
  static const channel=MethodChannel('com.metaoffice.aigolfcoatch/frame_extractor');
  List<Map> _pairs=[];
  String _source='full_ray';
  bool _slot=false;
  String? _reason;
  final _owned=<String>{};
  String? _video,_error;
  List<String> _images=[];
  int _index=0,_generation=0;
  @override
  void initState(){
    super.initState();
    final provider=context.read<SwingProvider>();
    _video=provider.currentSwing?.videoPath;
    _reason=provider.currentPoseReport?['fault_features']?['over_the_top_check']?['reason'] as String?;
    _source=provider.currentPoseReport?['fault_features']?['over_the_top_check']?['comparison_source'] as String? ?? 'full_ray';
    final report=provider.currentPoseReport?['fault_features']?['over_the_top_check'];
    _slot=(report?['slot_pairs'] as List? ?? []).isNotEmpty;
    _pairs=[for(final p in report?[_slot?'slot_pairs':'pairs'] as List? ?? [])
      if(p is Map && p['backswing'] is Map && p['downswing'] is Map)p];
    if(_pairs.isNotEmpty)_load(0);
  }
  Future<void> _delete(String path)async{try{await File(path).delete();}catch(_){} }
  Future<void> _load(int index)async{
    final generation=++_generation;
    setState((){_index=index;_images=[];_error=null;});
    final acquired=<String>[],images=<String>[];
    try{
      for(final key in ['backswing','downswing']){
        final row=_pairs[index][key] as Map;
        final frames=await channel.invokeMethod<List<dynamic>>('extractFrames',{
          'videoPath':_video,'startMs':row['t_ms'],'endMs':row['t_ms'],'sampleCount':2});
        for(final f in frames??[]){acquired.add(f['path'] as String);}
        if(frames==null||frames.isEmpty)throw StateError('missing frame');
        final frame=frames.first as Map;
        if(frame['width']!=row['width']||frame['height']!=row['height'])throw StateError('coordinate mismatch');
        images.add(frame['path'] as String);
      }
      if(!mounted||generation!=_generation)return;
      _owned.addAll(images);
      setState(()=>_images=images);
    }catch(_){if(mounted&&generation==_generation)setState(()=>_error='비교 장면을 불러오지 못했습니다. 다시 시도해 주세요.');}
    finally{
      for(final path in acquired){if(!mounted||generation!=_generation||!_images.contains(path))await _delete(path);}
      if(mounted&&generation==_generation){
        final stale=_owned.where((p)=>!_images.contains(p)).toList();
        _owned.removeAll(stale);for(final path in stale){await _delete(path);}
      }
    }
  }
  @override
  void dispose(){_generation++;for(final path in _owned){_delete(path);}super.dispose();}
  Widget _panel(Map row,String path,String label,Color color)=>Column(children:[
    Text('$label · ${((row['t_ms'] as num)/1000).toStringAsFixed(3)}초',style:TextStyle(color:color,fontWeight:FontWeight.bold)),
    const SizedBox(height:8),
    AspectRatio(aspectRatio:(row['width'] as num)/(row['height'] as num),child:Stack(fit:StackFit.expand,children:[
      Image.file(File(path),fit:BoxFit.fill),CustomPaint(painter:_PairPainter(row,color,reference:_slot&&label=='다운스윙'?_pairs[_index]['backswing'] as Map:null)),
    ])),
  ]);
  @override
  Widget build(BuildContext context){
    final pair=_pairs.isEmpty?null:_pairs[_index];
    return Scaffold(appBar:CoachAppBar(title:const Text('백스윙·다운스윙 비교')),
      body:ListView(padding:const EdgeInsets.all(20),children:[
        Text(_slot?'파란 선은 백스윙 샤프트 기준선, 주황색은 다운스윙 샤프트입니다. 다운스윙 화면의 파란 점선으로 기준선을 함께 확인하세요.':'손이 비슷한 높이에 있는 두 장면입니다. 표시된 선이 실제 샤프트와 겹치는지 먼저 확인하세요.'),
        const SizedBox(height:16),
        if(pair==null)Text('${const {
          "backswing_shaft_unavailable":"백스윙에서 샤프트를 연속 추적하지 못했습니다.",
          "downswing_shaft_unavailable":"백스윙에서는 샤프트를 찾았지만 다운스윙 추적이 끊겼습니다.",
        }[_reason] ?? "같은 손 높이에서 비교할 연속 샤프트 후보가 부족합니다."}\n오버더탑 정상·오류를 판정한 것은 아닙니다.'),
        if(pair!=null)...[
          Text(_slot?'백스윙 기준선과 연속 다운스윙 비교':_source=='near_grip' ? '손 근처 샤프트 구간 비교' : '긴 샤프트 후보 구간 비교'),
          Text('비교 ${_index+1}/${_pairs.length} · 손 높이 차이 ${(pair['hand_height_difference_px'] as num).toStringAsFixed(1)}px'),
          const SizedBox(height:12),
          if(_error!=null)...[Text(_error!),TextButton(onPressed:()=>_load(_index),child:const Text('다시 불러오기'))]
          else if(_images.length!=2)const SizedBox(height:220,child:Center(child:CircularProgressIndicator()))
          else LayoutBuilder(builder:(context,limits){
            final back=_panel(pair['backswing'] as Map,_images[0],'백스윙',Colors.lightBlueAccent);
            final down=_panel(pair['downswing'] as Map,_images[1],'다운스윙',Colors.orangeAccent);
            return limits.maxWidth>=700 ? Row(crossAxisAlignment:CrossAxisAlignment.start,children:[Expanded(child:back),const SizedBox(width:16),Expanded(child:down)])
              : Column(children:[back,const SizedBox(height:20),down]);
          }),
          const SizedBox(height:16),
          Text('샤프트 후보의 영상상 방향 차이 ${(pair['shaft_angle_difference_deg'] as num).abs().toStringAsFixed(1)}°'),
          if(_slot&&pair['plane_outward_ratio'] is num)
            Text('기준선 바깥 이동: 몸통 길이 대비 ${((pair['plane_outward_ratio'] as num)*100).toStringAsFixed(1)}% (음수는 안쪽)'),
          if(!_slot&&pair['shaft_outward_ratio'] is num)
            Text('같은 길이 지점의 공 방향 이동: 몸통 길이 대비 ${((pair['shaft_outward_ratio'] as num)*100).toStringAsFixed(1)}%'),
          Row(mainAxisAlignment:MainAxisAlignment.spaceBetween,children:[
            TextButton(onPressed:_index>0?()=>_load(_index-1):null,child:const Text('이전 비교')),
            TextButton(onPressed:_index<_pairs.length-1?()=>_load(_index+1):null,child:const Text('다음 비교')),
          ]),
          Text(_slot?'후방 2D 영상의 샤프트 기준선에 대한 앱 판정입니다. 선 끝은 클럽 헤드가 아니며, 기준 이내는 스윙 전체의 정상을 뜻하지 않습니다.':'점선은 손 높이입니다. 선 끝은 클럽 헤드가 아닙니다. 연속 샤프트 근거가 부족하면 자동 판정에 사용하지 않습니다.'),
        ],
      ]));
  }
}
class _PairPainter extends CustomPainter {
  final Map row;final Color color;final Map? reference;
  _PairPainter(this.row,this.color,{this.reference});
  @override
  void paint(Canvas canvas,Size size){
    Offset point(Map p)=>Offset((p['x'] as num)*size.width/(row['width'] as num),(p['y'] as num)*size.height/(row['height'] as num));
    if(reference!=null) {
      final a=point(reference!['grip'] as Map),b=point(reference!['shaft_end'] as Map);
      final delta=b-a;
      final p=Paint()..color=Colors.lightBlueAccent..strokeWidth=2;
      canvas.save();canvas.clipRect(Offset.zero&size);
      for(double t=-10;t<10;t+=.15){canvas.drawLine(a+delta*t,a+delta*(t+.08),p);}
      canvas.restore();
    }
    final grip=point(row['grip'] as Map),end=point(row['shaft_end'] as Map);
    final paint=Paint()..color=color..strokeWidth=2;
    canvas.drawLine(grip,end,paint);canvas.drawCircle(grip,4,paint);
    paint.color=color.withOpacity(.6);paint.strokeWidth=1;
    for(double x=0;x<size.width;x+=12){canvas.drawLine(Offset(x,grip.dy),Offset((x+6).clamp(0,size.width).toDouble(),grip.dy),paint);}
  }
  @override
  bool shouldRepaint(_PairPainter old)=>old.row!=row||old.color!=color;
}
