import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/habit_icons.dart';
import '../../theme/ember_theme.dart';

/// Shown once after a habit is created: a check mark that draws itself, a
/// burst of confetti and a short message. It plays for about two seconds and
/// then stands still, and is skipped (shown finished) when the phone asks for
/// reduced motion.
class HabitCreatedScreen extends StatefulWidget {
  const HabitCreatedScreen({
    super.key,
    required this.name,
    required this.iconKey,
    required this.color,
    required this.scheduleText,
    required this.startDate,
    required this.startsToday,
  });

  final String name;
  final String iconKey;
  final Color color;

  /// How often the habit repeats, for example "Every day" or "Mon, Wed, Fri".
  final String scheduleText;
  final DateTime startDate;
  final bool startsToday;

  @override
  State<HabitCreatedScreen> createState() => _HabitCreatedScreenState();
}

class _HabitCreatedScreenState extends State<HabitCreatedScreen> with SingleTickerProviderStateMixin {
  late final AnimationController _controller =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 2200));
  bool _started = false;

  @override
  void initState() {
    super.initState();
    HapticFeedback.mediumImpact();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.value = 1;
    } else {
      _controller.forward();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final firstCheckIn = widget.startsToday
        ? 'Your first check-in is today. Make it count.'
        : 'Your first check-in is on ${DateFormat('EEEE, d MMM').format(widget.startDate)}.';
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        actions: [
          IconButton(
            tooltip: 'Close',
            icon: const Icon(Icons.close_rounded),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(28, 0, 28, 20),
          child: Column(
            children: [
              const Spacer(),
              AnimatedBuilder(
                animation: _controller,
                builder: (context, _) => SizedBox(
                  width: 260,
                  height: 220,
                  child: CustomPaint(
                    key: const Key('celebration'),
                    painter: _CelebrationPainter(
                      progress: _controller.value,
                      color: widget.color,
                      background: EmberColors.surface,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              _Rise(
                controller: _controller,
                from: .35,
                child: Text('Habit created!', style: textTheme.headlineSmall, textAlign: TextAlign.center),
              ),
              const SizedBox(height: 10),
              _Rise(
                controller: _controller,
                from: .45,
                child: Column(
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(habitIconFor(widget.iconKey), size: 20, color: widget.color),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            widget.name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: textTheme.titleMedium,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '${widget.scheduleText}. $firstCheckIn',
                      textAlign: TextAlign.center,
                      style: textTheme.bodyMedium?.copyWith(color: EmberColors.textMuted),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              _Rise(
                controller: _controller,
                from: .55,
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    key: const Key('celebration-done'),
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Padding(
                      padding: EdgeInsets.symmetric(vertical: 14),
                      child: Text("Let's go"),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Fades and lifts its child in once the animation passes [from].
class _Rise extends StatelessWidget {
  const _Rise({required this.controller, required this.from, required this.child});
  final AnimationController controller;
  final double from;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      child: child,
      builder: (context, child) {
        final t = Curves.easeOutCubic.transform(((controller.value - from) / .25).clamp(0.0, 1.0));
        return Opacity(
          opacity: t,
          child: Transform.translate(offset: Offset(0, (1 - t) * 14), child: child),
        );
      },
    );
  }
}

/// A disc that pops in, a ring around it, a check mark that draws itself and
/// confetti flying out from behind it.
class _CelebrationPainter extends CustomPainter {
  _CelebrationPainter({required this.progress, required this.color, required this.background});

  final double progress;
  final Color color;
  final Color background;

  static const _confettiCount = 34;

  @override
  void paint(Canvas canvas, Size size) {
    final centre = Offset(size.width / 2, size.height / 2);
    const radius = 56.0;

    // Confetti first, so the disc sits on top of it.
    final random = math.Random(11);
    final palette = <Color>[
      color,
      const Color(0xFFFFB347),
      const Color(0xFFFF4D6D),
      const Color(0xFF5E9BFF),
      const Color(0xFF2EC4B6),
      const Color(0xFFC77DFF),
    ];
    final burst = ((progress - .1) / .9).clamp(0.0, 1.0);
    if (burst > 0) {
      for (var i = 0; i < _confettiCount; i++) {
        final angle = (i / _confettiCount) * math.pi * 2 + random.nextDouble() * .5;
        final speed = 70 + random.nextDouble() * 90;
        final spin = random.nextDouble() * math.pi * 2;
        final w = 4 + random.nextDouble() * 4;
        final colour = palette[i % palette.length];
        final travel = Curves.easeOutCubic.transform(burst);
        final fall = burst * burst * 46;
        final position = centre +
            Offset(math.cos(angle) * (radius + speed * travel), math.sin(angle) * (radius + speed * travel) + fall);
        final fade = (1 - ((burst - .65) / .35).clamp(0.0, 1.0));
        canvas.save();
        canvas.translate(position.dx, position.dy);
        canvas.rotate(spin + burst * 6);
        canvas.drawRRect(
          RRect.fromRectAndRadius(Rect.fromCenter(center: Offset.zero, width: w, height: w * 1.8), const Radius.circular(1.5)),
          Paint()..color = colour.withValues(alpha: fade),
        );
        canvas.restore();
      }
    }

    // The disc pops in with a small overshoot.
    final pop = Curves.elasticOut.transform((progress / .35).clamp(0.0, 1.0));
    canvas.drawCircle(centre, radius * pop, Paint()..color = color);
    canvas.drawCircle(
      centre,
      (radius + 12) * pop,
      Paint()
        ..color = color.withValues(alpha: .35)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );

    // The check mark draws itself.
    final draw = Curves.easeInOut.transform(((progress - .2) / .3).clamp(0.0, 1.0));
    if (draw > 0) {
      final path = Path()
        ..moveTo(centre.dx - 22, centre.dy + 2)
        ..lineTo(centre.dx - 7, centre.dy + 17)
        ..lineTo(centre.dx + 24, centre.dy - 16);
      final metric = path.computeMetrics().first;
      final on = ThemeData.estimateBrightnessForColor(color) == Brightness.dark ? Colors.white : const Color(0xFF1B1B1B);
      canvas.drawPath(
        metric.extractPath(0, metric.length * draw),
        Paint()
          ..color = on
          ..style = PaintingStyle.stroke
          ..strokeWidth = 8
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round,
      );
    }
  }

  @override
  bool shouldRepaint(_CelebrationPainter old) =>
      old.progress != progress || old.color != color || old.background != background;
}
