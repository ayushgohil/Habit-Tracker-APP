import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

/// One complete look for the app: surfaces, accent and text colours.
class EmberPalette {
  const EmberPalette({
    required this.id,
    required this.name,
    required this.background,
    required this.surface,
    required this.surfaceHigh,
    required this.track,
    required this.accent,
    required this.glow,
    required this.onAccent,
    required this.text,
    required this.textMuted,
    this.dark = true,
  });

  final String id;
  final String name;
  final Color background;
  final Color surface;
  final Color surfaceHigh;
  final Color track;
  final Color accent;
  final Color glow;
  final Color onAccent;
  final Color text;
  final Color textMuted;
  final bool dark;

  /// A dark look worked out from a background and two accent colours: the
  /// surfaces step up from the background, and text is near white.
  factory EmberPalette.fromDark({
    required String id,
    required String name,
    required int background,
    required int accent,
    required int glow,
  }) {
    final bg = Color(0xFF000000 | background);
    final text = Color.lerp(const Color(0xFFFFFFFF), Color(0xFF000000 | accent), 0.05)!;
    return EmberPalette(
      id: id,
      name: name,
      background: bg,
      surface: Color.lerp(bg, const Color(0xFFFFFFFF), 0.06)!,
      surfaceHigh: Color.lerp(bg, const Color(0xFFFFFFFF), 0.11)!,
      track: Color.lerp(bg, const Color(0xFFFFFFFF), 0.18)!,
      accent: Color(0xFF000000 | accent),
      glow: Color(0xFF000000 | glow),
      onAccent: _readableOn(Color(0xFF000000 | accent)),
      text: text,
      textMuted: Color.lerp(text, bg, 0.45)!,
    );
  }

  /// A light look: white cards on a tinted background, near-black text, and a
  /// darker second colour for streaks and highlights.
  factory EmberPalette.fromLight({
    required String id,
    required String name,
    required int background,
    required int accent,
    required int glow,
  }) {
    final bg = Color(0xFF000000 | background);
    final text = Color.lerp(const Color(0xFF000000), Color(0xFF000000 | accent), 0.12)!;
    return EmberPalette(
      id: id,
      name: name,
      dark: false,
      background: bg,
      surface: const Color(0xFFFFFFFF),
      surfaceHigh: Color.lerp(bg, const Color(0xFF000000), 0.04)!,
      track: Color.lerp(bg, const Color(0xFF000000), 0.12)!,
      accent: Color(0xFF000000 | accent),
      glow: Color(0xFF000000 | glow),
      onAccent: _readableOn(Color(0xFF000000 | accent)),
      text: text,
      textMuted: Color.lerp(text, bg, 0.4)!,
    );
  }
}

/// White or near-black, whichever reads better on [accent].
Color _readableOn(Color accent) {
  const dark = Color(0xFF14110F);
  const light = Color(0xFFFFFFFF);
  double contrast(Color a, Color b) {
    final la = a.computeLuminance();
    final lb = b.computeLuminance();
    return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
  }

  return contrast(accent, dark) >= contrast(accent, light) ? dark : light;
}

const _originalPalettes = <EmberPalette>[
  EmberPalette(
    id: 'ember', name: 'Ember',
    background: Color(0xFF14110F), surface: Color(0xFF211B18), surfaceHigh: Color(0xFF2C2420), track: Color(0xFF3A302B),
    accent: Color(0xFFFF6B2C), glow: Color(0xFFFFB347), onAccent: Color(0xFF1A0E08),
    text: Color(0xFFF6EFEA), textMuted: Color(0xFFA89B93),
  ),
  EmberPalette(
    id: 'amoled', name: 'Black',
    background: Color(0xFF000000), surface: Color(0xFF0E0E0E), surfaceHigh: Color(0xFF191919), track: Color(0xFF2A2A2A),
    accent: Color(0xFFFF6B2C), glow: Color(0xFFFFB347), onAccent: Color(0xFF1A0E08),
    text: Color(0xFFF6F6F6), textMuted: Color(0xFF9A9A9A),
  ),
  EmberPalette(
    id: 'ocean', name: 'Ocean',
    background: Color(0xFF0D1318), surface: Color(0xFF16202A), surfaceHigh: Color(0xFF1F2C38), track: Color(0xFF2B3A48),
    accent: Color(0xFF3DA5FF), glow: Color(0xFF7FD1FF), onAccent: Color(0xFF04121F),
    text: Color(0xFFEAF3FA), textMuted: Color(0xFF8EA3B3),
  ),
  EmberPalette(
    id: 'forest', name: 'Forest',
    background: Color(0xFF0E1410), surface: Color(0xFF18231C), surfaceHigh: Color(0xFF223127), track: Color(0xFF2E4235),
    accent: Color(0xFF4CC47A), glow: Color(0xFFB5E86B), onAccent: Color(0xFF07140B),
    text: Color(0xFFEBF5EE), textMuted: Color(0xFF90A89A),
  ),
  EmberPalette(
    id: 'mint', name: 'Mint',
    background: Color(0xFF0C1514), surface: Color(0xFF142320), surfaceHigh: Color(0xFF1D312E), track: Color(0xFF2A4440),
    accent: Color(0xFF2EC4B6), glow: Color(0xFF8CF0E4), onAccent: Color(0xFF021412),
    text: Color(0xFFE8F6F4), textMuted: Color(0xFF8CA8A4),
  ),
  EmberPalette(
    id: 'violet', name: 'Violet',
    background: Color(0xFF120F18), surface: Color(0xFF1D1827), surfaceHigh: Color(0xFF292233), track: Color(0xFF372F45),
    accent: Color(0xFFA678FF), glow: Color(0xFFD2B8FF), onAccent: Color(0xFF140A26),
    text: Color(0xFFF1ECF9), textMuted: Color(0xFF9F96B3),
  ),
  EmberPalette(
    id: 'rose', name: 'Rose',
    background: Color(0xFF170F13), surface: Color(0xFF241A1F), surfaceHigh: Color(0xFF30222A), track: Color(0xFF40303A),
    accent: Color(0xFFFF5C8A), glow: Color(0xFFFFA3C0), onAccent: Color(0xFF1F0610),
    text: Color(0xFFF8ECF0), textMuted: Color(0xFFB09AA3),
  ),
  EmberPalette(
    id: 'crimson', name: 'Crimson',
    background: Color(0xFF160E0E), surface: Color(0xFF241717), surfaceHigh: Color(0xFF312020), track: Color(0xFF432E2E),
    accent: Color(0xFFE5383B), glow: Color(0xFFFF8A80), onAccent: Color(0xFF1F0506),
    text: Color(0xFFF8ECEC), textMuted: Color(0xFFB09A9A),
  ),
  EmberPalette(
    id: 'gold', name: 'Gold',
    background: Color(0xFF14120B), surface: Color(0xFF211E12), surfaceHigh: Color(0xFF2D2918), track: Color(0xFF3D3720),
    accent: Color(0xFFF2C037), glow: Color(0xFFFFE08A), onAccent: Color(0xFF1A1400),
    text: Color(0xFFF8F3E3), textMuted: Color(0xFFA9A184),
  ),
  EmberPalette(
    id: 'slate', name: 'Slate',
    background: Color(0xFF121315), surface: Color(0xFF1C1E21), surfaceHigh: Color(0xFF272A2E), track: Color(0xFF363A40),
    accent: Color(0xFF9AA7B8), glow: Color(0xFFD0D9E6), onAccent: Color(0xFF0E1116),
    text: Color(0xFFEDEFF2), textMuted: Color(0xFF8E96A1),
  ),
  EmberPalette(
    id: 'paper', name: 'Paper', dark: false,
    background: Color(0xFFFAF6F1), surface: Color(0xFFFFFFFF), surfaceHigh: Color(0xFFF0EAE3), track: Color(0xFFE2D9CF),
    accent: Color(0xFFE8571A), glow: Color(0xFFB86A00), onAccent: Color(0xFFFFFFFF),
    text: Color(0xFF211B18), textMuted: Color(0xFF7A6E66),
  ),
  EmberPalette(
    id: 'daylight', name: 'Daylight', dark: false,
    background: Color(0xFFF3F7FB), surface: Color(0xFFFFFFFF), surfaceHigh: Color(0xFFE8EFF6), track: Color(0xFFD3DEE9),
    accent: Color(0xFF2E7DE8), glow: Color(0xFF1766C2), onAccent: Color(0xFFFFFFFF),
    text: Color(0xFF14202B), textMuted: Color(0xFF62707E),
  ),
];

/// Every look, the hand-made ones first. New ones are added at the end.
final emberPalettes = <EmberPalette>[
  ..._originalPalettes,
  EmberPalette.fromDark(id: 'midnight', name: 'Midnight', background: 0x0B1020, accent: 0x5B8CFF, glow: 0xA5C0FF),
  EmberPalette.fromDark(id: 'sunset', name: 'Sunset', background: 0x1A1012, accent: 0xFF7A59, glow: 0xFFC371),
  EmberPalette.fromDark(id: 'dusk', name: 'Dusk', background: 0x151221, accent: 0x9D7BFF, glow: 0xF2A7E0),
  EmberPalette.fromDark(id: 'berry', name: 'Berry', background: 0x190F1A, accent: 0xE04DB0, glow: 0xFF9ADA),
  EmberPalette.fromDark(id: 'aqua', name: 'Aqua', background: 0x0A1417, accent: 0x22D3EE, glow: 0x8BF0FF),
  EmberPalette.fromDark(id: 'lime', name: 'Lime', background: 0x101407, accent: 0xA3E635, glow: 0xE4FF8A),
  EmberPalette.fromDark(id: 'coral', name: 'Coral', background: 0x1A0F0E, accent: 0xFF7F6B, glow: 0xFFBE98),
  EmberPalette.fromDark(id: 'indigo', name: 'Indigo', background: 0x0E0F1F, accent: 0x6D70F5, glow: 0xB3B5FF),
  EmberPalette.fromDark(id: 'copper', name: 'Copper', background: 0x17110D, accent: 0xD98A4E, glow: 0xF3C79A),
  EmberPalette.fromDark(id: 'sakura', name: 'Sakura', background: 0x1A1115, accent: 0xF59EC9, glow: 0xFFD3E8),
  EmberPalette.fromDark(id: 'emerald', name: 'Emerald', background: 0x08130E, accent: 0x10B981, glow: 0x6EE7B7),
  EmberPalette.fromDark(id: 'sand', name: 'Sand', background: 0x16130E, accent: 0xE0B979, glow: 0xF7E2B8),
  EmberPalette.fromDark(id: 'steel', name: 'Steel', background: 0x0F141A, accent: 0x7AA2D6, glow: 0xBBD6F5),
  EmberPalette.fromDark(id: 'neon', name: 'Neon', background: 0x0A0A12, accent: 0x00F5A0, glow: 0x00D1FF),
  EmberPalette.fromLight(id: 'cream', name: 'Cream', background: 0xFBF7EE, accent: 0xC2410C, glow: 0x9A3412),
  EmberPalette.fromLight(id: 'sky', name: 'Sky', background: 0xEEF6FC, accent: 0x0369A1, glow: 0x075985),
  EmberPalette.fromLight(id: 'blush', name: 'Blush', background: 0xFDF2F4, accent: 0xBE185D, glow: 0x9D174D),
  EmberPalette.fromLight(id: 'meadow', name: 'Meadow', background: 0xF1F8F2, accent: 0x2B8A4F, glow: 0x1F6B3B),
  EmberPalette.fromLight(id: 'lilac', name: 'Lilac', background: 0xF5F1FC, accent: 0x6D3FE0, glow: 0x5B21B6),
  EmberPalette.fromLight(id: 'lemon', name: 'Lemon', background: 0xFFFBEA, accent: 0xA16207, glow: 0x854D0E),
];

EmberPalette paletteById(String? id) =>
    emberPalettes.where((p) => p.id == id).firstOrNull ?? emberPalettes.first;

/// The colours of the look that is currently selected. They are read when
/// widgets build, and the app rebuilds everything when the look changes.
class EmberColors {
  EmberColors._();

  static EmberPalette _palette = emberPalettes.first;

  static EmberPalette get palette => _palette;
  static void use(EmberPalette palette) => _palette = palette;

  static Color get background => _palette.background;
  static Color get surface => _palette.surface;
  static Color get surfaceHigh => _palette.surfaceHigh;
  static Color get track => _palette.track;
  static Color get ember => _palette.accent;
  static Color get glow => _palette.glow;
  static Color get onEmber => _palette.onAccent;
  static Color get text => _palette.text;
  static Color get textMuted => _palette.textMuted;
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
  Color(0xFFE5383B),
  Color(0xFFFF8FB1),
  Color(0xFF8E7CFF),
  Color(0xFF3DA5FF),
  Color(0xFF00B4D8),
  Color(0xFF4CC47A),
  Color(0xFFA3C93A),
  Color(0xFFF2C037),
  Color(0xFFD08A5B),
  Color(0xFF9AA7B8),
  Color(0xFFB5838D),
  Color(0xFFF4F1EA),
];

ThemeData emberTheme([EmberPalette? palette]) {
  final p = palette ?? EmberColors.palette;
  final base = p.dark
      ? ColorScheme.dark(
          primary: p.accent,
          onPrimary: p.onAccent,
          secondary: p.glow,
          surface: p.surface,
          onSurface: p.text,
          surfaceContainerHighest: p.surfaceHigh,
          surfaceContainerHigh: p.surfaceHigh,
          surfaceContainer: p.surface,
        )
      : ColorScheme.light(
          primary: p.accent,
          onPrimary: p.onAccent,
          secondary: p.glow,
          surface: p.surface,
          onSurface: p.text,
          surfaceContainerHighest: p.surfaceHigh,
          surfaceContainerHigh: p.surfaceHigh,
          surfaceContainer: p.surface,
        );

  return ThemeData(
    useMaterial3: true,
    brightness: p.dark ? Brightness.dark : Brightness.light,
    colorScheme: base,
    scaffoldBackgroundColor: p.background,
    appBarTheme: AppBarTheme(
      backgroundColor: p.background,
      surfaceTintColor: Colors.transparent,
      foregroundColor: p.text,
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: p.accent,
      foregroundColor: p.onAccent,
      shape: const CircleBorder(),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: p.surface,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide.none,
      ),
    ),
  );
}
