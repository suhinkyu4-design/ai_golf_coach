import 'package:flutter/material.dart';
import '../widgets/coach_app_bar.dart';
import '../widgets/assistant_welcome.dart';
import 'video_input_screen.dart';
import 'appearance_settings_screen.dart';
import 'history_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}
class _HomeScreenState extends State<HomeScreen> {
  bool _opening = false;
  Future<void> _start(String label) async {
    if (_opening) return;
    setState(() => _opening = true);
    try {
      await Navigator.push(context, MaterialPageRoute(builder: (_) =>
        VideoInputScreen(initialAction: label == '새 영상 촬영' ? 'camera' : 'gallery')));
    } finally { if (mounted) setState(() => _opening = false); }
  }
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: CoachAppBar(title: const Text('골프 코치'), actions: [
      IconButton(tooltip: '설정', icon: const Icon(Icons.settings_outlined),
        onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AppearanceSettingsScreen()))),
    ]),
    body: SafeArea(child: ListView(padding: const EdgeInsets.fromLTRB(20,16,20,24), children: [
      AssistantWelcome(busy: _opening, onAction: _start),
      Center(child: TextButton.icon(icon: const Icon(Icons.history_rounded), label: const Text('최근 스윙 기록'),
        onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const HistoryScreen())))),
    ])),
  );
}
