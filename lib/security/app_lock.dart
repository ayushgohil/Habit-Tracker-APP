import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:local_auth/local_auth.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../theme/ember_theme.dart';

const _lockKey = 'app_lock';

/// How long Ember can be out of sight before it asks again.
const lockGrace = Duration(seconds: 20);

/// Reads whether the lock is on, before the first frame so nothing flashes.
Future<bool> loadAppLock() async {
  try {
    return (await SharedPreferences.getInstance()).getBool(_lockKey) ?? false;
  } catch (_) {
    return false;
  }
}

/// Asks the phone to confirm it is the owner: fingerprint, face, or the screen
/// lock PIN, pattern or password.
abstract class LockAuthenticator {
  /// Whether the phone has a screen lock or biometrics set up.
  Future<bool> isAvailable();

  /// Shows the system prompt. True when the person passed it.
  Future<bool> authenticate(String reason);
}

class PhoneAuthenticator implements LockAuthenticator {
  final LocalAuthentication _auth = LocalAuthentication();

  @override
  Future<bool> isAvailable() async {
    try {
      return await _auth.isDeviceSupported();
    } catch (error) {
      debugPrint('Ember lock: $error');
      return false;
    }
  }

  @override
  Future<bool> authenticate(String reason) async {
    try {
      return await _auth.authenticate(
        localizedReason: reason,
        options: const AuthenticationOptions(biometricOnly: false, stickyAuth: true),
      );
    } catch (error) {
      debugPrint('Ember lock: $error');
      return false;
    }
  }
}

final lockAuthenticatorProvider = Provider<LockAuthenticator>((ref) => PhoneAuthenticator());

/// Whether the lock was on when the app started.
final appLockInitialProvider = Provider<bool>((ref) => false);

class AppLockController extends StateNotifier<bool> {
  AppLockController(super.initial);

  Future<void> set(bool on) async {
    state = on;
    try {
      await (await SharedPreferences.getInstance()).setBool(_lockKey, on);
    } catch (_) {}
  }
}

final appLockProvider = StateNotifierProvider<AppLockController, bool>(
  (ref) => AppLockController(ref.watch(appLockInitialProvider)),
);

/// Covers the app with a lock screen until the phone's own check is passed.
class LockGate extends ConsumerStatefulWidget {
  const LockGate({super.key, required this.child});
  final Widget child;

  @override
  ConsumerState<LockGate> createState() => _LockGateState();
}

class _LockGateState extends ConsumerState<LockGate> with WidgetsBindingObserver {
  late bool _locked = ref.read(appLockProvider);
  bool _checking = false;
  DateTime? _leftAt;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (_locked) WidgetsBinding.instance.addPostFrameCallback((_) => _unlock());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // The system prompt itself pauses the app; ignore that.
    if (_checking || !ref.read(appLockProvider)) return;
    if (state == AppLifecycleState.paused || state == AppLifecycleState.hidden) {
      _leftAt ??= DateTime.now();
    } else if (state == AppLifecycleState.resumed) {
      final left = _leftAt;
      _leftAt = null;
      if (left != null && DateTime.now().difference(left) >= lockGrace) {
        setState(() => _locked = true);
        _unlock();
      }
    }
  }

  Future<void> _unlock() async {
    if (_checking) return;
    _checking = true;
    final ok = await ref.read(lockAuthenticatorProvider).authenticate('Unlock Ember');
    _checking = false;
    _leftAt = null;
    if (ok && mounted) setState(() => _locked = false);
  }

  @override
  Widget build(BuildContext context) {
    // Turning the lock off while it is showing lets the person straight in.
    ref.listen<bool>(appLockProvider, (_, on) {
      if (!on && _locked) setState(() => _locked = false);
    });
    return Stack(
      children: [
        widget.child,
        if (_locked && ref.watch(appLockProvider))
          Positioned.fill(
            child: Container(
              key: const Key('lock-screen'),
              color: EmberColors.background,
              alignment: Alignment.center,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.lock_rounded, size: 56, color: EmberColors.glow),
                  const SizedBox(height: 16),
                  Text('Ember is locked', style: TextStyle(color: EmberColors.text, fontSize: 20, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 20),
                  FilledButton(
                    key: const Key('unlock-button'),
                    onPressed: _unlock,
                    child: const Text('Unlock'),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
