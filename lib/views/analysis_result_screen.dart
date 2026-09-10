import 'package:flutter/material.dart';
import '../widgets/golf_widgets.dart';
import 'package:provider/provider.dart';
import '../providers/swing_provider.dart';
import '../models/metric_model.dart';
import '../models/shot_measurement_model.dart';
import 'pose_trimming_screen.dart';

class AnalysisResultScreen extends StatelessWidget {
  const AnalysisResultScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final provider = context.watch<SwingProvider>();
    final result = provider.currentAnalysisResult;
    final swing = provider.currentSwing;
    final shot = provider.currentShotMeasurement;
    return Scaffold(
      appBar: AppBar(title: const Text('스윙 기록 결과')),
      body: result == null || swing == null
        ? const Center(child: Text('표시할 결과가 없습니다. 영상 구간을 확인한 뒤 다시 진행하세요.'))
        : ListView(padding: const EdgeInsets.all(20), children: [
          const GolfStepHeader(step: 4, title: '이번 스윙의 기록', description: '영상에서 지정한 시간과 확인한 샷 수치를 함께 봅니다.'),
          Text('${swing.club} · ${swing.view.name} · ${swing.handedness.name}',
            style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          Card(child: Padding(padding: const EdgeInsets.all(16), child: Text(result.koreanSummary))),
          const SizedBox(height: 16), const Text('영상에서 지정한 시각으로 계산한 수치'),
          if (result.metrics.isEmpty) const Padding(padding: EdgeInsets.all(16), child: Text('확인된 시간 수치가 없습니다.')),
          for (final metric in result.metrics) Padding(
            padding: const EdgeInsets.only(top: 12),
            child: GolfPanel(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(metric.name, style: Theme.of(context).textTheme.bodyMedium),
              const SizedBox(height: 10),
              Text('${metric.value.toStringAsFixed(metric.unit == 'ms' ? 0 : 2)} ${metric.unit}',
                style: Theme.of(context).textTheme.headlineLarge),
              const SizedBox(height: 10),
              Text('${metric.status == MetricStatus.estimated ? '수동 추정' : metric.status.name} · ${metric.evidenceTimeMs.join(', ')} ms',
                style: Theme.of(context).textTheme.bodySmall),
            ])),
          ),
          const SizedBox(height: 16), const Text('사용자가 확인한 스크린장 샷 기록'),
          if (shot == null || shot.ocrStatus != OcrStatus.userConfirmed)
            const Padding(padding: EdgeInsets.all(16), child: Text('첨부한 샷 기록 없음'))
          else ...[
            _shot('볼스피드', shot.ballSpeedMs, 'm/s'),
            _shot('클럽스피드', shot.clubSpeedMs, 'm/s'),
            _shot('캐리', shot.carryDistanceMeters, 'm'),
            _shot('총거리', shot.totalDistanceMeters, 'm'),
            _shot('발사각', shot.launchAngleDeg, '°'),
            _shot('백스핀', shot.backSpinRpm, 'rpm'),
            _shot('사이드스핀', shot.sideSpinRpm, 'rpm'),
            _shot('스매시 팩터 · 볼스피드/클럽스피드', shot.calculatedSmashFactor, ''),
          ],
          const SizedBox(height: 16),
          const Text('자세 각도와 자동 교정 분석은 아직 준비 중입니다. 측정하지 않은 항목을 정상으로 판정하지 않습니다.'),
          OutlinedButton(onPressed: () => Navigator.push(context,
            MaterialPageRoute(builder: (_) => const PoseTrimmingScreen())), child: const Text('영상과 지정 시각 다시 확인')),
          ElevatedButton(onPressed: () => Navigator.popUntil(context, (r) => r.isFirst), child: const Text('홈으로')),
        ]),
    );
  }
  Widget _shot(String label, double? value, String unit) => value == null
    ? const SizedBox.shrink()
    : ListTile(contentPadding: EdgeInsets.zero, title: Text(label), trailing: Text('${value.toStringAsFixed(2)} $unit'));
}
