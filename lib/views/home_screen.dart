import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/swing_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/golf_widgets.dart';
import 'video_input_screen.dart';
import 'history_screen.dart';
import 'analysis_result_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final provider = context.watch<SwingProvider>();
    return Scaffold(
      appBar: AppBar(title: const Text('GOLF / COACH', style: TextStyle(fontSize: 15, letterSpacing: 2)),
        actions: [IconButton(tooltip: '최근 기록', icon: const Icon(Icons.history_rounded),
          onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const HistoryScreen())))]),
      body: ListView(padding: const EdgeInsets.fromLTRB(24, 28, 24, 32), children: [
        const Text('한 번의 스윙, 하나의 기록', style: TextStyle(color: AppTheme.mint, fontSize: 13)),
        const SizedBox(height: 14),
        Text('내 스윙을,\n더 선명하게.', style: Theme.of(context).textTheme.headlineLarge),
        const SizedBox(height: 16),
        const Text('움직임은 영상으로.\n샷의 결과는 숫자로 확인하세요.',
          style: TextStyle(color: AppTheme.muted, fontSize: 16, height: 1.7)),
        const SizedBox(height: 32),
        GolfPanel(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Icon(Icons.sports_golf_rounded, size: 36, color: AppTheme.mint),
          const SizedBox(height: 20),
          Text('오늘의 스윙을 남겨보세요', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          const Text('직접 촬영하거나 갤러리에서 가져올 수 있어요.', style: TextStyle(color: AppTheme.muted)),
          const SizedBox(height: 24),
          ElevatedButton(onPressed: () => Navigator.push(context,
            MaterialPageRoute(builder: (_) => const VideoInputScreen())), child: const Text('새 스윙 기록   →')),
        ])),
        const SizedBox(height: 28),
        const Text('영상 확인  /  구간 지정  /  샷 기록', style: TextStyle(color: AppTheme.muted, fontSize: 12)),
        const SizedBox(height: 32),
        Row(children: [Expanded(child: Text('최근 기록', style: Theme.of(context).textTheme.titleMedium)),
          TextButton(onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const HistoryScreen())),
            child: const Text('모두 보기'))]),
        const Text('이번 앱 실행에서 확인한 스윙', style: TextStyle(color: AppTheme.muted, fontSize: 12)),
        const SizedBox(height: 12),
        if (provider.swingHistory.isEmpty)
          const GolfPanel(child: Row(children: [Icon(Icons.movie_outlined, color: AppTheme.muted),
            SizedBox(width: 14), Expanded(child: Text('첫 스윙을 기록하면 여기에 표시됩니다.', style: TextStyle(color: AppTheme.muted)))]))
        else for (final swing in provider.swingHistory.reversed.take(3)) Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: GolfPanel(padding: EdgeInsets.zero, child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            leading: const Icon(Icons.play_circle_outline, color: AppTheme.mint),
            title: Text(swing.club), subtitle: Text(swing.createdAt.toString().split('.')[0]),
            trailing: const Icon(Icons.chevron_right),
            onTap: () { provider.openHistory(swing); Navigator.push(context,
              MaterialPageRoute(builder: (_) => const AnalysisResultScreen())); },
          )),
        ),
      ]),
    );
  }
}
