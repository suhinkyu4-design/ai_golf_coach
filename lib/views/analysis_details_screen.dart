import '../widgets/coach_app_bar.dart';
import '../services/casting_rule.dart';
import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:flutter/services.dart';
import '../widgets/golf_widgets.dart';
import 'package:provider/provider.dart';
import '../providers/swing_provider.dart';
import '../models/metric_model.dart';
import '../models/shot_measurement_model.dart';
import 'pose_trimming_screen.dart';
import 'club_track_review_screen.dart';
import 'over_top_review_screen.dart';

class AnalysisDetailsScreen extends StatelessWidget {
  const AnalysisDetailsScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final provider = context.watch<SwingProvider>();
    final result = provider.currentAnalysisResult;
    final swing = provider.currentSwing;
    final knee = provider.currentPoseReport?['fault_features']?['trail_knee_check'] as Map?;
    final clubTrack = provider.currentPoseReport?['fault_features']?['over_the_top_check'] as Map?;
    final casting = provider.currentPoseReport?['fault_features']?['casting_check'] as Map?;
    final shot = provider.currentShotMeasurement;
    return Scaffold(
      appBar: CoachAppBar(title: const Text('분석 상세')),
      body: result == null || swing == null
          ? const Center(child: Text('표시할 결과가 없습니다. 영상 구간을 확인한 뒤 다시 진행하세요.'))
          : ListView(padding: const EdgeInsets.all(20), children: [
              const GolfStepHeader(
                  step: 4,
                  title: '이번 스윙의 기록',
                  description: '영상에서 지정한 시간과 확인한 샷 수치를 함께 봅니다.'),
              Text(
                  '${swing.club} · ${swing.view.name} · ${swing.handedness.name}',
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 12),
              Card(
                  child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(result.koreanSummary))),
              const SizedBox(height: 12),
              if (knee?['address_angle_deg'] is num && knee?['top_angle_deg'] is num)
                ExpansionTile(title: const Text('무릎 움직임 · 참고 수치'),
                  children: [Padding(padding: const EdgeInsets.all(16), child: Text(
                    '어드레스 ${(knee!['address_angle_deg'] as num).toStringAsFixed(1)}° → 탑 ${(knee['top_angle_deg'] as num).toStringAsFixed(1)}°\n자연스러운 변화가 포함될 수 있어 오류 여부를 판정하지 않습니다.'))]),
              if (casting != null)
                ExpansionTile(title: const Text('캐스팅 · 릴리즈 비교'),
                  subtitle: Text(casting['status']=='rule_classified'?casting['label'] as String:'각도 관찰 ${casting['valid_angle_frames'] ?? 0}개'), children: [
                    Padding(padding:const EdgeInsets.all(16),child:Text(casting['status']=='rule_classified'
                      ? casting['angle_change_measured']==false
                        ? '손이 골반보다 높은 다운스윙 초반 3장면에서 팔·샤프트가 크게 펴진 상태를 연속 확인했습니다. 앱의 캐스팅 의심 기준입니다.'
                        : '탑부터 손이 골반 높이에 오는 구간까지 연속 각도를 비교한 앱 기준입니다.'
                      : '${CastingRule.reasonMessage(casting['rule_check']?['reason'] as String?)} 정상으로 판정한 것은 아닙니다.')),
                    if (casting['selected_segment'] is Map)
                      Padding(padding: const EdgeInsets.all(16), child: Text(
                        '다운스윙 연속 관찰 ${casting['selected_segment']['frame_count']}개 · ${casting['selected_segment']['duration_ms']}ms\n'
                        '투영각 ${(casting['selected_segment']['start_angle_deg'] as num).toStringAsFixed(1)}° → ${(casting['selected_segment']['end_angle_deg'] as num).toStringAsFixed(1)}°\n'
                        '보이는 구간만 비교한 값이며, 전체 다운스윙이나 캐스팅 판정은 아닙니다.')),
                    if ((casting['arm_refinement_attempts'] as num? ?? 0) > 0)
                      Padding(padding: const EdgeInsets.all(16), child: Text(
                        '팔 확대 재검출 ${casting['arm_refinement_attempts']}개 중 ${casting['arm_refinement_accepted'] ?? 0}개 반영')),
                    if(casting['status']=='rule_classified'&&casting['angle_change_measured']==false)
                      Padding(padding:const EdgeInsets.all(16),child:Text('초기 다운스윙 대표 각도 ${(casting['early_down_angle_deg'] as num).toStringAsFixed(1)}° · 연속 ${casting['observation_count']}장면\n탑 각도와 실제 릴리즈 시작 시점은 추정하지 않았습니다.')),
                    if((casting['status']=='rule_classified'||casting['status']=='experimental_observation')&&casting['angle_change_measured']!=false)
                      Padding(padding:const EdgeInsets.all(16),child:Text(
                        '탑 ${(casting['top_angle_deg'] as num).toStringAsFixed(1)}° → 골반 높이 ${(casting['halfway_angle_deg'] as num).toStringAsFixed(1)}°\n'
                        '${casting['status']=='rule_classified'?'앱 기준: 120° 이상이면서 20° 이상 일찍 벌어지면 캐스팅 의심으로 표시합니다.':'영상에서 관찰한 투영각이며 판정에 쓸 품질 조건은 충족하지 못했습니다.'}')),
                    TextButton(onPressed: () => Navigator.push(context, MaterialPageRoute(
                      builder: (_) => const ClubTrackReviewScreen(nearGrip: true))),
                      child: const Text('전완과 샤프트 확인')),
                  ]),
              if (clubTrack != null)
                ExpansionTile(title: const Text('오버더탑 · 샤프트 비교'),
                  subtitle: Text(clubTrack['status']=='rule_classified'?clubTrack['label'] as String:'연속 샤프트 확인 필요'), children: [
                    Padding(padding: const EdgeInsets.all(16), child: Text(
                      clubTrack['status']=='rule_classified'
                      ? '백스윙 기준선과 다운스윙 ${clubTrack['observation_count']}장면을 자동 비교했습니다. 몸통 길이 대비 바깥 이동 5%부터 주의, 10%부터 오버더탑 의심으로 표시하는 앱 기준입니다.'
                      : '백스윙 기준선과 연속 다운스윙 샤프트를 확보하지 못했습니다. 추적이 부족하면 정상으로 표시하지 않습니다.')),
                    TextButton(onPressed: () => Navigator.push(context, MaterialPageRoute(
                      builder: (_) => const OverTopReviewScreen())), child: const Text('백스윙·다운스윙 비교')),
                    TextButton(onPressed: () => Navigator.push(context, MaterialPageRoute(
                      builder: (_) => const ClubTrackReviewScreen())), child: const Text('영상에 추적선 표시')),
                  ]),
              const Text('관련 자료와 연습 안내'),
              for (final resource
                  in provider.currentCoachingContext?['resources'] as List? ??
                      [])
                Card(
                    child: ExpansionTile(
                  title: Text(resource['title'] as String),
                  subtitle: const Text('측정값에 연결한 참고 자료'),
                  children: [
                    Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(resource['text'] as String),
                              const SizedBox(height: 12),
                              Text(resource['connection'] as String),
                              const SizedBox(height: 12),
                              Text(resource['source_title'] as String),
                              TextButton(
                                  onPressed: () => _source(context,
                                      resource['source_url'] as String),
                                  child: const Text('출처 링크 복사')),
                            ]))
                  ],
                )),
              const SizedBox(height: 16),
              if (provider.currentPoseReport?['trajectory'] != null)
                Card(child: ExpansionTile(
                  title: const Text('스윙 중 머리·골반 이동'),
                  subtitle: const Text('고정 카메라 기준 · 측정된 프레임의 최대 이동'),
                  children: [
                    const Padding(padding: EdgeInsets.all(16), child: Text(
                      '어드레스의 영상상 몸통 길이 대비 비율입니다. 화면 오른쪽·아래쪽이 +이며, 배치기나 스웨이 판정은 아닙니다. 머리는 양쪽 눈이 보이는 경우에만 측정합니다.')),
                    for (final row in provider.currentPoseReport?['trajectory']?['summaries'] as List? ?? [])
                      ListTile(
                        title: Text('${const {'head_eye_midpoint': '머리', 'pelvis_midpoint': '골반', 'shoulder_midpoint': '어깨'}[row['landmark_group']]} · ${row['segment'] == 'backswing' ? '백스윙' : '다운스윙'}'),
                        subtitle: Text(row['status'] == 'observations_only'
                          ? '좌우 ${(100 * (row['dx_max_abs_signed'] as num)).toStringAsFixed(1)}% · 상하 ${(100 * (row['dy_max_abs_signed'] as num)).toStringAsFixed(1)}%\n좌우 최대 이동 시각 ${(row['dx_peak_requested_ms'] as num) / 1000}초 (요청 시각)'
                          : '관절 기록이 부족하여 최대 이동을 요약하지 않았습니다.'),
                      ),
                    if ((provider.currentPoseReport?['trajectory']?['summaries'] as List? ?? []).isEmpty)
                      const ListTile(title: Text('이동량을 계산할 관절 기록이 부족합니다.')),
                  ],
                )),
              const Text('측정 기록'),
              if (result.metrics.isEmpty)
                const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text('확인된 시간 수치가 없습니다.')),
              for (final metric in result.metrics.where((m) => m.unit != 'deg'))
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: GolfPanel(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                        Text(metric.name,
                            style: Theme.of(context).textTheme.bodyMedium),
                        const SizedBox(height: 10),
                        Text(
                            '${metric.value.toStringAsFixed(metric.unit == 'ms' ? 0 : 2)} ${metric.unit}',
                            style: Theme.of(context).textTheme.headlineLarge),
                        const SizedBox(height: 10),
                        Text(
                            '${metric.status == MetricStatus.estimated ? '수동 추정' : metric.status.name} · ${metric.evidenceTimeMs.join(', ')} ms',
                            style: Theme.of(context).textTheme.bodySmall),
                      ])),
                ),
              for (final phase in const {
                'address': '어드레스',
                'top': '백스윙 탑',
                'impact': '임팩트',
                'finish': '피니시'
              }.entries)
                Card(
                    child: ExpansionTile(
                        title: Text('${phase.value} 자세 수치'),
                        children: [
                      for (final metric in result.metrics.where(
                          (m) => m.id.endsWith('_projected_at_${phase.key}')))
                        ListTile(
                            title: Text(metric.name),
                            subtitle: const Text('2D 영상 추정값'),
                            trailing:
                                Text('${metric.value.toStringAsFixed(1)}°')),
                      for (final row
                          in (provider.currentPoseReport?['metrics'] as List? ??
                                  [])
                              .where((r) =>
                                  r['phase'] == phase.key &&
                                  r['status'] == 'unavailable'))
                        ListTile(
                            title: Text(_kindLabel(row['kind'] as String)),
                            subtitle:
                                Text(_reasonLabel(row['reason'] as String?)),
                            trailing: const Text('측정 불가')),
                    ])),
              const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Text(
                      '각도는 영상 평면 기준입니다. 몸통 기울기는 화면 수직 위쪽을 0°, 오른쪽을 +로 표시합니다. 관절 신뢰도는 각도 정확도를 보장하지 않습니다.')),
              OutlinedButton.icon(
                  onPressed: provider.currentDatasetDraft == null
                      ? null
                      : () => _export(context, provider),
                  icon: const Icon(Icons.file_download_outlined),
                  label: const Text('측정값과 참고 자료 내보내기')),
              const SizedBox(height: 16),
              Text(shot?.isTestData == true ? '테스트 예시 · 실제 샷 기록 아님' : '사용자가 확인한 스크린장 샷 기록'),
              if (shot == null || shot.ocrStatus != OcrStatus.userConfirmed)
                const Padding(
                    padding: EdgeInsets.all(16), child: Text('첨부한 샷 기록 없음'))
              else ...[
                _shot('볼스피드', shot.ballSpeedMs, 'm/s'),
                _shot('클럽스피드', shot.clubSpeedMs, 'm/s'),
                _shot('캐리', shot.carryDistanceMeters, 'm'),
                _shot('총거리', shot.totalDistanceMeters, 'm'),
                _shot('발사각', shot.launchAngleDeg, '°'),
                _shot('백스핀', shot.backSpinRpm, 'rpm'),
                _shot('사이드스핀', shot.sideSpinRpm, 'rpm'),
                _shot('스매시 팩터 · 볼스피드/클럽스피드', shot.calculatedSmashFactor, ''),
              ],
              const SizedBox(height: 16),
              const Text(
                  '현재는 측정값과 참고 자료를 연결한 설명입니다. SLM은 아직 실행하지 않으며, 설명을 교정 정답으로 자동 학습하지 않습니다.'),
              OutlinedButton(
                  onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const PoseTrimmingScreen())),
                  child: const Text('영상과 지정 시각 다시 확인')),
              ElevatedButton(
                  onPressed: () =>
                      Navigator.popUntil(context, (r) => r.isFirst),
                  child: const Text('홈으로')),
            ]),
    );
  }

  Future<void> _source(BuildContext context, String url) async {
    await Clipboard.setData(ClipboardData(text: url));
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('출처 링크를 복사했습니다. 브라우저에서 열 수 있습니다.')));
    }
  }

  static String _kindLabel(String kind) =>
      const {
        'lead_elbow': '리드 팔꿈치',
        'trail_elbow': '트레일 팔꿈치',
        'lead_knee': '리드 무릎',
        'trail_knee': '트레일 무릎',
        'torso_tilt': '몸통 기울기',
      }[kind] ??
      kind;
  static String _reasonLabel(String? reason) =>
      const {
        'events_not_confirmed': '자세 시각 확인 필요',
        'unknown_view': '촬영 방향 설정 필요',
        'frame_unavailable': '선택 시각의 영상 추출 실패',
        'requested_time_mismatch': '영상 끝 경계 등으로 요청 시각 불일치',
        'invalid_image_size': '영상 크기 확인 불가',
        'missing_or_invalid_joint': '필요한 관절 검출 실패',
        'low_joint_likelihood': '관절 검출 신뢰도 부족',
        'joint_outside_image': '관절이 화면 밖에 있음',
        'degenerate_segment': '관절 사이 영상상 거리가 너무 짧음',
      }[reason] ??
      '측정 조건 확인 필요';
  Future<void> _export(BuildContext context, SwingProvider provider) async {
    final draft = provider.currentDatasetDraft;
    if (draft == null) return;
    try {
      final saved = await const MethodChannel(
              'com.metaoffice.aigolfcoatch/frame_extractor')
          .invokeMethod<bool>('exportDataset',
              {'json': const JsonEncoder.withIndent('  ').convert(draft)});
      if (context.mounted && saved == true) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('측정값과 참고 자료 JSON을 저장했습니다. 영상 파일은 포함하지 않습니다.')));
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('내보내기에 실패했습니다. 저장 위치를 확인하고 다시 시도하세요.')));
      }
    }
  }

  Widget _shot(String label, double? value, String unit) => value == null
      ? const SizedBox.shrink()
      : ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(label),
          trailing: Text('${value.toStringAsFixed(2)} $unit'));
}
