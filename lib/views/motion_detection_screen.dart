import '../widgets/coach_app_bar.dart';
import 'dart:io';
import 'package:flutter/material.dart';
import 'over_top_review_screen.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';
import '../providers/swing_provider.dart';
import '../services/video_orientation_service.dart';

class MotionDetectionScreen extends StatefulWidget {
  const MotionDetectionScreen({super.key});
  @override
  State<MotionDetectionScreen> createState() => _MotionDetectionScreenState();
}

class _MotionDetectionScreenState extends State<MotionDetectionScreen> {
  VideoPlayerController? _player;
  String? _error;
  int _rotationTurns = 0;
  String? _selected;
  @override
  void initState() {
    super.initState();
    final path = context.read<SwingProvider>().currentSwing?.videoPath;
    if (path != null) _open(path);
  }

  Future<void> _open(String path) async {
    final p = VideoPlayerController.file(File(path));
    _player = p;
    try {
      await p.initialize();
      _rotationTurns = await VideoOrientationService.read(path);
      if (mounted) setState(() {});
    } catch (_) {
      if (mounted) setState(() => _error = '원본 영상을 열지 못했습니다.');
    }
  }

  @override
  void dispose() {
    _player?.dispose();
    super.dispose();
  }

  Future<void> _seek(int time) async {
    final p = _player;
    if (p == null || !p.value.isInitialized) return;
    await p.pause();
    await p.seekTo(Duration(milliseconds: time));
    if (mounted) setState(() {});
  }

  static const reasons = {
    'foot_length_unavailable': '발 길이를 확인하지 못했습니다. 발끝과 뒤꿈치가 보이는 영상으로 다시 분석해 주세요.',
    'projected_reference_width_too_small': '머리는 검출됐지만 귀·어깨가 겹쳐 비교 기준 너비가 부족합니다.',
    'head_width_unavailable': '머리 너비를 확인할 수 없습니다. 새로 분석하거나 머리가 선명한 영상을 사용해 주세요.',
    'unsupported_club': '드라이버·7번 아이언만 지원합니다.',
    'reviewed_events_required': '어드레스·탑·임팩트·피니시 시각을 확인해 주세요.',
    'different_view_required': '촬영 방향 제한 · 현재 구현은 이 방향을 지원하지 않습니다.',
    'baseline_unavailable': '어드레스의 몸통 관절이 선명하지 않습니다.',
    'target_direction_unknown': '타깃 방향을 확인할 수 없습니다.',
    'ball_direction_unknown': '방향 정보 미지정 · 위에서 공 방향을 선택하면 계산합니다.',
    'verified_club_track_required': '클럽 후보 검증 중 · 확정된 클럽 궤적이 필요합니다.',
    'insufficient_joint_samples': '관절 검출 부족 · 해당 구간의 선명한 관절 기록이 필요합니다.',
    'sampling_gaps_too_large': '프레임 간격이 넓어 연속 변화를 확인할 수 없습니다.',
  };
  @override
  Widget build(BuildContext context) {
    final provider = context.watch<SwingProvider>();
    final report = provider.currentPoseReport?['fault_features'] as Map?;
    final rows = report?['patterns'] as List? ?? [];
    final extension = report?['early_extension_check'] as Map?;
    final headUp = report?['head_up_check'] as Map?;
    final chicken = report?['chicken_wing_check'] as Map?;
    final standing = report?['standing_up_check'] as Map?;
    final overTop = report?['over_the_top_check'] as Map?;
    final headCheck = report?['head_trail_check'] as Map?;
    final p = _player;
    return Scaffold(
      appBar: CoachAppBar(title: const Text('스윙 다시 보기')),
      body: ListView(padding: const EdgeInsets.all(20), children: [
        const Text('영상으로 확인하기',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        const Text('스웨이·얼리 스탠드업·배치기·치킨윙 판정을 영상에서 확인하세요.'),
        const SizedBox(height: 8),
        const SizedBox(height: 16),
        if (_error != null) Text(_error!),
        if (p != null && p.value.isInitialized) ...[
          SizedBox(
              height: 280,
              child: Center(
                  child: AspectRatio(
                      aspectRatio: _rotationTurns.isOdd ? 1 / p.value.aspectRatio : p.value.aspectRatio,
                      child: RotatedBox(quarterTurns: _rotationTurns, child: VideoPlayer(p))))),
          ValueListenableBuilder<VideoPlayerValue>(
              valueListenable: p,
              builder: (context, value, _) => Column(children: [
                    Slider(
                        value: value.position.inMilliseconds.toDouble().clamp(
                            0.0, value.duration.inMilliseconds.toDouble()),
                        max: value.duration.inMilliseconds.toDouble() > 0
                            ? value.duration.inMilliseconds.toDouble()
                            : 1,
                        onChanged: (v) => _seek(v.round())),
                    Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                      IconButton(
                          onPressed: () => _seek(
                              (value.position.inMilliseconds - 33)
                                  .clamp(0, value.duration.inMilliseconds)),
                          icon: const Icon(Icons.chevron_left)),
                      IconButton(
                          onPressed: () =>
                              value.isPlaying ? p.pause() : p.play(),
                          icon: Icon(value.isPlaying
                              ? Icons.pause
                              : Icons.play_arrow)),
                      IconButton(
                          onPressed: () => _seek(
                              (value.position.inMilliseconds + 33)
                                  .clamp(0, value.duration.inMilliseconds)),
                          icon: const Icon(Icons.chevron_right)),
                      Text(
                          '${(value.position.inMilliseconds / 1000).toStringAsFixed(3)}초'),
                    ]),
                  ])),
        ],
        const SizedBox(height: 16),
        if (headCheck != null)
          Card(child: ExpansionTile(
            title: const Text('스웨이 판정'),
            subtitle: Text(headCheck['status'] == 'rule_classified'
              ? headCheck['label'] as String
              : reasons[headCheck['reason']] ?? '측정 불가'),
            children: [Padding(padding: const EdgeInsets.all(16), child: Column(
              crossAxisAlignment: CrossAxisAlignment.start, children: [
                if (headCheck['head_position_measured'] == true)
                  Text('머리 가로 이동 ${(headCheck["horizontal_displacement_px"] as num).abs().toStringAsFixed(1)}px · 영상 좌표 기준'),
                if (headCheck['value'] is num)
                  Text('어드레스 → 탑: ${((headCheck['value'] as num) * 100).toStringAsFixed(1)}%'),
                const Text('어드레스 대비 탑에서 타깃 반대쪽 머리 이동. 머리 너비는 어드레스의 양 귀 간격으로 추정합니다.'),
                Text(headCheck['normalization'] == 'address_projected_shoulder_width'
                  ? '어깨 너비 기준: 7% 미만 기준 이내 · 7~12% 미만 주의 · 12% 이상 스웨이 감지'
                  : '머리 너비 기준: 25% 미만 기준 이내 · 25~50% 미만 주의 · 50% 이상 스웨이 감지'),
                if (headCheck['t_ms'] is int)
                  TextButton(onPressed: () => _seek(headCheck['t_ms'] as int), child: const Text('백스윙 탑 확인')),
              ]))],
          )),
        if (extension != null)
          Card(child: ExpansionTile(title: const Text('배치기 판정'),
            subtitle: Text(extension['status'] == 'rule_classified' ? extension['label'] as String : reasons[extension['reason']] ?? '측정 불가'),
            children: [Padding(padding: const EdgeInsets.all(16), child: Column(
              crossAxisAlignment: CrossAxisAlignment.start, children: [
                if (extension['value'] is num) Text('임팩트 골반 이동: 발 길이의 ${((extension['value'] as num) * 100).toStringAsFixed(1)}%'),
                const Text('10% 미만 기준 이내 · 10~25% 미만 주의 · 25% 이상 감지'),
                const Text('엉덩이 외곽선 대신 골반 관절 중심 이동을 사용한 근사 판정입니다.'),
                if (extension['torso_tilt_reduction_deg'] is num)
                  Text('임팩트 상체 기울기 감소: ${(extension['torso_tilt_reduction_deg'] as num).toStringAsFixed(1)}°'),
                if (extension['t_ms'] is int) TextButton(onPressed: () => _seek(extension['t_ms'] as int), child: const Text('임팩트 확인')),
              ]))])),
        if (headUp != null)
          Card(child: ExpansionTile(title: const Text('헤드업 판정'),
            subtitle: Text(headUp['status']=='rule_classified'?headUp['label'] as String:reasons[headUp['reason']]??'측정 불가'),
            children:[Padding(padding:const EdgeInsets.all(16),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
              if(headUp['value'] is num)Text('머리 상승: 몸통 길이의 ${((headUp['value'] as num)*100).toStringAsFixed(1)}%'),
              const Text('10% 미만 기준 이내 · 10~20% 미만 주의 · 20% 이상 감지'),
              const Text('어드레스보다 높아진 머리 위치로 판단합니다. 시선이나 고개 회전은 측정하지 않습니다.'),
              if(headUp['t_ms'] is int)TextButton(onPressed:()=>_seek(headUp['t_ms'] as int),child:const Text('해당 장면 보기')),
            ]))])),
        if(overTop!=null)
          Card(child:ListTile(title:const Text('오버더탑'),
            subtitle:Text(overTop['status']=='rule_classified'?overTop['label'] as String:'연속 샤프트 추적 부족'),
            trailing:const Icon(Icons.chevron_right),
            onTap:()=>Navigator.push(context,MaterialPageRoute(builder:(_)=>const OverTopReviewScreen())))),
        if (rows.isEmpty) const Text('영상을 새로 분석하면 동작별 측정 근거가 표시됩니다.'),
        for (final row in rows.where((r) => r['id'] != 'sway' && r['id'] != 'early_extension' && r['status'] == 'measured_not_classified'))
          Card(
              child: ExpansionTile(
            key: ValueKey('${row['id']}_${row['status']}'),
            title: Text(row['label'] as String),
            subtitle: Text(row['id'] == 'chicken_wing' && chicken?['status'] == 'rule_classified'
                ? chicken!['label'] as String
                : row['id'] == 'standing_up' && standing?['status'] == 'rule_classified'
                ? standing!['label'] as String
                : row['status'] == 'measured_not_classified'
                ? '변화량 보기'
                : reasons[row['reason']] ?? '추가 검증이 필요합니다.'),
            children: [
              if (row['peak'] is Map)
                Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                              '${row['metric']}: ${(row['peak']['value'] as num).toStringAsFixed(3)} ${row['unit'] == 'deg' ? '°' : '몸통 길이 비율'}'),
                          Text(row['id'] == 'standing_up'
                            ? '어드레스 대비 기울기 감소: 5° 미만 기준 이내 · 5~10° 미만 주의 · 10° 이상 감지'
                            : row['id'] == 'chicken_wing'
                              ? '임팩트 직후 0.15초: 15° 미만 기준 이내 · 15~30° 미만 주의 · 30° 이상 감지. 팔꿈치 변화만 이용한 근사 판정입니다.'
                              : '양수는 표시된 방향의 변화입니다.'),
                          const SizedBox(height: 8),
                          TextButton(
                              onPressed: () {
                                setState(
                                    () => _selected = row['label'] as String);
                                _seek(row['peak']['t_ms'] as int);
                              },
                              child: const Text('해당 장면 보기')),
                        ])),
            ],
          )),
        if (_selected != null) Text('선택한 근거: $_selected'),
        const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Text(
                '유의사항: 스웨이·얼리 스탠드업·배치기·치킨윙은 앱 판정 기준을 적용합니다. 머리 너비 추정, 촬영 각도, 고개 회전, 카메라 흔들림에 따라 오차가 생길 수 있습니다. 기준 이내가 스윙 전체의 정상을 뜻하지는 않습니다.')),
      ]),
    );
  }
}
