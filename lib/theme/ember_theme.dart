import 'package:flutter/material.dart';

/// Ember's own palette: warm charcoal surfaces with a glowing orange accent.
class EmberColors {
  EmberColors._();

  static const background = Color(0xFF14110F);
  static const surface = Color(0xFF211B18);
  static const surfaceHigh = Color(0xFF2C2420);
  static const track = Color(0xFF3A302B);
  static const ember = Color(0xFFFF6B2C);
  static const glow = Color(0xFFFFB347);
  static const onEmber = Color(0xFF1A0E08);
  static const text = Color(0xFFF6EFEA);
  static const textMuted = Color(0xFFA89B93);
}

/// Colours a habit can be given.
const habitPalette = <Color>[
  Color(0xFFFF6B2C),
  Color(0xFFFFB347),
  Color(0xFFFF4D6D),
  Color(0xFFC77DFF),
  Color(0xFF5E9BFF),
  Color(0xFF2EC4B6),
  Color(0xFF7BD389),
  Color(0xFFE9E36A),
];

ThemeData emberTheme() {
  const scheme = ColorScheme.dark(
    primary: EmberColors.ember,
    onPrimary: EmberColors.onEmber,
    secondary: EmberColors.glow,
    surface: EmberColors.surface,
    onSurface: EmberColors.text,
  );

  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: scheme,
    scaffoldBackgroundColor: EmberColors.background,
    appBarTheme: const AppBarTheme(
      backgroundColor: EmberColors.background,
      surfaceTintColor: Colors.transparent,
      foregroundColor: EmberColors.text,
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: EmberColors.ember,
      foregroundColor: EmberColors.onEmber,
      shape: CircleBorder(),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: EmberColors.surface,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide.none,
      ),
    ),
  );
}
