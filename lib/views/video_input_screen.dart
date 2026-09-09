import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/swing_model.dart';
import '../providers/swing_provider.dart';
import 'ocr_input_screen.dart';

class VideoInputScreen extends StatefulWidget {
  const VideoInputScreen({super.key});

  @override
  State<VideoInputScreen> createState() => _VideoInputScreenState();
}

class _VideoInputScreenState extends State<VideoInputScreen> {
  SwingView _selectedView = SwingView.faceOn;
  Handedness _selectedHandedness = Handedness.right;
  String _selectedClub = '7i';
  String? _videoPath = '/storage/emulated/0/Download/golf_sample.mp4';

  final List<String> _clubs = ['Driver', '3W', '5i', '7i', '9i', 'PW', 'SW'];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('스윙 정보 및 영상 설정'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAlignment.start,
          children: [
            // Video Select Box
            Container(
              height: 180,
              width: double.infinity,
              decoration: BoxDecoration(
                color: Colors.grey.shade900,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.teal.shade700),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.movie_creation_outlined, size: 48, color: Colors.teal),
                  const SizedBox(height: 12),
                  Text(
                    _videoPath != null ? '선택된 영상: golf_sample.mp4' : '영상 파일 선택',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  ElevatedButton.icon(
                    onPressed: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('데모용 영상이 파일 선택되었습니다.')),
                      );
                    },
                    icon: const Icon(Icons.file_upload),
                    label: const Text('갤러리에서 불러오기'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Orientation Selection
            const Text('촬영 방향 선택', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: ChoiceChip(
                    label: const Center(child: Text('정면 (Face-on)')),
                    selected: _selectedView == SwingView.faceOn,
                    onSelected: (val) => setState(() => _selectedView = SwingView.faceOn),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ChoiceChip(
                    label: const Center(child: Text('후방 (Rear)')),
                    selected: _selectedView == SwingView.rear,
                    onSelected: (val) => setState(() => _selectedView = SwingView.rear),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // Handedness Selection
            const Text('주 타석 손 잡이', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: ChoiceChip(
                    label: const Center(child: Text('오른손잡이')),
                    selected: _selectedHandedness == Handedness.right,
                    onSelected: (val) => setState(() => _selectedHandedness = Handedness.right),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ChoiceChip(
                    label: const Center(child: Text('왼손잡이')),
                    selected: _selectedHandedness == Handedness.left,
                    onSelected: (val) => setState(() => _selectedHandedness = Handedness.left),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // Club Selection
            const Text('사용 클럽', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: _clubs.map((club) {
                return ChoiceChip(
                  label: Text(club),
                  selected: _selectedClub == club,
                  onSelected: (selected) {
                    if (selected) setState(() => _selectedClub = club);
                  },
                );
              }).toList(),
            ),
            const SizedBox(height: 36),

            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.teal,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: () {
                  final provider = Provider.of<SwingProvider>(context, listen: false);
                  provider.createNewSwing(
                    videoPath: _videoPath ?? '',
                    view: _selectedView,
                    handedness: _selectedHandedness,
                    club: _selectedClub,
                  );

                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => const OcrInputScreen()),
                  );
                },
                child: const Text('다음: 스크린 샷 OCR 추가 (선택)', style: TextStyle(fontSize: 16, color: Colors.white)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
