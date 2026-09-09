import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/swing_provider.dart';

class AnalysisResultScreen extends StatelessWidget {
  const AnalysisResultScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<SwingProvider>(context);
    final result = provider.currentAnalysisResult;
    final swing = provider.currentSwing;
    final shotData = provider.currentShotMeasurement;

    if (result == null || swing == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('분석 결과')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('스윙 분석 결과'),
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
                      Text('${swing.club} 클럽 스윙', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                      Text('촬영 방향: ${swing.view.name} | ${swing.handedness.name}'),
                    ],
                  ),
                  Chip(
                    label: Text('버전 ${result.schemaVersion}'),
                    backgroundColor: Colors.teal.withOpacity(0.2),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // AI Korean Coaching Summary Box
            const Text('핵심 관찰 요약', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
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
            const Text('측정 수치 리포트', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Card(
              child: Column(
                children: [
                  ...result.metrics.map((metric) {
                    return ListTile(
                      title: Text(metric.name),
                      subtitle: Text('근거 타임스탬프: ${metric.evidenceTimeMs.join(', ')} ms'),
                      trailing: Text(
                        '${metric.value} ${metric.unit}',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.teal),
                      ),
                    );
                  }),
                  if (shotData != null && shotData.calculatedSmashFactor != null)
                    ListTile(
                      title: const Text('스매시 팩터 (Smash Factor)'),
                      subtitle: const Text('볼 스피드 ÷ 헤드 스피드'),
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
            const Text('다음 연습 한 가지 (Recommended Drill)', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
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
                      Text(
                        result.primaryDrillTitle,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.amber),
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
                child: const Text('홈으로 돌아가기', style: TextStyle(color: Colors.white, fontSize: 16)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
