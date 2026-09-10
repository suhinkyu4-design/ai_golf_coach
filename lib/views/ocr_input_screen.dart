import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/swing_provider.dart';
import '../services/ocr_service.dart';
import '../services/localization_service.dart';
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
    final lang = provider.appLanguage;
    final shotData = provider.currentShotMeasurement;

    return Scaffold(
      appBar: AppBar(
        title: Text(LocalizationService.tr('ocr_title', lang)),
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAlignment.start,
          children: [
            Text(
              LocalizationService.tr('ocr_title', lang),
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              LocalizationService.tr('ocr_desc', lang),
              style: const TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 20),

            if (!_hasOcrData)
              Center(
                child: ElevatedButton.icon(
                  onPressed: _runDemoOcr,
                  icon: const Icon(Icons.document_scanner),
                  label: Text(LocalizationService.tr('ocr_btn', lang)),
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
                      Row(
                        children: [
                          const Icon(Icons.check_circle, color: Colors.teal),
                          const SizedBox(width: 8),
                          Text(LocalizationService.tr('ocr_success', lang), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                        ],
                      ),
                      const Divider(height: 24),
                      Text('${LocalizationService.tr('ball_speed', lang)}: ${shotData.ballSpeedMs} m/s (${shotData.ballSpeedMph?.toStringAsFixed(1)} mph)'),
                      Text('${LocalizationService.tr('club_speed', lang)}: ${shotData.clubSpeedMs} m/s (${shotData.clubSpeedMph?.toStringAsFixed(1)} mph)'),
                      Text('${LocalizationService.tr('smash_factor', lang)}: ${shotData.calculatedSmashFactor}'),
                      Text('${LocalizationService.tr('carry_dist', lang)}: ${shotData.carryDistanceMeters} m (${shotData.carryYards?.toStringAsFixed(1)} yd)'),
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
                child: Text(LocalizationService.tr('start_analysis', lang), style: const TextStyle(fontSize: 16, color: Colors.white)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
