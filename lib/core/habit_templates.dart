import 'package:flutter/painting.dart' show Color;

import 'health.dart';
import 'streak.dart';

/// A ready-made habit the New habit screen can fill in. [target] is a number
/// of completions, or minutes for a timed habit.
class HabitTemplate {
  const HabitTemplate({
    required this.id,
    required this.name,
    required this.iconKey,
    required this.color,
    this.taskType = HabitTaskType.normal,
    this.target = 1,
    this.health = HealthMetric.none,
  });

  final String id;
  final String name;
  final String iconKey;
  final Color color;
  final HabitTaskType taskType;
  final int target;
  final HealthMetric health;
}

const habitTemplates = <HabitTemplate>[
  HabitTemplate(id: 'water', name: 'Drink water', iconKey: 'water', color: Color(0xFF3DA5FF), target: 8),
  HabitTemplate(id: 'steps', name: 'Walk 8,000 steps', iconKey: 'walk', color: Color(0xFF4CC47A), target: 8000, health: HealthMetric.steps),
  HabitTemplate(id: 'read', name: 'Read', iconKey: 'book', color: Color(0xFFFFB347), taskType: HabitTaskType.timed, target: 20),
  HabitTemplate(id: 'meditate', name: 'Meditate', iconKey: 'meditate', color: Color(0xFFC77DFF), taskType: HabitTaskType.timed, target: 10),
  HabitTemplate(id: 'workout', name: 'Workout', iconKey: 'fitness', color: Color(0xFFFF6B2C), taskType: HabitTaskType.timed, target: 30, health: HealthMetric.exercise),
  HabitTemplate(id: 'sleep', name: 'Sleep 8 hours', iconKey: 'sleep', color: Color(0xFF8E7CFF), taskType: HabitTaskType.timed, target: 480, health: HealthMetric.sleep),
  HabitTemplate(id: 'study', name: 'Study', iconKey: 'study', color: Color(0xFF5E9BFF), taskType: HabitTaskType.timed, target: 60),
  HabitTemplate(id: 'code', name: 'Practice coding', iconKey: 'code', color: Color(0xFF2EC4B6), taskType: HabitTaskType.timed, target: 30),
  HabitTemplate(id: 'stretch', name: 'Stretch', iconKey: 'stretch', color: Color(0xFF7BD389), taskType: HabitTaskType.timed, target: 10),
  HabitTemplate(id: 'journal', name: 'Write in my journal', iconKey: 'journal', color: Color(0xFFD08A5B)),
  HabitTemplate(id: 'gratitude', name: 'Note something I am grateful for', iconKey: 'gratitude', color: Color(0xFFF2C037)),
  HabitTemplate(id: 'vitamins', name: 'Take vitamins', iconKey: 'pill', color: Color(0xFFFF8FB1)),
  HabitTemplate(id: 'wake', name: 'Wake up early', iconKey: 'alarm', color: Color(0xFFE9E36A)),
  HabitTemplate(id: 'tidy', name: 'Tidy up', iconKey: 'clean', color: Color(0xFF00B4D8)),
  HabitTemplate(id: 'nosugar', name: 'No sugar', iconKey: 'sweets', color: Color(0xFFFF4D6D), taskType: HabitTaskType.negative),
  HabitTemplate(id: 'nosmoke', name: 'No smoking', iconKey: 'no_smoking', color: Color(0xFFE5383B), taskType: HabitTaskType.negative),
  HabitTemplate(id: 'scroll', name: 'No endless scrolling', iconKey: 'screen_off', color: Color(0xFF9AA7B8), taskType: HabitTaskType.negative),
];
