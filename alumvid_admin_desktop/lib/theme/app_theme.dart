import 'package:flutter/material.dart';
import '../shared/tema.dart';
export '../shared/apariencia.dart';

/// Compatibility names for the logistics screens; both shells use the same palette.
class AppTheme {
  static Color get background => AppColors.background;
  static Color get bgDark => AppColors.background;
  static Color get surface => AppColors.surface;
  static Color get surfaceDark => AppColors.surface;
  static Color get surfaceCard => AppColors.card;
  static Color get surfaceCardHover => AppColors.cardHigh;
  static Color get border => AppColors.border;
  static Color get primary => AppColors.primary;
  static Color get primaryLight => AppColors.primaryLight;
  static Color get accent => AppColors.info;
  static Color get textMain => AppColors.text;
  static Color get textMuted => AppColors.textMuted;
  static Color get textDim => AppColors.textDim;
  static Color get statusPendiente => AppColors.info;
  static Color get statusEnCurso => AppColors.warning;
  static Color get statusCompletada => AppColors.success;
  static Color get statusAlerta => AppColors.danger;
  static Color get statusCancelada => AppColors.neutral;
  static ThemeData get darkTheme => TemaAlumVid.oscuro;
  static ThemeData get lightTheme => TemaAlumVid.claro;
}
