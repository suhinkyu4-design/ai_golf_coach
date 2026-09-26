import 'package:ai_golf_coach/services/casting_rule.dart';
void check(bool v,String m){if(!v)throw StateError(m);}
Map<String,dynamic> report({double start=80,double end=135})=>{
 'halfway_t_ms':1250,'observations':[for(var i=0;i<10;i++){
   't_ms':[970,1000,1030,1090,1120,1150,1190,1220,1250,1280][i],
   'angle_deg':i<3?start:start+(end-start)*(i-2)/6,
   'sequence_index':i,'forearm_length_ratio':.45,'shaft_image_supported':true,'frame_signature':'image$i'}]};
Map run(Map r)=>CastingRule.evaluate(r,top:1000,impact:1400,view:'rear');
void main(){
 check(run(report())['grade']=='casting','early opening not detected');
 check(run(report(end:90))['grade']=='within_rule','maintained angle not within rule');
 check(run(report(end:105))['grade']=='warning','warning missing');
 check(run(report(start:140,end:150))['status']=='unavailable','already-open baseline called normal');
 final missing=report()..['halfway_t_ms']=null;
 check(run(missing)['reason']=='halfway_not_observed','invented halfway');
 final short=report();short['observations'][4]['forearm_length_ratio']=.15;
 check(run(short)['status']=='unavailable','foreshortened arm accepted');
 final background=report();background['observations'][4]['shaft_image_supported']=false;
 check(run(background)['status']=='unavailable','background shaft accepted');
 final hole=report();hole['observations'].removeAt(4);
 check(run(hole)['reason']=='angle_sequence_gap','missing angle bridged');
 final dup=report();dup['observations'][4]['frame_signature']='image3';
 check(run(dup)['reason']=='duplicate_decoded_frame','duplicate counted');
 final jump=report();jump['observations'][4]['angle_deg']=10.0;
 check(run(jump)['reason']=='angle_jump','angle reversal accepted');
 final nan=report();nan['observations'][4]['angle_deg']=double.nan;
 check(run(nan)['status']=='unavailable','NaN accepted');
 check(run(report())['diagnosis_validated']==false,'claimed externally validated');
 Map<String,dynamic> early({bool descending=true,double angle=160,double hip=-.8})=>{
   'halfway_t_ms':null,'observations':[for(var i=0;i<3;i++){
     't_ms':1100+33*i,'sequence_index':i,'angle_deg':angle,'angle_margin_assumed_deg':10.0,
     'forearm_length_ratio':.35,'shaft_image_supported':true,'frame_signature':'early$i',
     'wrist_y':descending?100.0+20*i:100.0,'wrist_hip_ratio':hip,'torso_length_px':100.0}]};
 final detected=run(early());
 check(detected['grade']=='casting'&&detected['angle_change_measured']==false,'early positive-only screen');
 check(detected['opening_change_deg']==null&&detected['top_angle_deg']==null,'invented unseen top angle');
 check(run(early(descending:false))['status']=='unavailable','top pause treated as downswing');
 check(run(early(angle:125))['status']=='unavailable','ignored assumed angle margin');
 check(run(early(angle:80))['status']=='unavailable','partial clip reported normal');
 check(run(early(hip:.2))['status']=='unavailable','late natural release classified as early');
 final earlyGap=early();earlyGap['observations'][1]['sequence_index']=7;
 check(run(earlyGap)['status']=='unavailable','early screen bridged missing image');
 final earlyDup=early();earlyDup['observations'][1]['frame_signature']='early0';
 check(run(earlyDup)['status']=='unavailable','early screen counted repeated image');
 final earlyNoShaft=early();earlyNoShaft['observations'][1]['shaft_image_supported']=false;
 check(run(earlyNoShaft)['status']=='unavailable','early screen accepted unsupported shaft');
 print('CASTING_RULE_CHECK_PASSED');
}
