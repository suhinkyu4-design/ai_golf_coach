import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'providers/swing_provider.dart';
import 'providers/voice_settings.dart';
import 'views/home_screen.dart';
import 'providers/experience_settings.dart';
import 'theme/app_theme.dart';
import 'theme/theme_controller.dart';
import 'services/slm_debug_check.dart';
import 'services/app_error_log.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  AppErrorLog.install();
  assert(registerSlmDebugCheck());
  final appearance = ThemeController();
  await appearance.load();
  final voice = VoiceSettings();
  await voice.load();
  final experience = ExperienceSettings();
  await experience.load();
  runApp(MultiProvider(providers: [ChangeNotifierProvider.value(value: experience), ChangeNotifierProvider(create: (_) => SwingProvider()),
    ChangeNotifierProvider.value(value: voice), ChangeNotifierProvider.value(value: appearance)], child: const AiGolfCoachApp()));
}
class AiGolfCoachApp extends StatelessWidget {
  const AiGolfCoachApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: '골프 코치', debugShowCheckedModeBanner: false,
    themeMode: context.watch<ThemeController>().mode, theme: AppTheme.light, darkTheme: AppTheme.dark,
    home: const HomeScreen(),
  );
}
