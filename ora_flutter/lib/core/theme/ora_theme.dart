import 'package:flutter/material.dart';

abstract final class OraColors {
  static const forest = Color(0xFF0E2118);
  static const forestDeep = Color(0xFF09150F);
  static const forestLight = Color(0xFF163828);
  static const cream = Color(0xFFF4E7C5);
  static const creamMuted = Color(0xFFCDBF9A);
  static const gold = Color(0xFFE0A83A);
  static const orange = Color(0xFFD86F32);
  static const moss = Color(0xFF6F8F4E);
  static const panel = Color(0xFF13281D);
  static const panelAlt = Color(0xFF1A3325);
  static const outline = Color(0xFF6B5B32);
  static const success = Color(0xFF8CC36B);
  static const teal = Color(0xFF49B8A6);
  static const rankBlue = Color(0xFF4D9DE0);
}

abstract final class OraTextStyles {
  static const displayLarge = TextStyle(
    fontFamily: 'PressStart2P',
    fontSize: 20,
    height: 1.4,
    color: OraColors.cream,
  );
  static const displayMedium = TextStyle(
    fontFamily: 'PressStart2P',
    fontSize: 14,
    height: 1.45,
    color: OraColors.cream,
  );
  static const displaySmall = TextStyle(
    fontFamily: 'PressStart2P',
    fontSize: 11,
    height: 1.45,
    color: OraColors.cream,
  );
}

ThemeData buildOraTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: OraColors.gold,
    brightness: Brightness.dark,
    primary: OraColors.gold,
    onPrimary: OraColors.forestDeep,
    surface: OraColors.panel,
    onSurface: OraColors.cream,
    error: OraColors.orange,
  );
  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: scheme,
    scaffoldBackgroundColor: OraColors.forestDeep,
    textTheme: const TextTheme(
      bodyLarge: TextStyle(fontSize: 16, height: 1.5, color: OraColors.cream),
      bodyMedium: TextStyle(fontSize: 14, height: 1.45, color: OraColors.cream),
      bodySmall: TextStyle(
        fontSize: 12,
        height: 1.4,
        color: OraColors.creamMuted,
      ),
      titleLarge: TextStyle(
        fontSize: 22,
        fontWeight: FontWeight.bold,
        color: OraColors.cream,
      ),
      titleMedium: TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.bold,
        color: OraColors.cream,
      ),
      labelLarge: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
      labelMedium: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: OraColors.panelAlt,
      labelStyle: const TextStyle(color: OraColors.creamMuted),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(5),
        borderSide: const BorderSide(color: OraColors.outline),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(5),
        borderSide: const BorderSide(color: OraColors.outline),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(5),
        borderSide: const BorderSide(color: OraColors.gold, width: 2),
      ),
    ),
  );
}
