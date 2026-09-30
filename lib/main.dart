import 'package:camera_android/camera_android.dart';
import 'package:flutter/material.dart';
import 'package:image_picker_android/image_picker_android.dart';
import 'package:provider/provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:video_player_android/video_player_android.dart';
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
  // This APK is built through a manual Dart-kernel path, which does not invoke
  // Flutter's generated Dart plugin registrant. Keep its Android registrations
  // explicit so platform implementations are available before app startup.
  _registerAndroidDartPlugins();
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

void _registerAndroidDartPlugins() {
  final registrations = <String, void Function()>{
    'camera_android': AndroidCamera.registerWith,
    'image_picker_android': ImagePickerAndroid.registerWith,
    'sqflite': SqflitePlugin.registerWith,
    'video_player_android': AndroidVideoPlayer.registerWith,
  };
  for (final entry in registrations.entries) {
    try {
      entry.value();
      AppErrorLog.record('DART_PLUGIN_REGISTERED', entry.key);
    } catch (error, stackTrace) {
      // Match Flutter's generated registrant behavior: one optional plugin
      // must not prevent the rest of the application from launching.
      AppErrorLog.record(
        'DART_PLUGIN_REGISTRATION_ERROR',
        '${entry.key}: $error\n$stackTrace',
      );
    }
  }
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
