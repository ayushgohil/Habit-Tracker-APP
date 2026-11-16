import 'package:material_ui/material_ui.dart';

import '../../theme/ember_theme.dart';
import 'ring_painter.dart';

/// One habit on the home grid: a progress ring around its icon, the name
/// beneath, and the current streak.
class HabitTile extends StatelessWidget {
  const HabitTile({
    super.key,
    required this.name,
    required this.icon,
    required this.color,
    required this.progress,
    required this.streakLabel,
    required this.streakActive,
    required this.onTap,
    required this.onLongPress,
  });

  final String name;
  final IconData icon;
  final Color color;
  final double progress;
  final String streakLabel;
  final bool streakActive;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  bool get _done => progress >= 1;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      onLongPress: onLongPress,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AspectRatio(
            aspectRatio: 1,
            child: TweenAnimationBuilder<double>(
              tween: Tween<double>(begin: 0, end: progress),
              duration: const Duration(milliseconds: 450),
              curve: Curves.easeOutCubic,
              builder: (context, value, child) => CustomPaint(
                painter: RingPainter(
                  progress: value,
                  color: color,
                  trackColor: EmberColors.track,
                ),
                child: child,
              ),
              child: Padding(
                padding: const EdgeInsets.all(11),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _done ? color : EmberColors.surface,
                  ),
                  child: Center(
                    child: Icon(
                      _done ? Icons.check_rounded : icon,
                      size: 30,
                      color: _done ? EmberColors.background : color,
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 2),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.local_fire_department_rounded,
                size: 14,
                color: streakActive ? EmberColors.glow : EmberColors.textMuted,
              ),
              const SizedBox(width: 2),
              Text(
                streakLabel,
                style: textTheme.bodySmall?.copyWith(
                  color:
                      streakActive ? EmberColors.glow : EmberColors.textMuted,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
