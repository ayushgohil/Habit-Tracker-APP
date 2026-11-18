/// Pure state of a habit timer. A timer banks the seconds it has run so far and
/// remembers when it last started running (null while paused), so the elapsed
/// time can always be recomputed from the clock, even after the app was closed.
library;

class TimerState {
  const TimerState({this.bankedSeconds = 0, this.runningSince});

  final int bankedSeconds;
  final DateTime? runningSince;

  bool get isRunning => runningSince != null;

  /// Total seconds run as of [now]. Never negative, even if the clock moved back.
  int elapsedSeconds(DateTime now) {
    final since = runningSince;
    if (since == null) return bankedSeconds;
    final running = now.difference(since).inSeconds;
    return bankedSeconds + (running < 0 ? 0 : running);
  }

  /// Starts or resumes. Does nothing if already running.
  TimerState start(DateTime now) =>
      isRunning ? this : TimerState(bankedSeconds: bankedSeconds, runningSince: now);

  /// Pauses, banking the time run so far. Does nothing if already paused.
  TimerState pause(DateTime now) =>
      isRunning ? TimerState(bankedSeconds: elapsedSeconds(now)) : this;

  /// Progress towards [targetSeconds] from 0 to 1.
  double progress(DateTime now, int targetSeconds) =>
      targetSeconds <= 0 ? 0 : (elapsedSeconds(now) / targetSeconds).clamp(0.0, 1.0).toDouble();
}

/// Formats seconds as `m:ss`, or `h:mm:ss` from one hour.
String formatClock(int seconds) {
  final s = seconds < 0 ? 0 : seconds;
  final h = s ~/ 3600;
  final m = (s % 3600) ~/ 60;
  final sec = s % 60;
  final ss = sec.toString().padLeft(2, '0');
  if (h > 0) return '$h:${m.toString().padLeft(2, '0')}:$ss';
  return '$m:$ss';
}
