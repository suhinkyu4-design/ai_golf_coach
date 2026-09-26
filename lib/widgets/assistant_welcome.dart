import 'package:flutter/material.dart';

class AssistantWelcome extends StatelessWidget {
  final bool busy;
  final ValueChanged<String> onAction;
  const AssistantWelcome(
      {super.key, required this.busy, required this.onAction});

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 12, 4, 24),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Center(
            child: Container(
          width: 190,
          height: 190,
          decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: dark
                      ? [const Color(0xFF294D40), const Color(0xFF172D25)]
                      : [const Color(0xFFE6F5EC), const Color(0xFFF5FAF7)])),
          child: Image.asset('assets/golf_coach_agent.png',
              fit: BoxFit.contain,
              semanticLabel: '손을 흔들며 반기는 AI 골프 코치',
              errorBuilder: (_, __, ___) =>
                  Icon(Icons.sports_golf, size: 72, color: c.primary)),
        )),
        const SizedBox(height: 24),
        Text('나의 AI 골프 코치',
            style: TextStyle(
                color: c.primary,
                fontSize: 13,
                fontWeight: FontWeight.w600,
                letterSpacing: .5)),
        const SizedBox(height: 10),
        Text('오늘의 스윙,\n함께 살펴볼까요?',
            style: TextStyle(
                color: c.onSurface,
                fontSize: 30,
                height: 1.25,
                fontWeight: FontWeight.w700,
                letterSpacing: -1)),
        const SizedBox(height: 14),
        Text('영상을 준비하면 분석부터 교정 안내까지\n차근차근 도와드릴게요.',
            style: TextStyle(
                color: c.onSurfaceVariant, height: 1.6, fontSize: 15)),
        const SizedBox(height: 26),
        SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
                onPressed: busy ? null : () => onAction('새 영상 촬영'),
                style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 17),
                    backgroundColor: c.primary,
                    foregroundColor: c.onPrimary,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18))),
                icon: const Icon(Icons.videocam_outlined),
                label: const Text('새 영상 촬영'))),
        const SizedBox(height: 10),
        SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
                onPressed: busy ? null : () => onAction('갤러리에서 가져오기'),
                style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 17),
                    foregroundColor: c.primary,
                    side: BorderSide(color: dark ? const Color(0xFF789889) : c.outline.withOpacity(.45)),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18))),
                icon: const Icon(Icons.video_library_outlined),
                label: const Text('갤러리에서 가져오기'))),
        const SizedBox(height: 16),
        Center(
            child: Text('궁금한 점은 상단 코치 아이콘을 눌러 주세요',
                style: TextStyle(color: c.onSurfaceVariant, fontSize: 12))),
      ]),
    );
  }
}
