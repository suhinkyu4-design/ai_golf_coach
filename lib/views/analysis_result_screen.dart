import '../widgets/coach_app_bar.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/swing_provider.dart';
import 'analysis_details_screen.dart';
import 'ocr_input_screen.dart';
import '../services/shot_insight_service.dart';
import 'motion_detection_screen.dart';
import 'pose_trimming_screen.dart';
import '../widgets/motion_visual_card.dart';
import '../widgets/shot_visual_card.dart';
import '../widgets/correction_guide_card.dart';
import '../models/swing_model.dart';

class AnalysisResultScreen extends StatelessWidget {
  const AnalysisResultScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final provider = context.watch<SwingProvider>();
    final result = provider.currentAnalysisResult;
    final shot = provider.currentShotMeasurement;
    final shotInsights = ShotInsightService.describe(shot, swingId: provider.currentSwing?.swingId);
    final motion = provider.currentPoseReport?['fault_features'] as Map?;
    final sway = motion?['head_trail_check'] as Map?;
    final extension = motion?['early_extension_check'] as Map?;
    final headUp = motion?['head_up_check'] as Map?;
    final chicken = motion?['chicken_wing_check'] as Map?;
    final standing = motion?['standing_up_check'] as Map?;
    final overTop = motion?['over_the_top_check'] as Map?;
    final casting = motion?['casting_check'] as Map?;
    return Scaffold(
      appBar: CoachAppBar(title: const Text('스윙 결과'), actions: [
        PopupMenuButton<String>(tooltip: '설정', icon: const Icon(Icons.settings_outlined),
          onSelected: (value) => Navigator.push(context, MaterialPageRoute(builder: (_) =>
            value == 'timing' ? const PoseTrimmingScreen() : value == 'shot' ? const OcrInputScreen() : const AnalysisDetailsScreen())),
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'timing', child: Text('자세 시점 수정')),
            PopupMenuItem(value: 'detail', child: Text('측정 상세')),
            PopupMenuItem(value: 'shot', child: Text('샷 기록 추가')),
          ]),
      ]),
      body: result == null
          ? const Center(child: Text('영상을 분석하면 코멘트가 표시됩니다.'))
          : SafeArea(
              child: ListView(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
                  children: [
                  Text(
                      motion == null ? '이번 스윙에서\n확인할 한 가지' : '이번 스윙의\n분석 결과',
                      style: Theme.of(context).textTheme.headlineMedium),
                  const SizedBox(height: 32),
                  if (motion == null)
                    Text(result.koreanSummary, style: Theme.of(context).textTheme.titleMedium)
                  else ...[
                    if (provider.currentSwing != null) MotionVisualCard(
                      key: ValueKey(provider.currentSwing!.swingId), videoPath: provider.currentSwing!.videoPath,
                      report: provider.currentPoseReport!, leadSide: provider.currentSwing!.handedness == Handedness.right ? 'left' : 'right'),
                    const SizedBox(height: 12),
                    ExpansionTile(title: const Text('전체 동작 판정과 수치'), children: [
                    _ruleCard(context, '스웨이', sway,
                      sway?['value'] is num ? '머리 이동 · ${sway?['normalization_label']} 대비 ${((sway?['value'] as num) * 100).toStringAsFixed(1)}%' : null),
                    const SizedBox(height: 12),
                    _ruleCard(context, '얼리 스탠드업', standing,
                      standing?['value'] is num ? '상체 기울기 감소 · ${(standing?['value'] as num).toStringAsFixed(1)}°' : null),
                    const SizedBox(height: 12),
                    _ruleCard(context, '배치기', extension,
                      extension?['value'] is num ? '임팩트 골반 이동 · 발 길이 대비 ${((extension?['value'] as num) * 100).toStringAsFixed(1)}%' : null),
                    const SizedBox(height: 12),
                    _ruleCard(context, '치킨윙', chicken,
                      chicken?['value'] is num ? '임팩트 직후 팔꿈치 굽힘 증가 · ${(chicken?['value'] as num).toStringAsFixed(1)}°' : null),
                    const SizedBox(height: 12),
                    _ruleCard(context, '헤드업', headUp,
                      headUp?['value'] is num ? '임팩트 전 머리 상승 · 몸통 길이 대비 ${((headUp?['value'] as num) * 100).toStringAsFixed(1)}%' : null),
                    if(casting?['status']=='rule_classified') ...[
                      const SizedBox(height:12),
                      _ruleCard(context,'캐스팅',casting,
                        casting!['angle_change_measured']==false
                          ? '초기 다운스윙 팔·샤프트 각도 · ${(casting['early_down_angle_deg'] as num).toStringAsFixed(1)}°'
                          : '다운스윙 팔·샤프트 각도 증가 · ${(casting['opening_change_deg'] as num).toStringAsFixed(1)}°'),
                    ],
                    if (overTop != null) ...[
                      const SizedBox(height: 12),
                      _ruleCard(context, '오버더탑', overTop,
                        overTop['value'] is num ? '샤프트 기준선 ${(overTop['value'] as num)>=0?'바깥':'안쪽'} · 몸통 길이 대비 ${((overTop['value'] as num).abs()*100).toStringAsFixed(1)}%' : null),
                    ],
                    ]),
                  ],
                  if (shotInsights.isNotEmpty) ...[
                    const SizedBox(height: 24),
                    ShotVisualCard(shot: shot!),
                  ],
                  if (motion == null) Card(child: Padding(padding: const EdgeInsets.all(24), child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(result.primaryDrillTitle, style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height:12), Text(result.primaryDrillDescription),
                    ]))),
                  const SizedBox(height:24),
                  Text(
                      motion != null
                          ? '앱 판정 기준 적용 · 촬영 각도와 카메라 흔들림에 따른 오차 가능'
                          : provider.currentSlmComment?['slm_output_used'] ==
                                  true
                              ? '기기 내 모델 · 측정값 설명'
                              : '영상 측정값 기반 요약',
                      style: Theme.of(context).textTheme.bodySmall),
                  const SizedBox(height: 12),
                  if (motion != null)
                    ElevatedButton(
                        onPressed: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) => const MotionDetectionScreen())),
                        child: const Text('영상으로 확인하기')),
                  const SizedBox(height: 12),
                  ElevatedButton(
                      onPressed: () =>
                          Navigator.popUntil(context, (r) => r.isFirst),
                      child: const Text('홈으로')),
                ])),
    );
  }
  Widget _ruleCard(BuildContext context, String title, Map? rule, String? detail) {
    final ready = rule?['status'] == 'rule_classified';
    final grade = rule?['grade'];
    final headObserved = title == '스웨이' && rule?['head_position_measured'] == true;
    final swayReason = rule?['reason'] == 'target_direction_unknown'
      ? '머리는 확인했지만 발이 겹쳐 타깃 방향을 구분하기 어렵습니다.'
      : '머리는 확인했지만 귀·어깨가 겹쳐 비교할 기준 너비가 부족합니다.';

    final dark = Theme.of(context).brightness == Brightness.dark;
    final color = !ready ? Theme.of(context).colorScheme.onSurfaceVariant : grade == 'within_rule'
      ? Theme.of(context).colorScheme.primary : dark ? Colors.amber : const Color(0xFF9A4600);
    return Card(child: Padding(padding: const EdgeInsets.all(20), child: Column(
      crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(ready ? rule!['label'] as String : headObserved ? '스웨이 · 머리 이동 확인' : '$title · 측정 불가',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(color: color)),
        const SizedBox(height: 8),
        Text(ready && detail != null ? detail : headObserved
          ? '어드레스 → 탑 가로 이동 ${(rule!["horizontal_displacement_px"] as num).abs().toStringAsFixed(1)}px\n$swayReason\n스웨이 여부는 판정하지 않았습니다.'
          : title=='오버더탑'
            ? '백스윙과 다운스윙의 샤프트를 충분히 연속 추적하지 못했습니다. 정상으로 판정한 것은 아닙니다.'
            : '이 영상에서 필요한 관절을 확인하지 못했습니다.'),
        if (title == '캐스팅' || title == '오버더탑') CorrectionGuideCard(
          kind: title == '캐스팅' ? 'casting_check' : 'over_the_top_check', rule: rule,
          leftHanded: context.read<SwingProvider>().currentSwing?.handedness == Handedness.left),
      ])));
  }

}
