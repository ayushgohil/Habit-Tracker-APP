import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ember/app.dart';
import 'package:ember/data/providers.dart';

void main() {
  testWidgets('Ember app starts and displays its home screen', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          habitViewsProvider.overrideWithValue(
            const AsyncValue.data([]),
          ),
        ],
        child: const EmberApp(),
      ),
    );

    await tester.pump();
    expect(find.text('EMBER'), findsOneWidget);
    expect(find.text('Light your first ember'), findsOneWidget);
  });
}
