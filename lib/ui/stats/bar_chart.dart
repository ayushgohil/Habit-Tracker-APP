import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../../theme/ember_theme.dart';

/// A bar chart you can read at a glance and touch.
///
/// Each value is drawn relative to [maxValue]. Faint guide lines carry
/// [axisTop] and [axisMid] labels, a bar that reaches the top is drawn in full
/// colour (a day whose goal was met), a smaller bar is softer, and an empty slot
/// keeps a small stub so the day is still visible. [valueTexts] puts a short
/// figure above each bar, and touching or dragging across the chart shows the
/// matching entry of [tooltips] above the bar under the finger.
class EmberBarChart extends StatefulWidget {
  const EmberBarChart({
    super.key,
    required this.values,
    required this.labels,
    required this.maxValue,
    required this.color,
    this.labelEvery = 1,
    this.height = 190,
    this.axisTop,
    this.axisMid,
    this.valueTexts,
    this.tooltips,
    this.highlightLast = true,
  });

  final List<double> values;
  final List<String> labels;
  final double maxValue;
  final Color color;
  final int labelEvery;
  final double height;

  /// Labels for the top and middle guide lines (for example `100%` and `50%`).
  final String? axisTop;
  final String? axisMid;

  /// Short text drawn above each bar; an empty string draws nothing.
  final List<String>? valueTexts;

  /// What to show in the bubble when a bar is touched.
  final List<String>? tooltips;

  /// Draws the last label (today) brighter than the rest.
  final bool highlightLast;

  @override
  State<EmberBarChart> createState() => _EmberBarChartState();
}

class _EmberBarChartState extends State<EmberBarChart> {
  int? _selected;

  @override
  void didUpdateWidget(EmberBarChart old) {
    super.didUpdateWidget(old);
    if (old.values.length != widget.values.length) _selected = null;
  }

  void _pick(double dx, double width, {bool toggle = false}) {
    final n = widget.values.length;
    if (n == 0) return;
    final slot = (width - _BarPainter.gutter) / n;
    if (slot <= 0) return;
    final i = ((dx - _BarPainter.gutter) / slot).floor().clamp(0, n - 1);
    setState(() => _selected = toggle && _selected == i ? null : i);
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: widget.height,
      width: double.infinity,
      child: LayoutBuilder(
        builder: (context, box) => GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (d) => _pick(d.localPosition.dx, box.maxWidth, toggle: true),
          onHorizontalDragStart: (d) => _pick(d.localPosition.dx, box.maxWidth),
          onHorizontalDragUpdate: (d) => _pick(d.localPosition.dx, box.maxWidth),
          child: CustomPaint(
            painter: _BarPainter(
              values: widget.values,
              labels: widget.labels,
              maxValue: widget.maxValue <= 0 ? 1 : widget.maxValue,
              color: widget.color,
              labelEvery: widget.labelEvery < 1 ? 1 : widget.labelEvery,
              axisTop: widget.axisTop,
              axisMid: widget.axisMid,
              valueTexts: widget.valueTexts,
              tooltips: widget.tooltips,
              highlightLast: widget.highlightLast,
              selected: _selected,
            ),
          ),
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
    required this.axisTop,
    required this.axisMid,
    required this.valueTexts,
    required this.tooltips,
    required this.highlightLast,
    required this.selected,
  });

  /// Room on the left for the guide-line labels.
  static const gutter = 34.0;

  final List<double> values;
  final List<String> labels;
  final double maxValue;
  final Color color;
  final int labelEvery;
  final String? axisTop;
  final String? axisMid;
  final List<String>? valueTexts;
  final List<String>? tooltips;
  final bool highlightLast;
  final int? selected;

  TextPainter _text(String text, {double size = 10, Color? colour, FontWeight? weight, double? maxWidth}) {
    return TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(color: colour ?? EmberColors.textMuted, fontSize: size, fontWeight: weight),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout(maxWidth: maxWidth ?? double.infinity);
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty) return;
    const labelHeight = 20.0;
    const topPad = 22.0; // room for the figures above the tallest bar
    const chartTop = topPad;
    final chartHeight = size.height - labelHeight - topPad;
    final plotWidth = size.width - gutter;
    final slot = plotWidth / values.length;
    final barWidth = (slot * 0.62).clamp(3.0, 28.0);
    final baseline = chartTop + chartHeight;

    // Guide lines: top, middle and the baseline.
    final guide = Paint()
      ..color = EmberColors.track
      ..strokeWidth = 1;
    void line(double y, String? label, {bool dashed = true}) {
      if (dashed) {
        for (var x = gutter; x < size.width; x += 8) {
          canvas.drawLine(Offset(x, y), Offset(math.min(x + 4, size.width), y), guide);
        }
      } else {
        canvas.drawLine(Offset(gutter, y), Offset(size.width, y), guide);
      }
      if (label != null) {
        final tp = _text(label, size: 10);
        tp.paint(canvas, Offset(gutter - 6 - tp.width, y - tp.height / 2));
      }
    }

    line(chartTop, axisTop);
    if (axisMid != null) line(chartTop + chartHeight / 2, axisMid);
    line(baseline, '0', dashed: false);

    for (var i = 0; i < values.length; i++) {
      final x = gutter + slot * i + (slot - barWidth) / 2;
      final radius = Radius.circular(barWidth / 3);
      final share = (values[i] / maxValue).clamp(0.0, 1.0);
      final full = share >= 0.999;
      final isSelected = selected == i;
      final h = values[i] <= 0 ? 3.0 : math.max(chartHeight * share, 4.0);

      final base = values[i] <= 0
          ? EmberColors.track
          : (full || isSelected ? color : color.withValues(alpha: .55));
      canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTWH(x, baseline - h, barWidth, h), radius),
        Paint()..color = base,
      );
      if (isSelected) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(Rect.fromLTWH(x - 2, baseline - h - 2, barWidth + 4, h + 4), radius),
          Paint()
            ..color = color
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5,
        );
      }

      // The figure above a bar. A selected bar shows its bubble instead.
      final figure = valueTexts != null && i < valueTexts!.length ? valueTexts![i] : '';
      if (figure.isNotEmpty && !isSelected) {
        final tp = _text(figure, size: 10, colour: EmberColors.text, weight: FontWeight.w600, maxWidth: slot * 1.4);
        tp.paint(canvas, Offset(gutter + slot * i + (slot - tp.width) / 2, baseline - h - tp.height - 3));
      }

      if (i % labelEvery == 0 && i < labels.length) {
        final today = highlightLast && i == values.length - 1;
        final tp = _text(
          labels[i],
          size: 10,
          colour: today || isSelected ? EmberColors.text : EmberColors.textMuted,
          weight: today || isSelected ? FontWeight.w700 : null,
          maxWidth: slot * labelEvery,
        );
        tp.paint(canvas, Offset(gutter + slot * i + (slot - tp.width) / 2, baseline + 5));
      }
    }

    // The bubble for the touched bar, kept inside the chart.
    final sel = selected;
    if (sel != null && tooltips != null && sel < tooltips!.length) {
      final tp = _text(tooltips![sel], size: 12, colour: EmberColors.text, weight: FontWeight.w600);
      final w = tp.width + 20;
      const h = 28.0;
      final centre = gutter + slot * sel + slot / 2;
      final left = (centre - w / 2).clamp(gutter, math.max(gutter, size.width - w)).toDouble();
      final barTop = baseline - (values[sel] <= 0 ? 3.0 : math.max(chartHeight * (values[sel] / maxValue).clamp(0.0, 1.0), 4.0));
      final top = math.max(0.0, barTop - h - 8);
      final rect = RRect.fromRectAndRadius(Rect.fromLTWH(left, top, w, h), const Radius.circular(10));
      canvas.drawRRect(rect, Paint()..color = EmberColors.surfaceHigh);
      canvas.drawRRect(
        rect,
        Paint()
          ..color = color.withValues(alpha: .6)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1,
      );
      tp.paint(canvas, Offset(left + 10, top + (h - tp.height) / 2));
    }
  }

  @override
  bool shouldRepaint(_BarPainter old) =>
      old.values != values ||
      old.labels != labels ||
      old.maxValue != maxValue ||
      old.color != color ||
      old.selected != selected ||
      old.valueTexts != valueTexts ||
      old.tooltips != tooltips ||
      old.axisTop != axisTop ||
      old.axisMid != axisMid;
}
