import 'package:material_ui/material_ui.dart';

import '../../theme/ember_theme.dart';

/// A small bar chart. Each value is drawn relative to [maxValue]; labels are
/// shown under every [labelEvery]-th bar.
class EmberBarChart extends StatelessWidget {
  const EmberBarChart({
    super.key,
    required this.values,
    required this.labels,
    required this.maxValue,
    required this.color,
    this.labelEvery = 1,
    this.height = 140,
  });

  final List<double> values;
  final List<String> labels;
  final double maxValue;
  final Color color;
  final int labelEvery;
  final double height;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      width: double.infinity,
      child: CustomPaint(
        painter: _BarPainter(
          values: values,
          labels: labels,
          maxValue: maxValue <= 0 ? 1 : maxValue,
          color: color,
          labelEvery: labelEvery < 1 ? 1 : labelEvery,
        ),
      ),
    );
  }
}

class _BarPainter extends CustomPainter {
  _BarPainter({
    required this.values,
    required this.labels,
    required this.maxValue,
    required this.color,
    required this.labelEvery,
  });

  final List<double> values;
  final List<String> labels;
  final double maxValue;
  final Color color;
  final int labelEvery;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty) return;
    const labelHeight = 18.0;
    final chartHeight = size.height - labelHeight;
    final slot = size.width / values.length;
    final barWidth = (slot * 0.62).clamp(2.0, 28.0);
    final track = Paint()..color = EmberColors.track;
    final fill = Paint()..color = color;

    for (var i = 0; i < values.length; i++) {
      final x = slot * i + (slot - barWidth) / 2;
      final radius = Radius.circular(barWidth / 3);
      canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTWH(x, 0, barWidth, chartHeight), radius),
        track,
      );
      final h = chartHeight * (values[i] / maxValue).clamp(0.0, 1.0);
      if (h > 0) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(x, chartHeight - h, barWidth, h),
            radius,
          ),
          fill,
        );
      }
      if (i % labelEvery == 0 && i < labels.length) {
        final tp = TextPainter(
          text: TextSpan(
            text: labels[i],
            style: const TextStyle(color: EmberColors.textMuted, fontSize: 10),
          ),
          textDirection: TextDirection.ltr,
        )..layout(maxWidth: slot * labelEvery);
        tp.paint(canvas, Offset(slot * i + (slot - tp.width) / 2, chartHeight + 4));
      }
    }
  }

  @override
  bool shouldRepaint(_BarPainter old) =>
      old.values != values || old.labels != labels || old.maxValue != maxValue || old.color != color;
}
