import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'providers/swing_provider.dart';
import 'views/home_screen.dart';

void main() {
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => SwingProvider()),
      ],
      child: const AiGolfCoachApp(),
    ),
  );
}

class AiGolfCoachApp extends StatelessWidget {
  const AiGolfCoachApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AI 온디바이스 골프 코치',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.dark,
      darkTheme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF121212),
        cardColor: const Color(0xFF1E1E1E),
        colorScheme: ColorScheme.dark(
          primary: Colors.teal,
          secondary: Colors.tealAccent,
          surface: const Color(0xFF1E1E1E),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF1E1E1E),
          elevation: 0,
          centerTitle: true,
          titleTextStyle: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
        ),
        useMaterial3: true,
      ),
      home: const HomeScreen(),
    );
  }
}
