import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../data/providers.dart';
import '../../theme/ember_theme.dart';
import '../../theme/theme_controller.dart';

Future<void> showAppearanceSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => const _AppearanceSheet(),
  );
}

class _AppearanceSheet extends ConsumerWidget {
  const _AppearanceSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(themeIdProvider);
    final auto = ref.watch(autoThemeProvider);
    final active = ref.watch(activePaletteProvider);
    bool isSelected(EmberPalette p) =>
        auto.enabled ? (p.dark ? p.id == auto.darkId : p.id == auto.lightId) : p.id == selected;
    void choose(EmberPalette p) {
      if (auto.enabled) {
        ref.read(autoThemeProvider.notifier).select(p);
      } else {
        ref.read(themeIdProvider.notifier).select(p.id);
      }
    }

    Widget group(String title, bool dark) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 8, top: 4),
              child: Text(title, style: TextStyle(color: EmberColors.textMuted, fontWeight: FontWeight.w600)),
            ),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                for (final p in emberPalettes)
                  if (p.dark == dark) _Swatch(palette: p, selected: isSelected(p), onTap: () => choose(p)),
              ],
            ),
            const SizedBox(height: 12),
          ],
        );

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Look and day', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 4),
            Text('Pick a look. It applies right away.', style: TextStyle(color: EmberColors.textMuted)),
            SwitchListTile(
              key: const Key('auto-theme-switch'),
              contentPadding: EdgeInsets.zero,
              title: const Text('Match my phone'),
              subtitle: Text(
                auto.enabled
                    ? 'Uses your chosen dark look at night and your light look by day.'
                    : 'Switch between a dark and a light look with the phone.',
              ),
              value: auto.enabled,
              onChanged: (on) => ref.read(autoThemeProvider.notifier).setEnabled(on, current: active),
            ),
            const SizedBox(height: 8),
            group(auto.enabled ? 'Dark look' : 'Dark', true),
            group(auto.enabled ? 'Light look' : 'Light', false),
            const SizedBox(height: 24),
            Text('Day starts at', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              'Stay up late? Until this time, what you log still counts for the day before.',
              style: TextStyle(color: EmberColors.textMuted),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final hour in const [0, 1, 2, 3, 4, 5, 6])
                  ChoiceChip(
                    key: Key('day-start-$hour'),
                    label: Text(hour == 0 ? 'Midnight' : '$hour AM'),
                    selected: ref.watch(dayStartProvider) == hour * 60,
                    onSelected: (_) => ref.read(dayStartProvider.notifier).select(hour * 60),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Swatch extends StatelessWidget {
  const _Swatch({required this.palette, required this.selected, required this.onTap});
  final EmberPalette palette;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      key: Key('theme-${palette.id}'),
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Container(
        width: 96,
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: palette.background,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: selected ? palette.accent : palette.track, width: selected ? 3 : 1.5),
        ),
        child: Column(
          children: [
            Container(
              height: 34,
              decoration: BoxDecoration(color: palette.surface, borderRadius: BorderRadius.circular(10)),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircleAvatar(radius: 8, backgroundColor: palette.accent),
                  const SizedBox(width: 6),
                  CircleAvatar(radius: 8, backgroundColor: palette.glow),
                ],
              ),
            ),
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (selected) Icon(Icons.check_rounded, size: 14, color: palette.accent),
                Flexible(
                  child: Text(palette.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: palette.text, fontSize: 12, fontWeight: FontWeight.w600)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
