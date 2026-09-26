import 'package:flutter/material.dart';

class GolfPanel extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  const GolfPanel({super.key, required this.child, this.padding = const EdgeInsets.all(20)});
  @override
  Widget build(BuildContext context) => Container(
    padding: padding,
    decoration: BoxDecoration(color: Theme.of(context).colorScheme.surface,
      borderRadius: BorderRadius.circular(24),
      border: Border.all(color: Theme.of(context).dividerColor)), child: child);
}

class GolfStepHeader extends StatelessWidget {
  final int step;
  final String title, description;
  const GolfStepHeader({super.key, required this.step, required this.title, required this.description});
  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(bottom: 24),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: List.generate(4, (i) => Expanded(child: Container(
        margin: EdgeInsets.only(right: i == 3 ? 0 : 6), height: 3,
        decoration: BoxDecoration(color: i < step ? Theme.of(context).colorScheme.primary : Theme.of(context).dividerColor,
          borderRadius: BorderRadius.circular(8)),
      )))),
      SizedBox(height: 20),
      Text('0$step / 04', style: TextStyle(color: Theme.of(context).colorScheme.primary, fontSize: 12, letterSpacing: 2)),
      SizedBox(height: 8),
      Text(title, style: Theme.of(context).textTheme.titleLarge),
      SizedBox(height: 8),
      Text(description, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, height: 1.6)),
    ]),
  );
}
