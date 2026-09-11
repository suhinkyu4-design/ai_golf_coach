import 'package:flutter/material.dart';

class AppTheme {
  static const background = Color(0xFF101715);
  static const surface = Color(0xFF1A2420);
  static const mint = Color(0xFFB8F3D1);
  static const muted = Color(0xFFA3B3AA);
  static ThemeData get dark {
    final base = ThemeData.dark(useMaterial3: true);
    return base.copyWith(
      scaffoldBackgroundColor: background,
      cardColor: surface,
      colorScheme: const ColorScheme.dark(primary: mint, onPrimary: Color(0xFF12291D),
        secondary: mint, onSecondary: Color(0xFF12291D), surface: surface,
        onSurface: Color(0xFFF2F5F1), error: Color(0xFFFFB4A9)),
      textTheme: base.textTheme.copyWith(
        headlineLarge: const TextStyle(fontSize: 36, height: 1.2, fontWeight: FontWeight.w700, letterSpacing: -1.2),
        titleLarge: const TextStyle(fontSize: 22, height: 1.35, fontWeight: FontWeight.w600, letterSpacing: -.5),
        titleMedium: const TextStyle(fontSize: 17, height: 1.4, fontWeight: FontWeight.w600),
        bodyLarge: const TextStyle(fontSize: 16, height: 1.6),
        bodyMedium: const TextStyle(fontSize: 14, height: 1.6),
        bodySmall: const TextStyle(fontSize: 12, height: 1.5, color: muted),
      ),
      appBarTheme: const AppBarTheme(backgroundColor: background, surfaceTintColor: Colors.transparent,
        foregroundColor: Color(0xFFF2F5F1), elevation: 0, centerTitle: false,
        titleTextStyle: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
      elevatedButtonTheme: ElevatedButtonThemeData(style: ElevatedButton.styleFrom(
        backgroundColor: mint, foregroundColor: const Color(0xFF12291D), elevation: 0,
        minimumSize: const Size(double.infinity, 54),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      )),
      outlinedButtonTheme: OutlinedButtonThemeData(style: OutlinedButton.styleFrom(
        foregroundColor: mint, minimumSize: const Size(0, 52),
        side: const BorderSide(color: Color(0xFF40534A)),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      )),
      inputDecorationTheme: InputDecorationTheme(filled: true, fillColor: surface,
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: mint)),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: surface,
        selectedColor: mint,
        disabledColor: surface,
        labelStyle: const TextStyle(color: Color(0xFFF2F5F1), fontWeight: FontWeight.w600),
        secondaryLabelStyle: const TextStyle(color: Color(0xFF12291D), fontWeight: FontWeight.bold),
        checkmarkColor: const Color(0xFF12291D),
        side: const BorderSide(color: Color(0xFF40534A)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      ),
      dividerTheme: const DividerThemeData(color: Color(0xFF2D3B33), space: 24),
    );
  }
}
