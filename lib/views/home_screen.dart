import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/swing_model.dart';
import '../providers/swing_provider.dart';
import '../services/localization_service.dart';
import '../theme/app_theme.dart';
import '../widgets/golf_widgets.dart';
import 'video_input_screen.dart';
import 'history_screen.dart';
import 'analysis_result_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  void _showSettingsDialog(BuildContext context, SwingProvider provider) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1E2B25),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final lang = provider.appLanguage;
            return Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.settings, color: AppTheme.mint),
                          SizedBox(width: 8),
                          Text('앱 환경 설정', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                        ],
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, color: Colors.white70),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                  const Divider(color: Colors.white12, height: 24),

                  // 1. Language Toggle
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.language, color: AppTheme.mint),
                    title: const Text('표시 언어 설정 (Language)', style: TextStyle(color: Colors.white, fontSize: 15)),
                    subtitle: Text(
                      lang == AppLanguage.korean ? '현재: 한국어 (Korean)' : 'Current: English',
                      style: const TextStyle(color: AppTheme.muted, fontSize: 12),
                    ),
                    trailing: TextButton.icon(
                      style: TextButton.styleFrom(
                        backgroundColor: Colors.white10,
                        foregroundColor: AppTheme.mint,
                      ),
                      onPressed: () {
                        provider.toggleLanguage();
                        setModalState(() {});
                      },
                      icon: const Icon(Icons.swap_horiz, size: 18),
                      label: Text(lang == AppLanguage.korean ? '🇰🇷 KR → 🇺🇸 EN' : '🇺🇸 EN → 🇰🇷 KR'),
                    ),
                  ),
                  const Divider(color: Colors.white12, height: 16),

                  // 2. OCR Step Toggle
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    activeColor: AppTheme.mint,
                    secondary: const Icon(Icons.document_scanner_outlined, color: AppTheme.mint),
                    title: const Text('스크린 샷 OCR 수치 연동 단계', style: TextStyle(color: Colors.white, fontSize: 15)),
                    subtitle: Text(
                      provider.enableOcrStep
                          ? '켜짐: 스윙 분석 전 스크린샷 OCR (볼스피드/비거리) 연동 단계를 거칩니다.'
                          : '꺼짐 (기본): 영상 선택/촬영 후 즉시 AI 분석 결과가 표시됩니다.',
                      style: const TextStyle(color: AppTheme.muted, fontSize: 12),
                    ),
                    value: provider.enableOcrStep,
                    onChanged: (val) {
                      provider.setEnableOcrStep(val);
                      setModalState(() {});
                    },
                  ),
                  const Divider(color: Colors.white12, height: 16),

                  // 3. Advanced Trimming Toggle
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    activeColor: AppTheme.mint,
                    secondary: const Icon(Icons.tune_outlined, color: AppTheme.mint),
                    title: const Text('고급 스윙 4단계 수동 조작 도구', style: TextStyle(color: Colors.white, fontSize: 15)),
                    subtitle: Text(
                      provider.enableAdvancedTrimming
                          ? '켜짐: 어드레스/탑/임팩트/피니시 시각 수동 지정 및 관절 디버그 패널이 활성화됩니다.'
                          : '꺼짐 (기본): 자동 포즈 스캔 기반의 깔끔한 타임라인이 제공됩니다.',
                      style: const TextStyle(color: AppTheme.muted, fontSize: 12),
                    ),
                    value: provider.enableAdvancedTrimming,
                    onChanged: (val) {
                      provider.setEnableAdvancedTrimming(val);
                      setModalState(() {});
                    },
                  ),
                  const Divider(color: Colors.white12, height: 16),

                  const ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.memory, color: AppTheme.mint),
                    title: Text('AI 온디바이스 엔진', style: TextStyle(color: Colors.white, fontSize: 15)),
                    subtitle: Text('Google ML Kit Pose Detection v3.0 (자동 회전 보정 및 33관절 스캔)', style: TextStyle(color: AppTheme.muted, fontSize: 12)),
                  ),
                  const SizedBox(height: 20),
                  Center(
                    child: Text(
                      'AI On-Device Golf Coach v0.1.0',
                      style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 11),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<SwingProvider>();
    final lang = provider.appLanguage;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          LocalizationService.tr('app_title', lang),
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        actions: [
          TextButton.icon(
            onPressed: () => provider.toggleLanguage(),
            icon: const Icon(Icons.language, color: AppTheme.mint, size: 18),
            label: Text(
              lang == AppLanguage.korean ? '🇰🇷 KR' : '🇺🇸 EN',
              style: const TextStyle(color: AppTheme.mint, fontWeight: FontWeight.bold, fontSize: 13),
            ),
          ),
          IconButton(
            tooltip: '설정',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => _showSettingsDialog(context, provider),
          ),
          IconButton(
            tooltip: '최근 기록',
            icon: const Icon(Icons.history_rounded),
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const HistoryScreen())),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(24, 28, 24, 32),
        children: [
          Text(LocalizationService.tr('banner_title', lang), style: const TextStyle(color: AppTheme.mint, fontSize: 13)),
          const SizedBox(height: 14),
          Text(
            lang == AppLanguage.korean ? '내 스윙을,\n더 선명하게.' : 'Clearer View of\nYour Swing.',
            style: Theme.of(context).textTheme.headlineLarge,
          ),
          const SizedBox(height: 16),
          Text(
            LocalizationService.tr('banner_subtitle', lang),
            style: const TextStyle(color: AppTheme.muted, fontSize: 15, height: 1.6),
          ),
          const SizedBox(height: 32),
          GolfPanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.sports_golf_rounded, size: 36, color: AppTheme.mint),
                const SizedBox(height: 20),
                Text(LocalizationService.tr('start_new_swing', lang), style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                Text(LocalizationService.tr('select_video_sub', lang), style: const TextStyle(color: AppTheme.muted)),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const VideoInputScreen()),
                  ),
                  child: Text('${LocalizationService.tr('start_new_swing', lang)}   →'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 28),
          const Text('영상 촬영  /  구간·관절 지정  /  스윙 분석 리포트', style: TextStyle(color: AppTheme.muted, fontSize: 12)),
          const SizedBox(height: 32),
          Row(
            children: [
              Expanded(child: Text(LocalizationService.tr('recent_history', lang), style: Theme.of(context).textTheme.titleMedium)),
              TextButton(
                onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const HistoryScreen())),
                child: Text(LocalizationService.tr('view_all', lang)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (provider.swingHistory.isEmpty)
            GolfPanel(
              child: Row(
                children: [
                  const Icon(Icons.movie_outlined, color: AppTheme.muted),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(LocalizationService.tr('no_history', lang), style: const TextStyle(color: AppTheme.muted)),
                  ),
                ],
              ),
            )
          else
            for (final swing in provider.swingHistory.reversed.take(3))
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: GolfPanel(
                  padding: EdgeInsets.zero,
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                    leading: const Icon(Icons.play_circle_outline, color: AppTheme.mint),
                    title: Text('${swing.club} Swing (${swing.view == SwingView.faceOn ? '정면' : '후방'})'),
                    subtitle: Text(swing.createdAt.toString().split('.')[0]),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () {
                      provider.openHistory(swing);
                      Navigator.push(context, MaterialPageRoute(builder: (_) => const AnalysisResultScreen()));
                    },
                  ),
                ),
              ),
        ],
      ),
    );
  }
}
