import 'package:flutter/material.dart';
import 'apariencia.dart';
export 'apariencia.dart';

/// Quiet surfaces and readable ink; pastel colors identify modules, not paragraphs.
class PaletaAlumVid {
  const PaletaAlumVid(this.oscura);
  final bool oscura;
  Color get background =>
      oscura ? const Color(0xFF141820) : const Color(0xFFF5F6FA);
  Color get surface =>
      oscura ? const Color(0xFF1C222D) : const Color(0xFFFFFFFF);
  Color get card => oscura ? const Color(0xFF222A37) : const Color(0xFFFFFFFF);
  Color get cardHigh =>
      oscura ? const Color(0xFF2C3545) : const Color(0xFFEEF0F7);
  Color get border =>
      oscura ? const Color(0xFF364152) : const Color(0xFFE1E5EF);
  Color get primary =>
      oscura ? const Color(0xFFC3B8F5) : const Color(0xFF65549C);
  Color get primaryLight =>
      oscura ? const Color(0xFFB7C8F1) : const Color(0xFF536E9C);
  Color get text => oscura ? const Color(0xFFEAEFF7) : const Color(0xFF273349);
  Color get textMuted =>
      oscura ? const Color(0xFFB0BDCF) : const Color(0xFF617086);
  Color get textDim =>
      oscura ? const Color(0xFF8C9BB2) : const Color(0xFF718096);
  Color get success =>
      oscura ? const Color(0xFF94D6BD) : const Color(0xFF326F5B);
  Color get warning =>
      oscura ? const Color(0xFFE9C994) : const Color(0xFF886027);
  Color get danger =>
      oscura ? const Color(0xFFE9A9B7) : const Color(0xFFA23F59);
  Color get info => primaryLight;
  Color get neutral => textMuted;
  Color get violet => primary;
}

class AppColors {
  static PaletaAlumVid get actual =>
      PaletaAlumVid(Apariencia.instancia.esOscuro);
  static Color get background => actual.background;
  static Color get surface => actual.surface;
  static Color get card => actual.card;
  static Color get cardHigh => actual.cardHigh;
  static Color get border => actual.border;
  static Color get primary => actual.primary;
  static Color get primaryLight => actual.primaryLight;
  static Color get text => actual.text;
  static Color get textMuted => actual.textMuted;
  static Color get textDim => actual.textDim;
  static Color get success => actual.success;
  static Color get warning => actual.warning;
  static Color get danger => actual.danger;
  static Color get info => actual.info;
  static Color get neutral => actual.neutral;
  static Color get violet => actual.violet;
  static const mint = Color(0xFFDBEEE5);
  static const lavender = Color(0xFFE8E1F6);
  static const peach = Color(0xFFF6E5D8);
  static const sky = Color(0xFFDFEAF8);
  static const rose = Color(0xFFF2DFE5);
}

class TemaAlumVid {
  static ThemeData get claro => crear(false);
  static ThemeData get oscuro => crear(true);
  static ThemeData crear(bool oscuro) {
    final p = PaletaAlumVid(oscuro);
    final scheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF8571B2),
      brightness: oscuro ? Brightness.dark : Brightness.light,
      primary: p.primary,
      onPrimary: oscuro ? const Color(0xFF251D3B) : Colors.white,
      secondary: p.primaryLight,
      surface: p.surface,
      onSurface: p.text,
      error: p.danger,
      outline: p.border,
      outlineVariant: p.border,
      surfaceContainerHighest: p.cardHigh,
    );
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: p.background,
    );
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(16),
    );
    return base.copyWith(
      textTheme: base.textTheme.apply(bodyColor: p.text, displayColor: p.text),
      appBarTheme: AppBarTheme(
        backgroundColor: p.background,
        foregroundColor: p.text,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: p.text,
          fontSize: 20,
          fontWeight: FontWeight.w700,
        ),
      ),
      cardTheme: CardThemeData(
        color: p.card,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: p.border),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: p.surface,
        surfaceTintColor: Colors.transparent,
        height: 72,
        indicatorColor: p.primary.withValues(alpha: oscuro ? .22 : .12),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => TextStyle(
            fontSize: 11,
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w700
                : FontWeight.w500,
            color: states.contains(WidgetState.selected)
                ? p.primary
                : p.textMuted,
          ),
        ),
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            color: states.contains(WidgetState.selected)
                ? p.primary
                : p.textMuted,
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: p.background,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 15,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: p.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: p.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: p.primary, width: 1.5),
        ),
        hintStyle: TextStyle(color: p.textDim),
        labelStyle: TextStyle(color: p.textMuted),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(64, 48),
          shape: shape,
          textStyle: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: scheme.primary,
          foregroundColor: scheme.onPrimary,
          elevation: 0,
          minimumSize: const Size(64, 46),
          shape: shape,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: p.text,
          side: BorderSide(color: p.border),
          minimumSize: const Size(64, 46),
          shape: shape,
        ),
      ),
      chipTheme: base.chipTheme.copyWith(
        backgroundColor: p.cardHigh,
        selectedColor: p.primary.withValues(alpha: .12),
        side: BorderSide.none,
        labelStyle: TextStyle(color: p.text, fontSize: 12),
        shape: shape,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: p.surface,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: p.surface,
        surfaceTintColor: Colors.transparent,
        shape: shape,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: oscuro ? p.cardHigh : const Color(0xFF273349),
        contentTextStyle: const TextStyle(color: Color(0xFFF5F6FA)),
      ),
      dividerTheme: DividerThemeData(color: p.border, space: 1),
      listTileTheme: ListTileThemeData(
        iconColor: p.textMuted,
        textColor: p.text,
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 4),
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: p.primary,
        unselectedLabelColor: p.textMuted,
        indicatorColor: p.primary,
        dividerColor: p.border,
        tabAlignment: TabAlignment.start,
      ),
      dataTableTheme: DataTableThemeData(
        headingRowColor: WidgetStatePropertyAll(p.cardHigh),
        headingTextStyle: TextStyle(
          color: p.textMuted,
          fontWeight: FontWeight.w600,
        ),
        dividerThickness: .5,
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: p.text,
          borderRadius: BorderRadius.circular(8),
        ),
        textStyle: TextStyle(color: p.surface),
      ),
    );
  }
}
