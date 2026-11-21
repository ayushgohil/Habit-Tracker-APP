/// Draws the card-style home-screen widgets onto a canvas and encodes them as
/// PNG. The Android side shows these images on a rounded background, so only
/// the marks are drawn here, in one ink colour.
library;

import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:material_ui/material_ui.dart' show Icons;

import '../core/habit_icons.dart';
import 'card_data.dart';

/// Width and height of every card image, in pixels.
const cardSize = 400.0;

/// Renders [kind] for [habits] (one habit, or several for the grid) to PNG bytes.
/// With [whiteInk] the marks are white, for coloured and glass backgrounds;
/// otherwise each habit is drawn in its own colour, for the dark background.
Future<Uint8List> renderCardPng(CardKind kind, List<CardHabit> habits, {required bool whiteInk}) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder, const Rect.fromLTWH(0, 0, cardSize, cardSize));
  paintCard(canvas, kind, habits, whiteInk: whiteInk);
  final image = await recorder.endRecording().toImage(cardSize.toInt(), cardSize.toInt());
  try {
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    return data!.buffer.asUint8List();
  } finally {
    image.dispose();
  }
}

void paintCard(Canvas canvas, CardKind kind, List<CardHabit> habits, {required bool whiteInk}) {
  if (habits.isEmpty) return;
  Color inkOf(CardHabit h) => whiteInk ? const Color(0xFFFFFFFF) : Color(h.colorValue);
  final habit = habits.first;
  switch (kind) {
    case CardKind.streak:
      _streak(canvas, habit, inkOf(habit));
    case CardKind.ring:
      _ring(canvas, habit, inkOf(habit));
    case CardKind.week:
      _week(canvas, habit, inkOf(habit));
    case CardKind.trend:
      _trend(canvas, habit, inkOf(habit));
    case CardKind.month:
      _month(canvas, habit, inkOf(habit));
    case CardKind.grid:
      _grid(canvas, habits.take(6).toList(), inkOf);
  }
}

void _text(Canvas canvas, String text, Offset center, double size, Color color,
    {FontWeight weight = FontWeight.w600, double maxWidth = cardSize - 32}) {
  final painter = TextPainter(
    text: TextSpan(text: text, style: TextStyle(fontSize: size, color: color, fontWeight: weight, height: 1.0)),
    textDirection: TextDirection.ltr,
    maxLines: 1,
    ellipsis: '…',
  )..layout(maxWidth: maxWidth);
  painter.paint(canvas, center - Offset(painter.width / 2, painter.height / 2));
}

void _icon(Canvas canvas, IconData icon, Offset center, double size, Color color) {
  final painter = TextPainter(
    text: TextSpan(
      text: String.fromCharCode(icon.codePoint),
      style: TextStyle(
        fontSize: size,
        color: color,
        fontFamily: icon.fontFamily,
        package: icon.fontPackage,
        height: 1.0,
      ),
    ),
    textDirection: TextDirection.ltr,
  )..layout();
  painter.paint(canvas, center - Offset(painter.width / 2, painter.height / 2));
}

Color _faint(Color c, double opacity) => c.withValues(alpha: opacity);

void _streak(Canvas canvas, CardHabit h, Color ink) {
  _icon(canvas, habitIconFor(h.iconKey), const Offset(56, 56), 48, _faint(ink, 0.9));
  final digits = '${h.streakLength}';
  final size = math.max(90.0, 190.0 - (digits.length - 1) * 38);
  _text(canvas, digits, const Offset(cardSize / 2, 200), size, ink, weight: FontWeight.w800);
  _text(canvas, '${h.streakNoun}${h.streakLength == 1 ? '' : 's'} streak'.toUpperCase(),
      const Offset(cardSize / 2, 330), 30, _faint(ink, 0.75),
      weight: FontWeight.w700);
}

void _ring(Canvas canvas, CardHabit h, Color ink) {
  const center = Offset(cardSize / 2, 180);
  const radius = 118.0;
  final track = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 28
    ..color = _faint(ink, 0.25);
  canvas.drawCircle(center, radius, track);
  if (h.progress > 0) {
    final arc = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 28
      ..strokeCap = StrokeCap.round
      ..color = ink;
    canvas.drawArc(Rect.fromCircle(center: center, radius: radius), -math.pi / 2,
        2 * math.pi * h.progress.clamp(0.0, 1.0), false, arc);
  }
  _icon(canvas, h.done ? Icons.check_rounded : habitIconFor(h.iconKey), center, 120, ink);
  final label = h.countText.isNotEmpty ? h.countText : h.name;
  _text(canvas, label, const Offset(cardSize / 2, 352), 38, _faint(ink, 0.9));
}

void _week(Canvas canvas, CardHabit h, Color ink) {
  _icon(canvas, habitIconFor(h.iconKey), const Offset(52, 52), 44, _faint(ink, 0.9));
  const left = 36.0;
  const pitch = (cardSize - 72) / 7;
  const baseline = 312.0;
  const tallest = 200.0;
  const letters = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
  final today = DateTime.now().weekday - 1;
  for (var i = 0; i < 7; i++) {
    final share = h.week[i];
    final height = share == null ? 10.0 : math.max(10.0, share * tallest);
    final opacity = share == null ? 0.2 : (share == 0 ? 0.35 : 1.0);
    final x = left + pitch * i + pitch / 2;
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(x - 14, baseline - height, 28, height), const Radius.circular(14)),
      Paint()..color = _faint(ink, opacity),
    );
    _text(canvas, letters[i], Offset(x, 352), 28, _faint(ink, i == today ? 1.0 : 0.65), weight: FontWeight.w700);
  }
}

void _trend(Canvas canvas, CardHabit h, Color ink) {
  _icon(canvas, habitIconFor(h.iconKey), const Offset(52, 52), 44, _faint(ink, 0.9));
  const left = 40.0;
  const right = cardSize - 40;
  const top = 110.0;
  const bottom = 290.0;
  final points = <Offset>[];
  for (var i = 0; i < h.trend.length; i++) {
    final x = left + (right - left) * i / math.max(1, h.trend.length - 1);
    points.add(Offset(x, bottom - (bottom - top) * h.trend[i]));
  }
  final path = Path()..moveTo(points.first.dx, points.first.dy);
  for (final p in points.skip(1)) {
    path.lineTo(p.dx, p.dy);
  }
  canvas.drawPath(
    path,
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 8
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round
      ..color = ink,
  );
  canvas.drawCircle(points.last, 11, Paint()..color = ink);
  canvas.drawLine(const Offset(left, 318), const Offset(right, 318),
      Paint()..color = _faint(ink, 0.3)..strokeWidth = 3);
  final from = TextPainter(
    text: TextSpan(text: h.trendFrom.toUpperCase(), style: TextStyle(fontSize: 24, color: _faint(ink, 0.8), fontWeight: FontWeight.w700)),
    textDirection: TextDirection.ltr,
  )..layout();
  from.paint(canvas, const Offset(left, 336));
  final now = TextPainter(
    text: TextSpan(text: 'TODAY', style: TextStyle(fontSize: 24, color: ink, fontWeight: FontWeight.w800)),
    textDirection: TextDirection.ltr,
  )..layout();
  now.paint(canvas, Offset(right - now.width, 336));
}

void _month(Canvas canvas, CardHabit h, Color ink) {
  _icon(canvas, habitIconFor(h.iconKey), const Offset(52, 52), 44, _faint(ink, 0.9));
  const left = 36.0;
  const pitch = (cardSize - 72) / 7;
  const top = 128.0;
  const rowPitch = 44.0;
  for (var i = 0; i < h.month.length; i++) {
    final state = h.month[i];
    if (state == null) continue;
    final center = Offset(left + pitch * (i % 7) + pitch / 2, top + rowPitch * (i ~/ 7));
    switch (state) {
      case DotState.done:
        canvas.drawCircle(center, 14, Paint()..color = ink);
      case DotState.today:
        canvas.drawCircle(
          center,
          12,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 4
            ..color = ink,
        );
      case DotState.upcoming:
        canvas.drawCircle(center, 14, Paint()..color = _faint(ink, 0.2));
      case DotState.off:
        canvas.drawCircle(center, 5, Paint()..color = _faint(ink, 0.2));
      case DotState.missed:
        final cross = Paint()
          ..strokeWidth = 4
          ..strokeCap = StrokeCap.round
          ..color = _faint(ink, 0.75);
        canvas.drawLine(center + const Offset(-8, -8), center + const Offset(8, 8), cross);
        canvas.drawLine(center + const Offset(8, -8), center + const Offset(-8, 8), cross);
    }
  }
}

void _grid(Canvas canvas, List<CardHabit> habits, Color Function(CardHabit) inkOf) {
  const xs = [105.0, 295.0];
  const ys = [88.0, 200.0, 312.0];
  for (var i = 0; i < habits.length; i++) {
    final h = habits[i];
    final ink = inkOf(h);
    final center = Offset(xs[i % 2], ys[i ~/ 2]);
    const radius = 44.0;
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 10
        ..color = _faint(ink, 0.25),
    );
    if (h.progress > 0) {
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        -math.pi / 2,
        2 * math.pi * h.progress.clamp(0.0, 1.0),
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 10
          ..strokeCap = StrokeCap.round
          ..color = ink,
      );
    }
    _icon(canvas, h.done ? Icons.check_rounded : habitIconFor(h.iconKey), center, 44, ink);
  }
}
