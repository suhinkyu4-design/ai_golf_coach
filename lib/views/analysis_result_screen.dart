import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/swing_provider.dart';
import '../services/localization_service.dart';

class AnalysisResultScreen extends StatelessWidget {
  const AnalysisResultScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<SwingProvider>(context);
    final lang = provider.appLanguage;
    final result = provider.currentAnalysisResult;
    final swing = provider.currentSwing;
    final shotData = provider.currentShotMeasurement;

    if (result == null || swing == null) {
      return Scaffold(
        appBar: AppBar(title: Text(LocalizationService.tr('analysis_result_title', lang))),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(LocalizationService.tr('analysis_result_title', lang)),
        actions: [
          // Language Switch Toggle Button
          TextButton.icon(
            onPressed: () {
              provider.toggleLanguage();
            },
            icon: const Icon(Icons.language, color: Colors.tealAccent, size: 20),
            label: Text(
              lang == AppLanguage.korean ? '🇰🇷 KR' : '🇺🇸 EN',
              style: const TextStyle(color: Colors.tealAccent, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAlignment.start,
          children: [
            // Header Info Card
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Theme.of(context).cardColor,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.teal.shade800),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAlignment.start,
                    children: [
                      Text('${swing.club} Swing', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                      Text('${LocalizationService.tr('select_orientation', lang)}: ${swing.view.name} | ${swing.handedness.name}'),
                    ],
                  ),
                  Chip(
                    label: Text('Schema ${result.schemaVersion}'),
                    backgroundColor: Colors.teal.withOpacity(0.2),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // AI Korean/English Coaching Summary Box
            Text(LocalizationService.tr('key_summary', lang), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.teal.shade900.withOpacity(0.3),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.teal),
              ),
              child: Text(
                result.koreanSummary,
                style: const TextStyle(fontSize: 15, height: 1.5),
              ),
            ),
            const SizedBox(height: 24),

            // Measured Key Metrics Table
            Text(LocalizationService.tr('metrics_report', lang), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Card(
              child: Column(
                children: [
                  ...result.metrics.map((metric) {
                    return ListTile(
                      title: Text(metric.name),
                      subtitle: Text('Evidence ms: ${metric.evidenceTimeMs.join(', ')} ms'),
                      trailing: Text(
                        '${metric.value} ${metric.unit}',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.teal),
                      ),
                    );
                  }),
                  if (shotData != null && shotData.calculatedSmashFactor != null)
                    ListTile(
                      title: Text(LocalizationService.tr('smash_factor', lang)),
                      subtitle: const Text('Ball Speed ÷ Club Speed'),
                      trailing: Text(
                        '${shotData.calculatedSmashFactor}',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.amber),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Actionable Drill Recommendation Card
            Text(LocalizationService.tr('recommended_drill', lang), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.amber.shade900.withOpacity(0.25),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.amber),
              ),
              child: Column(
                crossAxisAlignment: CrossAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.fitness_center, color: Colors.amber),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          result.primaryDrillTitle,
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.amber),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    result.primaryDrillDescription,
                    style: const TextStyle(fontSize: 14, height: 1.4),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 30),

            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.teal),
                onPressed: () {
                  Navigator.popUntil(context, (route) => route.isFirst);
                },
                child: Text(LocalizationService.tr('back_to_home', lang), style: const TextStyle(color: Colors.white, fontSize: 16)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
