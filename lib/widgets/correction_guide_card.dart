import 'package:flutter/material.dart';
import '../services/correction_guide.dart';

class CorrectionGuideCard extends StatelessWidget {
  final String kind;
  final Map? rule;
  final bool leftHanded;
  const CorrectionGuideCard({super.key,required this.kind,required this.rule,this.leftHanded=false});
  @override Widget build(BuildContext context) {
    final guide=CorrectionGuide.guides[kind];
    if(guide==null)return const SizedBox.shrink();
    if(!CorrectionGuide.eligible(rule))return Padding(padding:const EdgeInsets.only(top:16),child:Text(
      rule?['status']=='rule_classified' && rule?['grade']=='within_rule'
        ? '이번 영상에서는 이 동작이 앱 기준 이내입니다. 무리하게 자세를 바꾸기보다 같은 움직임을 유지해 보세요.'
        : '측정 근거가 부족해 이 동작의 교정 안내는 표시하지 않습니다. 먼저 영상에서 해당 장면을 확인해 주세요.',
      style:Theme.of(context).textTheme.bodySmall));
    final c=Theme.of(context).colorScheme;
    return Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
      const SizedBox(height:16),const Divider(),
      Row(children:[Icon(Icons.self_improvement,color:c.primary),const SizedBox(width:8),Text('이렇게 연습해 보세요',style:Theme.of(context).textTheme.titleMedium)]),
      const SizedBox(height:8),Text(guide.title),const SizedBox(height:16),
      LayoutBuilder(builder:(context,box) {
        Widget panel(bool practice)=>Column(children:[
          Text(practice?'② 연습 방향':'① 확인할 움직임',style:Theme.of(context).textTheme.bodySmall),
          Semantics(label:practice?guide.focus:guide.title,child:SizedBox(height:150,width:160,child:CustomPaint(
            painter:_CoachPainter(kind,practice,leftHanded,c.onSurface,c.primary)))),
        ]);
        return box.maxWidth<260?Column(children:[panel(false),panel(true)]):Row(children:[Expanded(child:panel(false)),const Icon(Icons.arrow_forward,size:18),Expanded(child:panel(true))]);
      }),
      Text('연습 설명용 그림 · 실제 관절이나 정답 각도를 재현한 것이 아닙니다.',style:Theme.of(context).textTheme.bodySmall),
      const SizedBox(height:12),Text(guide.focus,style:Theme.of(context).textTheme.titleMedium),
      const SizedBox(height:8),
      for(var i=0;i<guide.steps.length;i++) Padding(padding:const EdgeInsets.only(bottom:8),child:Text('${i+1}. ${guide.steps[i]}')),
      TextButton.icon(onPressed:()=>showDialog<void>(context:context,builder:(context)=>AlertDialog(
        title:const Text('천천히 5번, 다시 확인'),content:const Text('공 없이 작은 빈스윙으로 5번 연습해 보세요. 편안한 범위에서 움직이고, 통증이 느껴지면 멈추세요. 같은 촬영 위치에서 다시 찍어 변화를 비교하세요.'),
        actions:[TextButton(onPressed:()=>Navigator.pop(context),child:const Text('확인'))])),
        icon:const Icon(Icons.replay_5),label:const Text('연습 방법 보기')),
    ]);
  }
}
class _CoachPainter extends CustomPainter {
  final String kind; final bool practice, mirror; final Color ink, accent;
  _CoachPainter(this.kind,this.practice,this.mirror,this.ink,this.accent);
  @override void paint(Canvas canvas,Size size) {
    canvas.save();canvas.scale(size.width/160,size.height/150);
    if(mirror){canvas.translate(160,0);canvas.scale(-1,1);}
    final p=Paint()..color=ink..strokeWidth=5..strokeCap=StrokeCap.round..style=PaintingStyle.stroke;
    final hi=Paint()..color=practice?accent:const Color(0xFFB65B00)..strokeWidth=3..style=PaintingStyle.stroke;
    void line(Offset a,Offset b,[Paint? pen])=>canvas.drawLine(a,b,pen??p);
    void dash(double x){for(double y=20;y<132;y+=10)line(Offset(x,y),Offset(x,y+5),Paint()..color=ink.withOpacity(.35)..strokeWidth=1.5);}
    var hip=const Offset(68,90), shoulder=const Offset(92,53), head=const Offset(98,33);
    if(!practice&&kind=='head_trail_check'){hip=hip+const Offset(-17,0);shoulder=shoulder+const Offset(-23,0);head=head+const Offset(-23,0);}
    if(!practice&&kind=='early_extension_check'){hip=hip+const Offset(20,0);shoulder=shoulder+const Offset(9,-5);head=head+const Offset(9,-5);}
    if(!practice&&(kind=='standing_up_check'||kind=='head_up_check')){shoulder=const Offset(77,43);head=const Offset(79,23);}
    canvas.drawCircle(head,9,p);line(head+const Offset(-3,10),shoulder);line(shoulder,hip);
    line(hip,const Offset(57,113));line(const Offset(57,113),const Offset(47,138));line(hip,const Offset(87,113));line(const Offset(87,113),const Offset(105,138));
    line(const Offset(40,138),const Offset(54,138));line(const Offset(100,138),const Offset(115,138));
    var elbow=const Offset(106,77),hand=const Offset(119,95);
    if(kind=='chicken_wing_check'){elbow=practice?const Offset(112,63):const Offset(64,59);hand=practice?const Offset(136,69):const Offset(98,53);}
    if(kind=='over_the_top_check'){elbow=Offset(practice?99:128,70);hand=Offset(practice?110:144,86);}
    line(shoulder,elbow);line(elbow,hand);
    final clubEnd=kind=='casting_check'?Offset(practice?139:133,practice?48:133):const Offset(142,132);
    line(hand,clubEnd,Paint()..color=ink.withOpacity(.6)..strokeWidth=2);line(clubEnd,clubEnd+const Offset(-8,2),p);
    if(kind=='head_trail_check'||kind=='head_up_check'){dash(98);canvas.drawCircle(head,15,hi);}
    else if(kind=='early_extension_check'){dash(62);canvas.drawCircle(hip,14,hi);}
    else if(kind=='standing_up_check'){line(const Offset(68,90),const Offset(92,53),Paint()..color=accent.withOpacity(.3)..strokeWidth=10);line(hip,shoulder,hi);}
    else if(kind=='chicken_wing_check'){canvas.drawCircle(elbow,13,hi);}
    else {canvas.drawCircle(hand,12,hi);line(hand,clubEnd,hi);}
    canvas.restore();
  }
  @override bool shouldRepaint(covariant _CoachPainter old)=>old.kind!=kind||old.practice!=practice||old.mirror!=mirror||old.ink!=ink||old.accent!=accent;
}
