import 'package:flutter/material.dart';

/// Habit icons are stored by key (not code point) so release builds can
/// tree-shake the icon font.
const Map<String, IconData> habitIcons = {
  'flame': Icons.local_fire_department_rounded,
  'water': Icons.water_drop_rounded,
  'fitness': Icons.fitness_center_rounded,
  'run': Icons.directions_run_rounded,
  'walk': Icons.directions_walk_rounded,
  'meditate': Icons.self_improvement_rounded,
  'sleep': Icons.bedtime_rounded,
  'sun': Icons.wb_sunny_rounded,
  'book': Icons.menu_book_rounded,
  'study': Icons.school_rounded,
  'write': Icons.edit_rounded,
  'code': Icons.code_rounded,
  'music': Icons.music_note_rounded,
  'food': Icons.restaurant_rounded,
  'pill': Icons.medication_rounded,
  'clean': Icons.cleaning_services_rounded,
  'savings': Icons.savings_rounded,
  'no_phone': Icons.phone_disabled_rounded,
};

IconData habitIconFor(String key) =>
    habitIcons[key] ?? Icons.local_fire_department_rounded;
