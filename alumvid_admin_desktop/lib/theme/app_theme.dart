import 'package:flutter/material.dart';

class AppTheme {
  static const Color background = Color(0xFF0A0E17);
  static const Color surface = Color(0xFF111827);
  static const Color surfaceCard = Color(0xFF1E293B);
  static const Color surfaceCardHover = Color(0xFF283548);
  static const Color border = Color(0xFF334155);

  static const Color primary = Color(0xFF2563EB);
  static const Color primaryLight = Color(0xFF38BDF8);
  static const Color accent = Color(0xFF60A5FA);

  static const Color statusPendiente = Color(0xFF38BDF8);
  static const Color statusEnCurso = Color(0xFFF59E0B);
  static const Color statusCompletada = Color(0xFF10B981);
  static const Color statusAlerta = Color(0xFFF43F5E);
  static const Color statusCancelada = Color(0xFF64748B);

  static const Color textMain = Color(0xFFF8FAFC);
  static const Color textMuted = Color(0xFF94A3B8);
  static const Color textDim = Color(0xFF64748B);

  static ThemeData darkTheme = ThemeData(
    brightness: Brightness.dark,
    scaffoldBackgroundColor: background,
    primaryColor: primary,
    colorScheme: const ColorScheme.dark(
      primary: primary,
      secondary: primaryLight,
      surface: surface,
    ),
    cardTheme: CardThemeData(
      color: surfaceCard,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: border, width: 1),
      ),
      elevation: 3,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: surface,
      elevation: 0,
      centerTitle: false,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: surface,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: primaryLight, width: 1.5),
      ),
      hintStyle: const TextStyle(color: textDim, fontSize: 13),
      labelStyle: const TextStyle(color: textMuted, fontSize: 13),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: primary,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        elevation: 2,
        textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: const Color(0xF20F172A),
      elevation: 6,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: const BorderSide(color: border),
      ),
      contentTextStyle: const TextStyle(
        color: Color(0xFFF1F5F9),
        fontSize: 12.5,
        fontWeight: FontWeight.w500,
      ),
    ),
  );
}
