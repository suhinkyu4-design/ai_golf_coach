import '../widgets/coach_app_bar.dart';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../providers/swing_provider.dart';

/// Optional development evidence, never part of the required analysis flow.
class ClubTrackReviewScreen extends StatefulWidget {
  final bool nearGrip;
  const ClubTrackReviewScreen({super.key, this.nearGrip = false});
  @override
  State<ClubTrackReviewScreen> createState()=>_ClubTrackReviewScreenState();
}
class _ClubTrackReviewScreenState extends State<ClubTrackReviewScreen> {
  static const channel=MethodChannel('com.metaoffice.aigolfcoatch/frame_extractor');
  List<Map> _rows=[];
  final _angles=<int,num>{};
  final _observedArms=<int,Map>{};
  String _leadSide = 'left';
  final _files=<String>{};
  String? _video,_image,_error;
  int _index=0,_generation=0;
  @override
  void initState(){
    super.initState();
    final provider=context.read<SwingProvider>();
    for(final observation in provider.currentPoseReport?['fault_features']?['casting_check']?['observations'] as List? ?? []) {
      if(observation['t_ms'] is int && observation['angle_deg'] is num) {
        _angles[observation['t_ms'] as int]=observation['angle_deg'] as num;
        _observedArms[observation['t_ms'] as int]={'elbow':observation['lead_elbow'],'wrist':observation['lead_wrist']};
      }
    }
    _video=provider.currentSwing?.videoPath;
    _leadSide = provider.currentSwing?.handedness.name == 'left' ? 'right' : 'left';
    final key = widget.nearGrip ? 'near_shaft_candidate' : 'shaft_candidate';
    _rows=[for(final row in provider.currentPoseReport?['motion_evidence']?['samples'] as List? ?? [])
      if(row[key] is Map && row[key]['shaft_end'] is Map)
        row[key] as Map];
    if(widget.nearGrip) {
      _rows=[for(final row in _rows) if(_observedArms.containsKey(row['t_ms']))
        {...row,'forearms':{...row['forearms'] as Map,_leadSide:_observedArms[row['t_ms']]}}
        else row];
    }
    if(_rows.isNotEmpty)_load(0);
  }
  Future<void> _remove(String path)async{try{await File(path).delete();}catch(_){} }
  Future<void> _load(int index)async{
    final generation=++_generation;
    setState((){_index=index;_image=null;_error=null;});
    final owned=<String>[];
    try{
      final t=_rows[index]['t_ms'] as int;
      final frames=await channel.invokeMethod<List<dynamic>>('extractFrames',{
        'videoPath':_video,'startMs':t,'endMs':t,'sampleCount':2});
      for(final frame in frames ?? []){owned.add(frame['path'] as String);}
      if(owned.isEmpty)throw StateError('no frame');
      if(!mounted||generation!=_generation)return;
      _files.addAll(owned);
      setState(()=>_image=owned.first);
    }catch(_){if(mounted&&generation==_generation)setState(()=>_error='해당 프레임을 열지 못했습니다.');}
    finally{
      for(final path in owned){if(!mounted||generation!=_generation)await _remove(path);}
      // Bound temporary images to the current request.
      if(mounted&&generation==_generation){
        final stale=_files.where((p)=>p!=_image).toList();
        _files.removeAll(stale);for(final p in stale){await _remove(p);}
      }
    }
  }
  @override
  void dispose(){_generation++;for(final path in _files){_remove(path);}super.dispose();}
  @override
  Widget build(BuildContext context){
    final row=_rows.isEmpty?null:_rows[_index];
    return Scaffold(appBar:CoachAppBar(title:const Text('클럽 추적 검증')),
      body:ListView(padding:const EdgeInsets.all(20),children:[
        Text(widget.nearGrip ? '하늘색은 리드 팔의 전완, 초록·주황색은 손 근처 샤프트 후보입니다. 아직 캐스팅 판정에 사용하지 않습니다.' : '표시된 선이 실제 샤프트와 겹치는지 확인합니다. 선 끝은 클럽 헤드 위치가 아닙니다. 아직 오버더탑 판정에 사용하지 않습니다.'),
        const SizedBox(height:16),
        if(row==null)const Text('비교할 샤프트 후보를 찾지 못했습니다.'),
        if(row!=null)...[
          Text('${(row['t_ms'] as num)/1000}초 · ${row['temporally_supported']==true?'연속 후보':'연속성 미확인'}'),
          if(widget.nearGrip)
            Text(_angles[row['t_ms']] == null ? '이 후보의 각도는 측정 근거가 부족합니다.'
              : '전완–샤프트 투영각 ${_angles[row['t_ms']]!.toStringAsFixed(1)}° · 정상/오류 판정 아님'),
          const SizedBox(height:8),
          if(_error!=null)Text(_error!)
          else if(_image==null)const SizedBox(height:360,child:Center(child:CircularProgressIndicator()))
          else SizedBox(height:420,child:Center(child:AspectRatio(
            aspectRatio:(row['width'] as num)/(row['height'] as num),
            child:Stack(fit:StackFit.expand,children:[
              Image.file(File(_image!),fit:BoxFit.fill),
              CustomPaint(painter:_ShaftPainter(row, widget.nearGrip ? _leadSide : null)),
            ])))),
          Row(mainAxisAlignment:MainAxisAlignment.spaceBetween,children:[
            TextButton(onPressed:_index>0?()=>_load(_index-1):null,child:const Text('이전 후보')),
            Text('${_index+1} / ${_rows.length}'),
            TextButton(onPressed:_index<_rows.length-1?()=>_load(_index+1):null,child:const Text('다음 후보')),
          ]),
          const Text('초록: 연속성 검사 통과 · 주황: 미확인 후보\n요청 시각에서 가장 가까운 영상 프레임을 표시합니다.'),
        ],
      ]));
  }
}
class _ShaftPainter extends CustomPainter{
  final Map row;
  final String? lead;
  _ShaftPainter(this.row, this.lead);
  @override
  void paint(Canvas canvas,Size size){
    Offset point(Map p)=>Offset((p['x'] as num)*size.width/(row['width'] as num),
      (p['y'] as num)*size.height/(row['height'] as num));
    final paint=Paint()..color=(row['temporally_supported']==true?Colors.greenAccent:Colors.orangeAccent)..strokeWidth=2;
    final start=point(row['grip'] as Map),end=point(row['shaft_end'] as Map);
    canvas.drawLine(start,end,paint);paint.style=PaintingStyle.stroke;
    canvas.drawCircle(start,4,paint);canvas.drawCircle(end,4,paint);
    final arm = lead == null ? null : row['forearms']?[lead];
    if (arm is Map) {
      paint.color = Colors.lightBlueAccent;
      canvas.drawLine(point(arm['elbow'] as Map),point(arm['wrist'] as Map),paint);
    }
  }
  @override
  bool shouldRepaint(_ShaftPainter old)=>old.row!=row || old.lead!=lead;
}
