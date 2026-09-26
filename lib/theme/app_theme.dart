import 'package:flutter/services.dart';
import 'package:flutter/material.dart';

class AppTheme {
  static const background = Color(0xFF101715);
  static const surface = Color(0xFF1A2420);
  static const mint = Color(0xFFB8F3D1);
  static const muted = Color(0xFFA3B3AA);
  static ThemeData get light => _build(false);
  static ThemeData get dark => _build(true);
  static ThemeData _build(bool isDark) {
    final background = isDark ? AppTheme.background : Colors.white;
    final surface = isDark ? AppTheme.surface : const Color(0xFFF2F6F3);
    final muted = isDark ? AppTheme.muted : const Color(0xFF53645A);
    final ink = isDark ? const Color(0xFFF2F5F1) : const Color(0xFF182B21);
    final accent = isDark ? mint : const Color(0xFF176B43);
    final base = ThemeData(brightness: isDark ? Brightness.dark : Brightness.light, useMaterial3: true);
    return base.copyWith(
      scaffoldBackgroundColor: background,
      dividerColor: isDark ? const Color(0xFF2D3B33) : const Color(0xFFDCE5DF),
      cardColor: surface,
      cardTheme: CardTheme(color: surface, surfaceTintColor: Colors.transparent, elevation: 0, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24))),
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF176B43), brightness: isDark ? Brightness.dark : Brightness.light).copyWith(
        primary: accent, onPrimary: isDark ? const Color(0xFF12291D) : Colors.white,
        secondary: accent, surface: surface, onSurface: ink, onSurfaceVariant: muted,
        outline: isDark ? const Color(0xFF40534A) : const Color(0xFFA8B9AE)),
      textTheme: base.textTheme.copyWith(
        headlineLarge: const TextStyle(fontSize: 36, height: 1.2, fontWeight: FontWeight.w700, letterSpacing: -1.2),
        titleLarge: const TextStyle(fontSize: 22, height: 1.35, fontWeight: FontWeight.w600, letterSpacing: -.5),
        titleMedium: const TextStyle(fontSize: 17, height: 1.4, fontWeight: FontWeight.w600),
        bodyLarge: const TextStyle(fontSize: 16, height: 1.6),
        bodyMedium: const TextStyle(fontSize: 14, height: 1.6),
        bodySmall: TextStyle(fontSize: 12, height: 1.5, color: muted),
      ).apply(bodyColor: ink, displayColor: ink),
      appBarTheme: AppBarTheme(backgroundColor: background, surfaceTintColor: Colors.transparent,
        foregroundColor: ink, elevation: 0, centerTitle: false,
        iconTheme: IconThemeData(color: ink, size: 28),
        actionsIconTheme: IconThemeData(color: ink, size: 28),
        systemOverlayStyle: SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
          systemNavigationBarColor: background,
          systemNavigationBarIconBrightness: isDark ? Brightness.light : Brightness.dark),
        titleTextStyle: TextStyle(color: ink, fontSize: 18, fontWeight: FontWeight.w600)),
      elevatedButtonTheme: ElevatedButtonThemeData(style: ElevatedButton.styleFrom(
        backgroundColor: mint, foregroundColor: const Color(0xFF12291D), elevation: 0,
        minimumSize: const Size(double.infinity, 54),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      )),
      outlinedButtonTheme: OutlinedButtonThemeData(style: OutlinedButton.styleFrom(
        foregroundColor: accent, minimumSize: const Size(0, 52),
        side: BorderSide(color: isDark ? const Color(0xFF789889) : const Color(0xFF40534A)),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      )),
      inputDecorationTheme: InputDecorationTheme(filled: true, fillColor: surface,
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: accent)),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: surface,
        selectedColor: mint,
        disabledColor: surface,
        labelStyle: TextStyle(color: ink, fontWeight: FontWeight.w600),
        secondaryLabelStyle: const TextStyle(color: Color(0xFF12291D), fontWeight: FontWeight.bold),
        checkmarkColor: const Color(0xFF12291D),
        side: BorderSide(color: isDark ? const Color(0xFF789889) : const Color(0xFF40534A)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      ),
      dividerTheme: DividerThemeData(color: isDark ? const Color(0xFF2D3B33) : const Color(0xFFDCE5DF), space: 24),
    );
  }
}
