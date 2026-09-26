import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../models/shot_measurement_model.dart';
import '../services/shot_insight_service.dart';

class ShotVisualCard extends StatelessWidget {
  final ShotMeasurementModel shot;
  const ShotVisualCard({super.key, required this.shot});
  bool valid(double? n) => n != null && n.isFinite && n >= 0;
  Widget bar(BuildContext context, String label, double value, double max, String unit, Color color) => Padding(
    padding: const EdgeInsets.only(top: 16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('$label  ${value.toStringAsFixed(1)} $unit'), const SizedBox(height: 8),
      Semantics(label: '$label ${value.toStringAsFixed(1)} $unit', child: ClipRRect(borderRadius: BorderRadius.circular(8),
        child: LinearProgressIndicator(value: max > 0 ? (value/max).clamp(0,1) : 0, minHeight: 14, color: color,
          backgroundColor: Theme.of(context).colorScheme.onSurface.withOpacity(.08)))),
    ]));
  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    final carry = shot.carryDistanceMeters, total = shot.totalDistanceMeters;
    final ball = shot.ballSpeedMs, club = shot.clubSpeedMs;
    final distanceMax = math.max(valid(carry) ? carry! : 0.0, valid(total) ? total! : 0.0);
    final speedMax = math.max(valid(ball) ? ball! : 0.0, valid(club) ? club! : 0.0);
    return Card(child: Padding(padding: const EdgeInsets.all(20), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [Icon(Icons.sports_golf, color: c.primary), const SizedBox(width: 8),
        Expanded(child: Text(shot.isTestData ? '샷 결과 · 테스트 예시' : '공은 얼마나 날아갔나요?', style: Theme.of(context).textTheme.titleLarge))]),
      if (shot.isTestData) const Padding(padding: EdgeInsets.only(top: 8), child: Text('실제 측정값이 아닌 테스트 데이터입니다.')),
      if (valid(carry) || valid(total)) ...[
        if (valid(carry)) bar(context, '착지까지 · 캐리', carry!, distanceMax, 'm', c.primary),
        if (valid(total)) bar(context, '멈춘 곳까지 · 총거리', total!, distanceMax, 'm', c.secondary),
        if (valid(carry) && valid(total) && total! >= carry!) Padding(padding: const EdgeInsets.only(top: 12),
          child: Text('착지 이후 ${(total-carry).toStringAsFixed(1)} m', style: Theme.of(context).textTheme.titleMedium)),
        const SizedBox(height: 8), Text('거리 비교 그림 · 실제 비행 궤적은 아닙니다.', style: Theme.of(context).textTheme.bodySmall),
      ] else const Padding(padding: EdgeInsets.only(top: 12), child: Text('거리 수치를 추가하면 캐리와 총거리를 비교할 수 있습니다.')),
      if (valid(ball) || valid(club)) ...[
        const SizedBox(height: 24), Text('클럽에서 공으로', style: Theme.of(context).textTheme.titleMedium),
        if (valid(club)) bar(context, '클럽 속도', club!, speedMax, 'm/s', c.onSurfaceVariant),
        if (valid(ball)) bar(context, '공 속도', ball!, speedMax, 'm/s', c.primary),
        if (shot.calculatedSmashFactor != null) Padding(padding: const EdgeInsets.only(top: 12),
          child: Text('속도 비율 ${shot.calculatedSmashFactor!.toStringAsFixed(2)} · 스매시 팩터')),
      ],
      const SizedBox(height: 16),
      ExpansionTile(tilePadding: EdgeInsets.zero, title: const Text('발사각·스핀과 수치 해석'), children: [
        for(final line in ShotInsightService.describe(shot)) Padding(padding: const EdgeInsets.only(bottom: 12),child: Text(line)),
        const Text('샷 수치만으로 자세 오류의 원인을 확정하지 않습니다.'),
      ]),
    ])));
  }
}
