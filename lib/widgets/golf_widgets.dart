import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class GolfPanel extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  const GolfPanel({super.key, required this.child, this.padding = const EdgeInsets.all(20)});
  @override
  Widget build(BuildContext context) => Container(
    padding: padding,
    decoration: BoxDecoration(color: AppTheme.surface,
      borderRadius: BorderRadius.circular(24),
      border: Border.all(color: const Color(0xFF2B3931))), child: child);
}

class GolfStepHeader extends StatelessWidget {
  final int step;
  final String title, description;
  const GolfStepHeader({super.key, required this.step, required this.title, required this.description});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 24),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: List.generate(4, (i) => Expanded(child: Container(
        margin: EdgeInsets.only(right: i == 3 ? 0 : 6), height: 3,
        decoration: BoxDecoration(color: i < step ? AppTheme.mint : const Color(0xFF304137),
          borderRadius: BorderRadius.circular(8)),
      )))),
      const SizedBox(height: 20),
      Text('0$step / 04', style: const TextStyle(color: AppTheme.mint, fontSize: 12, letterSpacing: 2)),
      const SizedBox(height: 8),
      Text(title, style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 8),
      Text(description, style: const TextStyle(color: AppTheme.muted, height: 1.6)),
    ]),
  );
}
