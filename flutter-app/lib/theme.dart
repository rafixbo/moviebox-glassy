import 'package:flutter/material.dart';

/// Clean Material 3 dark theme: one solid background, standard Material
/// widgets, no decorative background art and no blur effects.
class AppTheme {
  static const accent = Color(0xFF8B7CFF);
  static const accent2 = Color(0xFF3ED6C5);
  static const accent3 = Color(0xFFFF6B9D);
  static const bg = Color(0xFF0E0E13);
  static const surface = Color(0xFF1A1A22);
  static const text = Color(0xFFF4F4F8);
  static const muted = Color(0xFF9A9AAF);

  static ThemeData get theme => ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    scaffoldBackgroundColor: bg,
    colorScheme: const ColorScheme.dark(
      primary: accent,
      secondary: accent2,
      tertiary: accent3,
      surface: surface,
      onSurface: text,
    ),
    textTheme: const TextTheme(
      bodyMedium: TextStyle(color: text),
      bodyLarge: TextStyle(color: text),
      titleLarge: TextStyle(color: text, fontWeight: FontWeight.w700),
      titleMedium: TextStyle(color: text, fontWeight: FontWeight.w600),
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: bg,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        color: text,
        fontSize: 22,
        fontWeight: FontWeight.w800,
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: surface,
      indicatorColor: accent.withValues(alpha: 0.25),
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) => TextStyle(
          color: states.contains(WidgetState.selected) ? text : muted,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),
    snackBarTheme: const SnackBarThemeData(
      backgroundColor: surface,
      contentTextStyle: TextStyle(color: text),
    ),
  );
}
