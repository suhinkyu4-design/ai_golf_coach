import 'dart:math' as math;
import 'package:ai_golf_coach/services/over_the_top_rule.dart';
void check(bool v,String m){if(!v)throw StateError(m);}
List<Map<String,dynamic>> fixture({double outward=0,double scale=1,bool mirror=false}) {
 final rows=<Map<String,dynamic>>[];
 for(final t in [100,133,166,500,533,566]) {
  final down=t>=500;
  final index=down?(t-500)/33:(t-100)/33;
  final y=down?195+index*15:210-index*15;
  final x=200+(y-210)/math.sqrt(3)+(down?outward:0);
  double tx(double a)=>(mirror?600-a:a)*scale;
  final angle=mirror?300.0:240.0;
  final c=<String,dynamic>{'t_ms':t,'status':'line_candidate','temporally_supported':true,
    'extension_supported':true,'frame_signature':'frame$t','width':600*scale,'height':600*scale,
    'coordinate_space':'upright_image_pixels','angle_deg':angle,'length_px':80*scale,'torso_length_px':100*scale,
    'grip':{'x':tx(x),'y':y*scale},'shaft_end':{'x':tx(x-40),'y':(y-80*math.sqrt(3)/2)*scale}};
  rows.add({'t_ms':t,'width':600*scale,'height':600*scale,'near_shaft_candidate':c});
 }
 return rows;
}
void main(){
 Map run(List<Map<String,dynamic>> rows,{int? sign=1,bool rear=true})=>OverTheTopRule.evaluate(rows,address:0,top:300,impact:650,rear:rear,ballSign:sign);
 final normal=run(fixture());
 check(normal['grade']=='within_rule','aligned shafts should be within app rule');
 check((normal['value'] as num).abs()<1e-9,'aligned reference distance');
 final positive=run(fixture(outward:25));
 check(positive['grade']=='over_the_top','outward shaft not detected');
 check(run(fixture(outward:8))['grade']=='warning','borderline outside not warning');
 check(run(fixture(outward:-25))['grade']=='within_rule','inside path marked outside');
 check(run(fixture(outward:25,mirror:true),sign:-1)['grade']=='over_the_top','mirror invariance');
 check(((run(fixture(outward:25,scale:2))['value'] as num)-(positive['value'] as num)).abs()<1e-9,'scale invariance');
 check(run(fixture(),sign:null)['status']=='unavailable','unknown direction called normal');
 check(run(fixture(),rear:false)['status']=='unavailable','unsupported camera called normal');
 final missing=fixture()..removeAt(4);
 check(run(missing)['status']=='unavailable','two observations called normal');
 final duplicate=fixture();duplicate[4]['near_shaft_candidate']['frame_signature']='frame500';
 check(run(duplicate)['status']=='unavailable','duplicate decoded image counted');
 final ambiguous=fixture();ambiguous[4]['near_shaft_candidate']['status']='ambiguous';
 check(run(ambiguous)['status']=='unavailable','ambiguous line counted');
 final weak=fixture();for(final row in weak){row['near_shaft_candidate']['extension_supported']=false;}
 check(run(weak)['status']=='unavailable','temporal-only background track classified');
 final invalid=fixture();invalid[4]['near_shaft_candidate']['grip']['x']=double.nan;
 check(run(invalid)['status']=='unavailable','NaN counted');
 final dimensions=fixture();dimensions[4]['width']=601;
 check(run(dimensions)['status']=='unavailable','coordinate mismatch counted');
 check(positive['diagnosis_validated']==false&&positive['diagnosis']==null,'heuristic claimed validated diagnosis');
 print('OVER_THE_TOP_RULE_CHECK_PASSED');
}
