import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import '../models/swing_model.dart';
import '../providers/swing_provider.dart';
import '../services/localization_service.dart';
import 'pose_trimming_screen.dart';
import 'live_camera_recording_screen.dart';

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
  final ImagePicker _picker = ImagePicker();

  final List<String> _clubs = ['Driver', '3W', '5i', '7i', '9i', 'PW', 'SW'];

  void _selectDemoVideo({bool fromCameraAttempt = false}) {
    setState(() {
      _videoPath = '/storage/emulated/0/Download/golf_sample.mp4';
    });
    final lang = Provider.of<SwingProvider>(context, listen: false).appLanguage;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          fromCameraAttempt
              ? (lang == AppLanguage.korean
                  ? '📹 [온디바이스 시뮬레이션] 샘플 스윙 비디오(golf_sample.mp4)가 적용되었습니다.'
                  : '📹 [On-Device Demo Mode] Sample swing video (golf_sample.mp4) applied.')
              : (lang == AppLanguage.korean
                  ? '🎬 데모 스윙 비디오(golf_sample.mp4)가 선택되었습니다.'
                  : '🎬 Demo swing video (golf_sample.mp4) selected.'),
        ),
        backgroundColor: Colors.teal,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _openLiveCameraWithSkeleton() {
    final provider = Provider.of<SwingProvider>(context, listen: false);
    provider.createNewSwing(
      videoPath: _videoPath ?? '',
      view: _selectedView,
      handedness: _selectedHandedness,
      club: _selectedClub,
    );

    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const LiveCameraRecordingScreen()),
    );
  }

  Future<void> _pickVideoFromGallery() async {
    try {
      final XFile? video = await _picker.pickVideo(source: ImageSource.gallery);
      if (video != null) {
        setState(() {
          _videoPath = video.path;
        });
        if (mounted) {
          final lang = Provider.of<SwingProvider>(context, listen: false).appLanguage;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                lang == AppLanguage.korean
                    ? '📁 갤러리 영상 가져오기 완료!'
                    : '📁 Video Imported from Gallery!',
              ),
              backgroundColor: Colors.teal,
            ),
          );
        }
      } else {
        _selectDemoVideo(fromCameraAttempt: false);
      }
    } catch (e) {
      _selectDemoVideo(fromCameraAttempt: false);
    }
  }

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
            color: selected ? Colors.white : Colors.white.withOpacity(0.9),
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
    final isEn = lang == AppLanguage.english;

    return Scaffold(
      appBar: AppBar(
        title: Text(LocalizationService.tr('video_setting_title', lang)),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAlignment.start,
          children: [
            // Video Select Box with Camera Shoot & Gallery / Demo Video Selection
            Container(
              padding: const EdgeInsets.all(16),
              width: double.infinity,
              decoration: BoxDecoration(
                color: const Color(0xFF1E1E1E),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: _videoPath != null ? Colors.tealAccent : Colors.teal.shade600,
                  width: 2.0,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.teal.withOpacity(0.15),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    _videoPath != null ? Icons.check_circle_rounded : Icons.movie_creation_outlined,
                    size: 44,
                    color: _videoPath != null ? Colors.tealAccent : Colors.white70,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _videoPath != null
                        ? (lang == AppLanguage.korean
                            ? '✅ 선택된 비디오: ${_videoPath!.split('/').last}'
                            : '✅ Selected: ${_videoPath!.split('/').last}')
                        : (lang == AppLanguage.korean ? '스윙 비디오 선택 또는 라이브 촬영' : 'Select or Live Record Swing Video'),
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: _videoPath != null ? Colors.tealAccent : Colors.white,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      // Real Live Camera Shoot with Skeleton Button
                      Expanded(
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.teal.shade700,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 11),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                          onPressed: _openLiveCameraWithSkeleton,
                          icon: const Icon(Icons.videocam_rounded, color: Colors.white, size: 18),
                          label: Text(
                            lang == AppLanguage.korean ? '라이브 촬영 & 스켈레톤' : 'Live Camera & Pose',
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      // Gallery File Select Button
                      Expanded(
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.teal,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 11),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                          onPressed: _pickVideoFromGallery,
                          icon: const Icon(Icons.video_library_rounded, color: Colors.white, size: 18),
                          label: Text(
                            lang == AppLanguage.korean ? '갤러리 선택' : 'Pick Gallery',
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      // Demo Video Fallback Button
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF333333),
                          foregroundColor: Colors.tealAccent,
                          padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                            side: const BorderSide(color: Colors.tealAccent, width: 1),
                          ),
                        ),
                        onPressed: () => _selectDemoVideo(fromCameraAttempt: false),
                        child: Text(
                          lang == AppLanguage.korean ? '데모' : 'Demo',
                          style: const TextStyle(color: Colors.tealAccent, fontWeight: FontWeight.bold, fontSize: 12),
                        ),
                      ),
                    ],
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
                    MaterialPageRoute(builder: (context) => const PoseTrimmingScreen()),
                  );
                },
                child: Text(
                  isEn ? 'Next: Trimming & Key Event Markers' : '다음: 구간 자르기 및 4대 이벤트 확인',
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
