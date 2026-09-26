import '../widgets/coach_app_bar.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../theme/theme_controller.dart';
import '../providers/voice_settings.dart';
import '../providers/experience_settings.dart';
import '../models/swing_model.dart';
import 'package:flutter/services.dart';

class AppearanceSettingsScreen extends StatelessWidget {
  const AppearanceSettingsScreen({super.key});
  Future<void> _save(BuildContext context, ExperienceSettings prefs,
      {Handedness? hand, SwingView? view, String? club}) async {
    try {
      await prefs.select(hand: hand, view: view, club: club);
    } catch (_) {
      if (context.mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('설정 저장에 실패했습니다.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<ThemeController>();
    final experience = context.watch<ExperienceSettings>();
    final voice = context.watch<VoiceSettings>();
    return Scaffold(
        appBar: CoachAppBar(title: const Text('설정')),
        body: ListView(padding: const EdgeInsets.all(24), children: [
          Text('다음 스윙 기본 설정', style: Theme.of(context).textTheme.titleLarge),
          DropdownButtonFormField<Handedness>(
              value: experience.hand,
              decoration: const InputDecoration(labelText: '주사용 손'),
              items: const [
                DropdownMenuItem(value: Handedness.right, child: Text('오른손')),
                DropdownMenuItem(value: Handedness.left, child: Text('왼손'))
              ],
              onChanged: experience.saving
                  ? null
                  : (v) => _save(context, experience, hand: v)),
          DropdownButtonFormField<String>(
              value: experience.club,
              decoration: const InputDecoration(labelText: '클럽'),
              items: const [
                DropdownMenuItem(
                    value: 'unknown', child: Text('미지정 · 공통 동작 분석')),
                DropdownMenuItem(value: 'Driver', child: Text('드라이버')),
                DropdownMenuItem(value: '7i', child: Text('7번 아이언'))
              ],
              onChanged: experience.saving
                  ? null
                  : (v) => _save(context, experience, club: v)),
          DropdownButtonFormField<SwingView>(
              value: experience.view,
              decoration: const InputDecoration(labelText: '촬영 방향'),
              items: const [
                DropdownMenuItem(value: SwingView.rear, child: Text('후방')),
                DropdownMenuItem(value: SwingView.faceOn, child: Text('정면'))
              ],
              onChanged: experience.saving
                  ? null
                  : (v) => _save(context, experience, view: v)),
          const SizedBox(height: 32),
          Text('화면 테마', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          const Text('편안하게 볼 수 있는 배경을 선택하세요.'),
          const SizedBox(height: 24),
          for (final mode in [ThemeMode.light, ThemeMode.dark])
            Card(
                child: RadioListTile<ThemeMode>(
                    value: mode,
                    groupValue: controller.mode,
                    title: Text(mode == ThemeMode.light ? '밝은 화면' : '어두운 화면'),
                    subtitle: Text(mode == ThemeMode.light
                        ? '흰색 배경 · 기본 테마'
                        : '기존의 짙은 녹색 배경'),
                    onChanged: controller.saving
                        ? null
                        : (value) async {
                            try {
                              await controller.select(value!);
                            } catch (_) {
                              if (context.mounted)
                                ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                        content: Text(
                                            '설정을 저장하지 못했습니다. 다시 시도해 주세요.')));
                            }
                          })),
          const SizedBox(height: 24),
          const Text('선택한 테마는 앱을 다시 열어도 유지됩니다.'),
          const SizedBox(height: 32),
          Text('촬영', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 12),
          Card(
              child: SwitchListTile(
                  title: const Text('음성으로 촬영'),
                  subtitle:
                      const Text('켜면 마이크 권한을 확인합니다. 촬영 화면에서만 음성 명령을 듣습니다.'),
                  value: voice.enabled,
                  onChanged: voice.saving
                      ? null
                      : (value) async {
                          try {
                            await voice.select(value);
                          } catch (e) {
                            if (context.mounted)
                              ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                      content: Text(e is PlatformException
                                          ? (e.message ?? '음성 촬영을 설정하지 못했습니다.')
                                          : '설정을 저장하지 못했습니다. 다시 시도해 주세요.')));
                          }
                        })),
          const SizedBox(height: 8),
          const Text(
              '“시작” · “종료”\n한 번 켜면 다음 촬영부터 자동으로 대기합니다. 꺼 두면 버튼으로만 촬영합니다.'),
        ]));
  }
}
