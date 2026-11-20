import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

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
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Appearance', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 4),
            Text('Pick a look. It applies right away.', style: TextStyle(color: EmberColors.textMuted)),
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                for (final p in emberPalettes)
                  _Swatch(
                    palette: p,
                    selected: p.id == selected,
                    onTap: () => ref.read(themeIdProvider.notifier).select(p.id),
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
