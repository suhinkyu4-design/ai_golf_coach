import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/swing_model.dart';
import '../providers/swing_provider.dart';
import '../services/localization_service.dart';
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
  final String? _videoPath = '/storage/emulated/0/Download/golf_sample.mp4';

  final List<String> _clubs = ['Driver', '3W', '5i', '7i', '9i', 'PW', 'SW'];

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<SwingProvider>(context);
    final lang = provider.appLanguage;

    return Scaffold(
      appBar: AppBar(
        title: Text(LocalizationService.tr('video_setting_title', lang)),
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
                    _videoPath != null ? 'Selected: golf_sample.mp4' : 'Select Video File',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  ElevatedButton.icon(
                    onPressed: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Demo video selected.')),
                      );
                    },
                    icon: const Icon(Icons.file_upload),
                    label: Text(LocalizationService.tr('select_video_btn', lang)),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Orientation Selection
            Text(LocalizationService.tr('select_orientation', lang), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: ChoiceChip(
                    label: Center(child: Text(LocalizationService.tr('face_on', lang))),
                    selected: _selectedView == SwingView.faceOn,
                    onSelected: (val) => setState(() => _selectedView = SwingView.faceOn),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ChoiceChip(
                    label: Center(child: Text(LocalizationService.tr('rear', lang))),
                    selected: _selectedView == SwingView.rear,
                    onSelected: (val) => setState(() => _selectedView = SwingView.rear),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // Handedness Selection
            Text(LocalizationService.tr('handedness', lang), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: ChoiceChip(
                    label: Center(child: Text(LocalizationService.tr('right_handed', lang))),
                    selected: _selectedHandedness == Handedness.right,
                    onSelected: (val) => setState(() => _selectedHandedness = Handedness.right),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ChoiceChip(
                    label: Center(child: Text(LocalizationService.tr('left_handed', lang))),
                    selected: _selectedHandedness == Handedness.left,
                    onSelected: (val) => setState(() => _selectedHandedness = Handedness.left),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // Club Selection
            Text(LocalizationService.tr('club_used', lang), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
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
                child: Text(LocalizationService.tr('next_ocr', lang), style: const TextStyle(fontSize: 15, color: Colors.white)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
