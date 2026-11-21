import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'data/day_start.dart';
import 'security/app_lock.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await loadDayStart();
  final locked = await loadAppLock();
  runApp(ProviderScope(
    overrides: [appLockInitialProvider.overrideWithValue(locked)],
    child: const EmberApp(),
  ));
}
