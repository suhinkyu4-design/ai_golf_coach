import 'dart:convert';
import 'dart:io';

/// Extra clockwise quarter turns after the platform's metadata rotation.
class VideoOrientationService {
  static int? infer(List<Map<String,dynamic>> samples) {
    final votes=<int,int>{};
    for(final row in samples) {
      final points=<String,Map>{for(final p in (row['landmarks'] as List? ?? []).whereType<Map>())
        if(p['name'] is String && p['likelihood'] is num && (p['likelihood'] as num)>=.8 &&
          p['x'] is num && p['y'] is num && (p['x'] as num)>=0 && (p['y'] as num)>=0 &&
          (p['x'] as num)<(row['width'] as num) && (p['y'] as num)<(row['height'] as num))p['name'] as String:p};
      if(!['leftShoulder','rightShoulder','leftAnkle','rightAnkle'].every(points.containsKey))continue;
      double center(String a,String b,String axis)=>((points[a]![axis] as num)+(points[b]![axis] as num))/2;
      final dx=center('leftAnkle','rightAnkle','x')-center('leftShoulder','rightShoulder','x');
      final dy=center('leftAnkle','rightAnkle','y')-center('leftShoulder','rightShoulder','y');
      if(dx*dx+dy*dy<400)continue;
      int? turns;
      if(dx.abs()>dy.abs()*1.5)turns=dx<0?3:1;
      if(dy.abs()>dx.abs()*1.5)turns=dy>0?0:2;
      if(turns!=null)votes.update(turns,(v)=>v+1,ifAbsent:()=>1);
    }
    final total=votes.values.fold<int>(0,(a,b)=>a+b);
    if(total<5)return null;
    final sorted=votes.entries.toList()..sort((a,b)=>b.value.compareTo(a.value));
    return sorted.first.value/total>=.8?sorted.first.key:null;
  }
  static Future<int> read(String path) async {
    try {final data=jsonDecode(await File('$path.orientation.json').readAsString());
      final value=data['quarter_turns'];return value is int&&value>=0&&value<=3?value:0;
    }catch(_){return 0;}
  }
}
