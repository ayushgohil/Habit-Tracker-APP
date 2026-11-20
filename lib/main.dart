import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'data/day_start.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await loadDayStart();
  runApp(const ProviderScope(child: EmberApp()));
}
