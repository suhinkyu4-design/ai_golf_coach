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

  Widget _buildHighContrastChip({
    required String label,
    required bool selected,
    required VoidCallback onSelected,
  }) {
    return ChoiceChip(
      label: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.white : Colors.white90,
            fontWeight: selected ? FontWeight.bold : FontWeight.w500,
            fontSize: 14,
          ),
        ),
      ),
      selected: selected,
      onSelected: (_) => onSelected(),
      selectedColor: Colors.teal,
      backgroundColor: const Color(0xFF2C2C2C),
      side: BorderSide(
        color: selected ? Colors.tealAccent : Colors.grey.shade700,
        width: selected ? 1.5 : 1.0,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      showCheckmark: false,
    );
  }

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
                color: const Color(0xFF1E1E1E),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.teal.shade600, width: 1.5),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.movie_creation_outlined, size: 48, color: Colors.tealAccent),
                  const SizedBox(height: 12),
                  Text(
                    _videoPath != null ? 'Selected: golf_sample.mp4' : 'Select Video File',
                    style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                  const SizedBox(height: 8),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.teal,
                      foregroundColor: Colors.white,
                    ),
                    onPressed: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Demo video selected.')),
                      );
                    },
                    icon: const Icon(Icons.file_upload, color: Colors.white),
                    label: Text(
                      LocalizationService.tr('select_video_btn', lang),
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Orientation Selection
            Text(
              LocalizationService.tr('select_orientation', lang),
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.white),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _buildHighContrastChip(
                    label: LocalizationService.tr('face_on', lang),
                    selected: _selectedView == SwingView.faceOn,
                    onSelected: () => setState(() => _selectedView = SwingView.faceOn),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildHighContrastChip(
                    label: LocalizationService.tr('rear', lang),
                    selected: _selectedView == SwingView.rear,
                    onSelected: () => setState(() => _selectedView = SwingView.rear),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),

            // Handedness Selection
            Text(
              LocalizationService.tr('handedness', lang),
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.white),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _buildHighContrastChip(
                    label: LocalizationService.tr('right_handed', lang),
                    selected: _selectedHandedness == Handedness.right,
                    onSelected: () => setState(() => _selectedHandedness = Handedness.right),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildHighContrastChip(
                    label: LocalizationService.tr('left_handed', lang),
                    selected: _selectedHandedness == Handedness.left,
                    onSelected: () => setState(() => _selectedHandedness = Handedness.left),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),

            // Club Selection
            Text(
              LocalizationService.tr('club_used', lang),
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.white),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: _clubs.map((club) {
                return _buildHighContrastChip(
                  label: club,
                  selected: _selectedClub == club,
                  onSelected: () => setState(() => _selectedClub = club),
                );
              }).toList(),
            ),
            const SizedBox(height: 36),

            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.teal,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  elevation: 2,
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
                child: Text(
                  LocalizationService.tr('next_ocr', lang),
                  style: const TextStyle(fontSize: 16, color: Colors.white, fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
