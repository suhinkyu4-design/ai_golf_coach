import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'providers/swing_provider.dart';
import 'views/home_screen.dart';
import 'theme/app_theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(ChangeNotifierProvider(create: (_) => SwingProvider(), child: const AiGolfCoachApp()));
}
class AiGolfCoachApp extends StatelessWidget {
  const AiGolfCoachApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: '골프 코치', debugShowCheckedModeBanner: false,
    themeMode: ThemeMode.dark, darkTheme: AppTheme.dark,
    home: const HomeScreen(),
  );
}
