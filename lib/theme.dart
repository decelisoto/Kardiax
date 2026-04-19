// lib/theme.dart
import 'package:flutter/material.dart';

class KardiaxColors {
  // Primary
  static const red = Color(0xFFE53935);
  static const redLight = Color(0xFFEF9A9A);
  static const redGlow = Color(0x33E53935);
  static const gray = Color(0xFF9CA3AF);

  // Backgrounds
  static const black = Color(0xFFF2F4F8);   // page background (light)
  static const surface = Color(0xFFFFFFFF);
  static const card = Color(0xFFFFFFFF);
  static const input = Color(0xFFE8EBF0);

  // Text
  static const textPrimary = Color(0xFF0D1117);
  static const textSecondary = Color(0xFF6B7280);
  static const textHint = Color(0xFFADB5BD);

  // Semantic
  static const green = Color(0xFF00A846);
  static const amber = Color(0xFFF59E0B);
  static const greenGlow = Color(0x2200A846);
  static const amberGlow = Color(0x22F59E0B);
}

class KardiaxTheme {
  static ThemeData get theme => ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    scaffoldBackgroundColor: KardiaxColors.black,
    colorScheme: const ColorScheme.light(
      primary: KardiaxColors.red,
      surface: KardiaxColors.surface,
      error: KardiaxColors.red,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: KardiaxColors.surface,
      foregroundColor: KardiaxColors.textPrimary,
      elevation: 0,
      centerTitle: false,
    ),
    drawerTheme: const DrawerThemeData(backgroundColor: KardiaxColors.surface),
    textTheme: const TextTheme(
      displayLarge: TextStyle(
        fontFamily: 'Oswald',
        color: KardiaxColors.textPrimary,
        fontWeight: FontWeight.w700,
      ),
      headlineMedium: TextStyle(
        fontFamily: 'Oswald',
        color: KardiaxColors.textPrimary,
        fontWeight: FontWeight.w600,
      ),
      bodyLarge: TextStyle(
        fontFamily: 'Oswald',
        color: KardiaxColors.textPrimary,
      ),
      bodyMedium: TextStyle(
        fontFamily: 'Oswald',
        color: KardiaxColors.textSecondary,
      ),
    ),
  );
}
