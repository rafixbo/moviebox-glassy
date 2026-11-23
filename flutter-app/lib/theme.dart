import 'package:flutter/material.dart';

/// Dark glass theme: near-black background, soft coloured blobs behind,
/// frosted cards (white 8% fill + white 12% border), rounded 18–20px.
class GlassTheme {
  static const bg = Color(0xFF0A0A0F);
  static const surface = Color(0xFF14141C);
  static const accent = Color(0xFF7C6CFF);
  static const accent2 = Color(0xFF3ED6C5);
  static const accent3 = Color(0xFFFF6B9D);
  static const text = Color(0xFFF4F4F8);
  static const muted = Color(0xFF9A9AAF);

  static const glassFill = Color(0x14FFFFFF); // white 8%
  static const glassBorder = Color(0x1FFFFFFF); // white 12%

  static ThemeData get theme => ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: bg,
        colorScheme: const ColorScheme.dark(
          primary: accent,
          secondary: accent2,
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
          backgroundColor: Colors.transparent,
          elevation: 0,
          centerTitle: false,
          titleTextStyle: TextStyle(
              color: text, fontSize: 22, fontWeight: FontWeight.w800),
        ),
        bottomNavigationBarTheme: const BottomNavigationBarThemeData(
          backgroundColor: Colors.transparent,
          elevation: 0,
          selectedItemColor: text,
          unselectedItemColor: muted,
          type: BottomNavigationBarType.fixed,
          showSelectedLabels: false,
          showUnselectedLabels: false,
        ),
        useMaterial3: true,
      );
}
