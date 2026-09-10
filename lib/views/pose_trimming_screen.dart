import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/swing_provider.dart';
import '../services/localization_service.dart';
import 'ocr_input_screen.dart';

class PoseTrimmingScreen extends StatefulWidget {
  const PoseTrimmingScreen({super.key});

  @override
  State<PoseTrimmingScreen> createState() => _PoseTrimmingScreenState();
}

class _PoseTrimmingScreenState extends State<PoseTrimmingScreen> {
  RangeValues _trimRange = const RangeValues(200, 2800);
  int _addressMs = 200;
  int _topMs = 1200;
  int _impactMs = 1510;
  int _finishMs = 2800;

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<SwingProvider>(context);
    final lang = provider.appLanguage;
    final isEn = lang == AppLanguage.english;
    final swing = provider.currentSwing;

    return Scaffold(
      appBar: AppBar(
        title: Text(isEn ? 'Swing Trimming & Events' : '스윙 구간 및 이벤트 확인'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Skeleton Overlay Video Preview Placeholder
            Container(
              height: 240,
              width: double.infinity,
              decoration: BoxDecoration(
                color: Colors.black,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.tealAccent, width: 2),
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  const Icon(Icons.sports_golf, size: 80, color: Colors.teal),
                  // Skeleton Joints Simulation Overlay
                  Positioned(
                    top: 40,
                    child: Column(
                      children: [
                        const CircleAvatar(radius: 8, backgroundColor: Colors.amber), // Head
                        Container(width: 2, height: 40, color: Colors.tealAccent), // Spine
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(width: 30, height: 2, color: Colors.tealAccent), // Shoulders
                            Container(width: 30, height: 2, color: Colors.tealAccent),
                          ],
                        ),
                      ],
                    ),
                  ),
                  Positioned(
                    bottom: 12,
                    left: 12,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.7),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        isEn ? 'MediaPipe Pose Skeleton Overlay' : 'MediaPipe 포즈 스켈레톤 라이브 추적 중',
                        style: const TextStyle(color: Colors.tealAccent, fontSize: 12, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Trimming Slider Box
            Text(
              isEn ? '1. Swing Section Trimming (0.5s ~ 3s)' : '1. 스윙 구간 자르기 (어드레스 ~ 피니시)',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 8),
            RangeSlider(
              values: _trimRange,
              min: 0,
              max: 3000,
              divisions: 60,
              activeColor: Colors.teal,
              labels: RangeLabels(
                '${(_trimRange.start / 1000).toStringAsFixed(1)}s',
                '${(_trimRange.end / 1000).toStringAsFixed(1)}s',
              ),
              onChanged: (values) {
                setState(() {
                  _trimRange = values;
                });
              },
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '${isEn ? 'Start' : '시작'}: ${(_trimRange.start / 1000).toStringAsFixed(2)}s',
                  style: const TextStyle(color: Colors.grey),
                ),
                Text(
                  '${isEn ? 'End' : '종료'}: ${(_trimRange.end / 1000).toStringAsFixed(2)}s',
                  style: const TextStyle(color: Colors.grey),
                ),
              ],
            ),
            const SizedBox(height: 24),

            // 4-Event Markers
            Text(
              isEn ? '2. Key Swing Events Frame Markers' : '2. 4대 스윙 구간 이벤트 타임스탬프',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 12),

            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  children: [
                    _buildEventRow(isEn ? 'Address Frame' : '어드레스 (Address)', _addressMs, (ms) => setState(() => _addressMs = ms)),
                    const Divider(),
                    _buildEventRow(isEn ? 'Top of Backswing' : '백스윙 탑 (Top)', _topMs, (ms) => setState(() => _topMs = ms)),
                    const Divider(),
                    _buildEventRow(isEn ? 'Estimated Impact' : '임팩트 추정 (Impact)', _impactMs, (ms) => setState(() => _impactMs = ms)),
                    const Divider(),
                    _buildEventRow(isEn ? 'Finish Hold' : '피니시 유지 (Finish)', _finishMs, (ms) => setState(() => _finishMs = ms)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 30),

            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.teal,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: () {
                  if (swing != null) {
                    swing.eventsMs['address'] = _addressMs;
                    swing.eventsMs['top'] = _topMs;
                    swing.eventsMs['impact'] = _impactMs;
                    swing.eventsMs['finish'] = _finishMs;
                  }

                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => const OcrInputScreen()),
                  );
                },
                child: Text(
                  isEn ? 'Next: Attach Screen OCR' : '다음: 스크린 샷 OCR 연동 (선택)',
                  style: const TextStyle(fontSize: 16, color: Colors.white, fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEventRow(String title, int timeMs, Function(int) onChange) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          child: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        ),
        Row(
          children: [
            IconButton(
              icon: const Icon(Icons.remove_circle_outline, size: 20, color: Colors.grey),
              onPressed: () => onChange((timeMs - 16).clamp(0, 3000)),
            ),
            Text('${timeMs} ms', style: const TextStyle(color: Colors.tealAccent, fontWeight: FontWeight.bold)),
            IconButton(
              icon: const Icon(Icons.add_circle_outline, size: 20, color: Colors.teal),
              onPressed: () => onChange((timeMs + 16).clamp(0, 3000)),
            ),
          ],
        ),
      ],
    );
  }
}
