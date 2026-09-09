import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/swing_provider.dart';
import '../services/ocr_service.dart';
import 'analysis_result_screen.dart';

class OcrInputScreen extends StatefulWidget {
  const OcrInputScreen({super.key});

  @override
  State<OcrInputScreen> createState() => _OcrInputScreenState();
}

class _OcrInputScreenState extends State<OcrInputScreen> {
  bool _hasOcrData = false;

  void _runDemoOcr() {
    final provider = Provider.of<SwingProvider>(context, listen: false);
    if (provider.currentSwing == null) return;

    // Demo raw OCR string from screen golf equipment
    const mockRawText = '''
    Ball Speed: 60.0 m/s
    Club Speed: 40.0 m/s
    Carry: 180 m
    BackSpin: 2500 rpm
    ''';

    final measurement = OcrService.parseOcrText(mockRawText, provider.currentSwing!.swingId);
    provider.attachShotMeasurement(measurement);

    setState(() {
      _hasOcrData = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<SwingProvider>(context);
    final shotData = provider.currentShotMeasurement;

    return Scaffold(
      appBar: AppBar(
        title: const Text('스크린 결과 OCR 연동'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAlignment.start,
          children: [
            const Text(
              '스크린 타석 결과 캡처 이미지',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              '볼스피드, 헤드스피드, 비거리가 포함된 모니터 화면 사진을 추가하면 동작과 통합 분석합니다.',
              style: TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 20),

            if (!_hasOcrData)
              Center(
                child: ElevatedButton.icon(
                  onPressed: _runDemoOcr,
                  icon: const Icon(Icons.document_scanner),
                  label: const Text('스크린 캡처 OCR 자동 분석 실행'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                  ),
                ),
              )
            else if (shotData != null)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.check_circle, color: Colors.teal),
                          SizedBox(width: 8),
                          Text('OCR 추출 성공', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                        ],
                      ),
                      const Divider(height: 24),
                      Text('볼 스피드: ${shotData.ballSpeedMs} m/s (${shotData.ballSpeedMph?.toStringAsFixed(1)} mph)'),
                      Text('클럽 스피드: ${shotData.clubSpeedMs} m/s (${shotData.clubSpeedMph?.toStringAsFixed(1)} mph)'),
                      Text('스매시 팩터 (Smash Factor): ${shotData.calculatedSmashFactor}'),
                      Text('캐리 거리: ${shotData.carryDistanceMeters} m (${shotData.carryYards?.toStringAsFixed(1)} yd)'),
                    ],
                  ),
                ),
              ),

            const Spacer(),

            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.teal,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: () async {
                  await provider.runAnalysis();
                  if (context.mounted) {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => const AnalysisResultScreen()),
                    );
                  }
                },
                child: const Text('통합 분석 시작', style: TextStyle(fontSize: 16, color: Colors.white)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
