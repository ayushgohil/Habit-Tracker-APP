import 'package:material_ui/material_ui.dart';

import '../../core/habit_icons.dart';
import '../../theme/ember_theme.dart';

/// Searchable icon grid for the habit form.
class IconPicker extends StatefulWidget {
  const IconPicker({super.key, required this.selected, required this.color, required this.onChanged});
  final String selected;
  final Color color;
  final ValueChanged<String> onChanged;

  @override
  State<IconPicker> createState() => _IconPickerState();
}

class _IconPickerState extends State<IconPicker> {
  static const _collapsed = 24;
  String _query = '';
  bool _showAll = false;

  @override
  Widget build(BuildContext context) {
    final found = searchHabitIcons(_query);
    final searching = _query.trim().isNotEmpty;
    final visible = (_showAll || searching || found.length <= _collapsed) ? found : found.take(_collapsed).toList();
    // Keep the chosen icon visible even when the short list would hide it.
    final selectedHidden = !searching && !_showAll && !visible.any((e) => e.key == widget.selected);
    final shown = selectedHidden
        ? [habitIconEntries.firstWhere((e) => e.key == widget.selected, orElse: () => habitIconEntries.first), ...visible]
        : visible;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          key: const Key('icon-search'),
          decoration: const InputDecoration(
            hintText: 'Search icons (run, book, money...)',
            prefixIcon: Icon(Icons.search_rounded),
            isDense: true,
          ),
          onChanged: (v) => setState(() => _query = v),
        ),
        const SizedBox(height: 12),
        if (found.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text('No icon matches that.', style: TextStyle(color: EmberColors.textMuted)),
          )
        else
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final entry in shown)
                Tooltip(
                  message: entry.words.split(' ').first,
                  child: InkWell(
                    key: Key('icon-${entry.key}'),
                    customBorder: const CircleBorder(),
                    onTap: () => widget.onChanged(entry.key),
                    child: CircleAvatar(
                      backgroundColor: widget.selected == entry.key ? widget.color.withValues(alpha: .2) : EmberColors.surface,
                      child: Icon(entry.icon, color: widget.selected == entry.key ? widget.color : EmberColors.textMuted),
                    ),
                  ),
                ),
            ],
          ),
        if (!searching && found.length > _collapsed)
          TextButton(
            key: const Key('icon-show-all'),
            onPressed: () => setState(() => _showAll = !_showAll),
            child: Text(_showAll ? 'Show fewer icons' : 'Show all ${found.length} icons'),
          ),
      ],
    );
  }
}
