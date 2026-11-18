import 'package:ember/core/timer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final t0 = DateTime(2026, 11, 18, 10);

  test('a new timer is paused at zero', () {
    const timer = TimerState();
    expect(timer.isRunning, isFalse);
    expect(timer.elapsedSeconds(t0), 0);
  });

  test('a running timer counts up from the clock', () {
    final timer = const TimerState().start(t0);
    expect(timer.isRunning, isTrue);
    expect(timer.elapsedSeconds(t0.add(const Duration(minutes: 5, seconds: 7))), 307);
  });

  test('pausing banks the time and stops counting', () {
    final paused = const TimerState().start(t0).pause(t0.add(const Duration(minutes: 10)));
    expect(paused.isRunning, isFalse);
    expect(paused.elapsedSeconds(t0.add(const Duration(hours: 5))), 600);
  });

  test('resuming adds to what was banked', () {
    final paused = const TimerState().start(t0).pause(t0.add(const Duration(minutes: 10)));
    final resumed = paused.start(t0.add(const Duration(hours: 1)));
    expect(resumed.elapsedSeconds(t0.add(const Duration(hours: 1, minutes: 2))), 720);
  });

  test('starting a running timer or pausing a paused one changes nothing', () {
    final running = const TimerState().start(t0);
    expect(identical(running.start(t0.add(const Duration(minutes: 1))), running), isTrue);
    const paused = TimerState(bankedSeconds: 30);
    expect(identical(paused.pause(t0), paused), isTrue);
  });

  test('a clock that moved backwards never gives negative time', () {
    final timer = const TimerState(bankedSeconds: 20).start(t0);
    expect(timer.elapsedSeconds(t0.subtract(const Duration(minutes: 3))), 20);
  });

  test('progress is clamped between 0 and 1', () {
    const timer = TimerState(bankedSeconds: 900);
    expect(timer.progress(t0, 1800), 0.5);
    expect(timer.progress(t0, 600), 1.0);
    expect(timer.progress(t0, 0), 0.0);
  });

  test('formatClock shows m:ss and h:mm:ss', () {
    expect(formatClock(0), '0:00');
    expect(formatClock(65), '1:05');
    expect(formatClock(3599), '59:59');
    expect(formatClock(3600), '1:00:00');
    expect(formatClock(3725), '1:02:05');
    expect(formatClock(-4), '0:00');
  });
}
