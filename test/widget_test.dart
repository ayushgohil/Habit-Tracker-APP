import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ember/app.dart';
import 'package:ember/data/database.dart';
import 'package:ember/data/providers.dart';

void main() {
  testWidgets('Ember app starts and displays its home screen', (tester) async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(database),
        ],
        child: const EmberApp(),
      ),
    );

    await tester.pump();
    expect(find.text('EMBER'), findsOneWidget);
  });
}
