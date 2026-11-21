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

/// Most sessions a goal can be split into. Keeps the alerts for one timer few.
const maxTimerSessions = 20;

/// A timed goal split into equal sessions, for example four 25 minute focus
/// sessions. The last session is shorter when the goal does not divide evenly.
class SessionPlan {
  const SessionPlan({required this.goalSeconds, required this.sessionSeconds});

  final int goalSeconds;

  /// Length of one session; 0 means the goal is not split.
  final int sessionSeconds;

  bool get isSplit => sessionSeconds > 0 && sessionSeconds < goalSeconds;

  int get count => isSplit ? (goalSeconds + sessionSeconds - 1) ~/ sessionSeconds : 1;

  /// The 1-based session that [totalSeconds] of progress falls in. Stays on the
  /// last session once the goal is reached.
  int sessionAt(int totalSeconds) {
    if (!isSplit || totalSeconds >= goalSeconds) return count;
    return (totalSeconds < 0 ? 0 : totalSeconds) ~/ sessionSeconds + 1;
  }

  /// How long session [session] (1-based) is.
  int lengthOf(int session) {
    if (!isSplit) return goalSeconds;
    final left = goalSeconds - (session - 1) * sessionSeconds;
    return left < sessionSeconds ? left : sessionSeconds;
  }

  /// Seconds done in the session [totalSeconds] falls in.
  int secondsIntoSession(int totalSeconds) {
    if (!isSplit) return totalSeconds < 0 ? 0 : totalSeconds;
    final session = sessionAt(totalSeconds);
    final into = totalSeconds - (session - 1) * sessionSeconds;
    return into.clamp(0, lengthOf(session)).toInt();
  }

  /// Progress through the current session from 0 to 1.
  double sessionProgress(int totalSeconds) {
    final length = lengthOf(sessionAt(totalSeconds));
    return length <= 0 ? 0 : (secondsIntoSession(totalSeconds) / length).clamp(0.0, 1.0).toDouble();
  }

  /// Every session end still ahead of [totalSeconds], the last being the goal.
  List<TimerAlert> alertsFrom(int totalSeconds) {
    final alerts = <TimerAlert>[];
    for (var session = 1; session <= count; session++) {
      final end = isSplit ? (session * sessionSeconds < goalSeconds ? session * sessionSeconds : goalSeconds) : goalSeconds;
      if (end > totalSeconds) {
        alerts.add(TimerAlert(secondsFromNow: end - totalSeconds, session: session, sessions: count));
      }
    }
    return alerts;
  }
}

/// A moment a running timer should notify: a session ending, or the goal.
class TimerAlert {
  const TimerAlert({required this.secondsFromNow, required this.session, required this.sessions});

  final int secondsFromNow;
  final int session;
  final int sessions;

  bool get isGoal => session == sessions;
}

/// The session length to save: 0 (not split) unless it is shorter than the
/// goal, and never so short that the goal needs more than [maxTimerSessions].
int normalizeSessionSeconds(int goalSeconds, int sessionSeconds) {
  if (sessionSeconds <= 0 || sessionSeconds >= goalSeconds) return 0;
  final least = (goalSeconds + maxTimerSessions - 1) ~/ maxTimerSessions;
  return sessionSeconds < least ? least : sessionSeconds;
}
