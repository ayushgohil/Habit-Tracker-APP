import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../security/app_lock.dart';
import '../../theme/ember_theme.dart';

/// The Android package Ember's automation actions are named after.
const automationPackage = 'com.nextlyr.ember';

const automationActions = <(String, String)>[
  ('LOG', 'Adds one step to the habit (a tap)'),
  ('COMPLETE', 'Marks the habit done for today'),
  ('START', 'Starts the habit\'s timer'),
  ('STOP', 'Stops the timer and saves the time'),
];

class PrivacyScreen extends ConsumerWidget {
  const PrivacyScreen({super.key});

  Future<void> _toggleLock(BuildContext context, WidgetRef ref, bool on) async {
    final messenger = ScaffoldMessenger.of(context);
    final auth = ref.read(lockAuthenticatorProvider);
    if (on && !await auth.isAvailable()) {
      messenger.showSnackBar(const SnackBar(
        content: Text('Set up a screen lock or fingerprint on your phone first, then try again.'),
      ));
      return;
    }
    // Turning it on or off both need the owner, so nobody else can change it.
    if (!await auth.authenticate(on ? 'Turn on the Ember lock' : 'Turn off the Ember lock')) return;
    await ref.read(appLockProvider.notifier).set(on);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final muted = text.bodyMedium?.copyWith(color: EmberColors.textMuted);
    final locked = ref.watch(appLockProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Privacy & automation')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          Text('App lock', style: text.titleMedium),
          SwitchListTile(
            key: const Key('app-lock-switch'),
            contentPadding: EdgeInsets.zero,
            title: const Text('Ask before opening Ember'),
            subtitle: const Text('Uses your fingerprint, face or your phone\'s PIN, pattern or password.'),
            value: locked,
            onChanged: (on) => _toggleLock(context, ref, on),
          ),
          const SizedBox(height: 20),
          Text('Quick settings tile', style: text.titleMedium),
          const SizedBox(height: 4),
          Text(
            'Swipe down twice, tap the pencil and drag "Ember" into your tiles. Tapping it logs your next habit that is still to do, without opening the app.',
            style: muted,
          ),
          const SizedBox(height: 20),
          Theme(
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              key: const Key('automation-section'),
              tilePadding: EdgeInsets.zero,
              childrenPadding: EdgeInsets.zero,
              shape: const Border(),
              collapsedShape: const Border(),
              title: Text('Automation (advanced)', style: text.titleMedium),
              subtitle: Text('For apps like Tasker or MacroDroid', style: muted),
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'You can ignore this unless you use an automation app. Those apps can tell Ember to log a habit, '
                    'for example when you reach the gym. Send a broadcast with one of the actions below and a text extra '
                    'named habit holding the habit\'s name. Tap an action to copy it.',
                    style: muted,
                  ),
                ),
                const SizedBox(height: 8),
                for (final (name, what) in automationActions)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Material(
                      color: EmberColors.surface,
                      borderRadius: BorderRadius.circular(14),
                      clipBehavior: Clip.antiAlias,
                      child: ListTile(
                        key: Key('action-$name'),
                        title: Text('$automationPackage.action.$name', style: const TextStyle(fontSize: 13)),
                        subtitle: Text(what),
                        trailing: const Icon(Icons.copy_rounded, size: 18),
                        onTap: () async {
                          await Clipboard.setData(ClipboardData(text: '$automationPackage.action.$name'));
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Copied')));
                          }
                        },
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
