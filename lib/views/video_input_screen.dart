import 'dart:io';
import 'package:flutter/material.dart';
import '../widgets/golf_widgets.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import '../models/swing_model.dart';
import '../providers/swing_provider.dart';
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
  void _open(bool camera) {
    if (!camera && _video == null) return;
    context.read<SwingProvider>().createNewSwing(videoPath: camera ? '' : _video!,
      view: _view, handedness: _hand, club: _club);
    Navigator.push(context, MaterialPageRoute(builder: (_) => camera
      ? const LiveCameraRecordingScreen() : const PoseTrimmingScreen()));
  }
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('스윙 영상 준비')),
    body: ListView(padding: const EdgeInsets.all(20), children: [
      const GolfStepHeader(step: 1, title: '스윙을 준비하세요', description: '촬영 방향과 클럽을 선택한 뒤 영상을 준비합니다.'),
      const Text('촬영 방향'),
      Wrap(spacing: 8, children: [
        ChoiceChip(label: const Text('정면'), selected: _view == SwingView.faceOn,
          onSelected: (_) => setState(() => _view = SwingView.faceOn)),
        ChoiceChip(label: const Text('후방'), selected: _view == SwingView.rear,
          onSelected: (_) => setState(() => _view = SwingView.rear)),
      ]),
      const SizedBox(height: 16), const Text('주사용 손'),
      Wrap(spacing: 8, children: [
        ChoiceChip(label: const Text('오른손'), selected: _hand == Handedness.right,
          onSelected: (_) => setState(() => _hand = Handedness.right)),
        ChoiceChip(label: const Text('왼손'), selected: _hand == Handedness.left,
          onSelected: (_) => setState(() => _hand = Handedness.left)),
      ]),
      const SizedBox(height: 16), const Text('클럽'),
      Wrap(spacing: 8, children: ['Driver','3W','5i','7i','9i','PW','SW'].map((c) =>
        ChoiceChip(label: Text(c), selected: _club == c,
          onSelected: (_) => setState(() => _club = c))).toList()),
      const SizedBox(height: 24),
      ElevatedButton.icon(onPressed: _busy ? null : () => _open(true),
        icon: const Icon(Icons.videocam), label: const Text('카메라 촬영 · 관절 표시')),
      OutlinedButton.icon(onPressed: _busy ? null : _pick,
        icon: const Icon(Icons.video_library), label: Text(_busy ? '선택 중…' : '갤러리 영상 가져오기')),
      if (_video != null) Text('선택한 영상: ${_video!.split('/').last}'),
      const SizedBox(height: 12),
      const Text('전신이 보이도록 촬영하세요. 외부 영상은 현재 재생과 수동 구간 지정이 가능하며, 관절 자동 추출은 아직 연결되지 않았습니다.'),
      const SizedBox(height: 24),
      ElevatedButton(onPressed: _video == null || _busy ? null : () => _open(false),
        child: const Text('선택한 영상 확인')),
    ]),
  );
}
