import '../lib/services/correction_guide.dart';
void main() {
  for(final rule in [null, <String,dynamic>{}, {'status':'unavailable','grade':'warning'}, {'status':'rule_classified','grade':'within_rule'}, {'status':'rule_classified','grade':'unknown'}]) {
    if(CorrectionGuide.eligible(rule)) throw StateError('Unmeasured or in-range motion got corrective advice');
  }
  for(final grade in ['warning','sway','standing_up','early_extension','chicken_wing','head_up','casting','over_the_top']) {
    if(!CorrectionGuide.eligible({'status':'rule_classified','grade':grade})) throw StateError('Missing detected motion');
  }
  if(CorrectionGuide.guides.length!=7)throw StateError('Missing guide');
  print('PASS: unavailable/normal/unknown gated; seven motion guides available');
}
