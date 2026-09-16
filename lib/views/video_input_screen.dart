import 'dart:io';
import 'package:flutter/material.dart';
import '../widgets/golf_widgets.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import '../models/swing_model.dart';
import '../providers/swing_provider.dart';
import '../theme/app_theme.dart';
import '../services/gallery_pose_service.dart';
import 'pose_trimming_screen.dart';
import 'live_camera_recording_screen.dart';

class VideoInputScreen extends StatefulWidget {
  const VideoInputScreen({super.key});
  @override
  State<VideoInputScreen> createState() => _VideoInputScreenState();
}
class _VideoInputScreenState extends State<VideoInputScreen> {
  SwingView _view = SwingView.faceOn;
  Handedness _hand = Handedness.right;
  String _club = '7i';
  String? _video;
  bool _busy = false;

  Widget _buildChip({
    required String label,
    required bool selected,
    required VoidCallback onSelected,
  }) {
    return ChoiceChip(
      label: Text(
        label,
        style: TextStyle(
          color: selected ? const Color(0xFF12291D) : const Color(0xFFF2F5F1),
          fontWeight: selected ? FontWeight.bold : FontWeight.w500,
        ),
      ),
      selected: selected,
      onSelected: (_) => onSelected(),
      selectedColor: AppTheme.mint,
      backgroundColor: const Color(0xFF1A2420),
      checkmarkColor: const Color(0xFF12291D),
      side: BorderSide(
        color: selected ? AppTheme.mint : const Color(0xFF40534A),
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
    );
  }

  Future<void> _pick() async {
    setState(() => _busy = true);
    try {
      final file = await ImagePicker().pickVideo(source: ImageSource.gallery);
      if (file == null) return;
      if (!await File(file.path).exists()) throw StateError('영상 파일을 찾지 못했습니다.');
      if (mounted) setState(() => _video = file.path);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('영상 선택 실패: $e')));
    } finally { if (mounted) setState(() => _busy = false); }
  }

  Future<void> _open(bool camera) async {
    if (!camera && _video == null) return;

    if (!camera) {
      double currentProgress = 0.05;
      String currentStatus = '갤러리 영상 관절 스캔 준비 중…';
      void Function(void Function())? refreshDialog;

      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => StatefulBuilder(
          builder: (context, setDialogState) {
            refreshDialog = setDialogState;
            return AlertDialog(
              backgroundColor: const Color(0xFF1E2B25),
              title: const Row(
                children: [
                  Icon(Icons.auto_awesome, color: AppTheme.mint),
                  SizedBox(width: 8),
                  Text('갤러리 스윙 분석 중', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(currentStatus, style: const TextStyle(color: AppTheme.mint, fontSize: 13)),
                  const SizedBox(height: 12),
                  LinearProgressIndicator(value: currentProgress, color: AppTheme.mint, backgroundColor: Colors.white12),
                  const SizedBox(height: 8),
                  Text('${(currentProgress * 100).toInt()}% 완료', style: const TextStyle(color: Colors.white70, fontSize: 12)),
                ],
              ),
            );
          },
        ),
      );

      final analyzed = await GalleryPoseService.analyzeGalleryVideo(
        videoPath: _video!,
        onProgress: (p, s) {
          if (!mounted) return;
          refreshDialog?.call(() {
            currentProgress = p;
            currentStatus = s;
          });
        },
      );

      if (mounted) Navigator.of(context, rootNavigator: true).pop();
      if (mounted && !analyzed) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('관절 스캔에 실패했습니다. 영상은 열리지만 자동 후보 시각 정확도는 낮을 수 있습니다.')),
        );
      }
    }

    if (!mounted) return;
    context.read<SwingProvider>().createNewSwing(
      videoPath: camera ? '' : _video!,
      view: _view,
      handedness: _hand,
      club: _club,
    );

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => camera ? const LiveCameraRecordingScreen() : const PoseTrimmingScreen(),
      ),
    );
  }
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('스윙 영상 준비')),
    body: ListView(padding: const EdgeInsets.all(20), children: [
      const GolfStepHeader(step: 1, title: '스윙을 준비하세요', description: '촬영 방향과 클럽을 선택한 뒤 영상을 준비합니다.'),
      const SizedBox(height: 12),
      const Text('촬영 방향', style: TextStyle(fontWeight: FontWeight.bold)),
      const SizedBox(height: 8),
      Wrap(spacing: 8, children: [
        _buildChip(label: '정면', selected: _view == SwingView.faceOn,
          onSelected: () => setState(() => _view = SwingView.faceOn)),
        _buildChip(label: '후방', selected: _view == SwingView.rear,
          onSelected: () => setState(() => _view = SwingView.rear)),
      ]),
      const SizedBox(height: 16),
      const Text('주사용 손', style: TextStyle(fontWeight: FontWeight.bold)),
      const SizedBox(height: 8),
      Wrap(spacing: 8, children: [
        _buildChip(label: '오른손', selected: _hand == Handedness.right,
          onSelected: () => setState(() => _hand = Handedness.right)),
        _buildChip(label: '왼손', selected: _hand == Handedness.left,
          onSelected: () => setState(() => _hand = Handedness.left)),
      ]),
      const SizedBox(height: 16),
      const Text('클럽', style: TextStyle(fontWeight: FontWeight.bold)),
      const SizedBox(height: 8),
      Wrap(spacing: 8, runSpacing: 8, children: [
        'Driver', '3W', '5W', 'Utility',
        '4i', '5i', '6i', '7i', '8i', '9i',
        'PW', 'AW', 'SW'
      ].map((c) =>
        _buildChip(label: c, selected: _club == c,
          onSelected: () => setState(() => _club = c))).toList()),
      const SizedBox(height: 24),
      ElevatedButton.icon(onPressed: _busy ? null : () => _open(true),
        icon: const Icon(Icons.videocam), label: const Text('카메라 촬영 · 관절 표시')),
      const SizedBox(height: 12),
      OutlinedButton.icon(onPressed: _busy ? null : _pick,
        icon: const Icon(Icons.video_library), label: Text(_busy ? '선택 중…' : '갤러리 영상 가져오기')),
      if (_video != null) ...[
        const SizedBox(height: 8),
        Text('선택한 영상: ${_video!.split('/').last}'),
      ],
      const SizedBox(height: 12),
      const Text('전신이 보이도록 촬영하거나 갤러리 영상을 선택하세요. 선택 시 온디바이스 AI가 관절 궤적 및 어드레스·탑·임팩트·피니시 4구간을 자동 추출합니다.'),
      const SizedBox(height: 24),
      ElevatedButton(onPressed: _video == null || _busy ? null : () => _open(false),
        child: const Text('선택한 영상 확인')),
    ]),
  );
}
