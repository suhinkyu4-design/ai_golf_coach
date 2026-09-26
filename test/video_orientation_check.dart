import 'package:ai_golf_coach/services/video_orientation_service.dart';
void main(){
 for(final turn in [0,1,2,3]) {
  final dx=turn==1?200:turn==3?-200:0;
  final dy=turn==0?200:turn==2?-200:0;
  final rows=List.generate(6,(_)=><String,dynamic>{'width':1000,'height':1000,'landmarks':[
    for(final name in ['leftShoulder','rightShoulder','leftAnkle','rightAnkle'])
      {'name':name,'x':500+(name.contains('Ankle')?dx:0),
       'y':500+(name.contains('Ankle')?dy:0),'likelihood':.99}]});
  if(VideoOrientationService.infer(rows)!=turn)throw StateError('wrong rotation $turn');
  if(VideoOrientationService.infer(rows.take(4).toList())!=null)throw StateError('too few votes');
 }
 print('ORIENTATION_CHECK_PASSED');
}
