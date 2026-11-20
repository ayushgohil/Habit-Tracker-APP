import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/day.dart';
import '../../data/database.dart';
import '../../data/providers.dart';
import '../../theme/ember_theme.dart';
import '../common/text_dialogs.dart';

/// Notes that match [query] (in the text or the date), pinned ones first and
/// each group newest first. An empty query keeps everything.
List<DayNote> filterNotes(List<DayNote> notes, String query) {
  final words = query.toLowerCase().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
  bool matches(DayNote n) {
    final text = '${n.note} ${DateFormat('EEEE d MMMM yyyy').format(parseDayKey(n.day))} ${n.day}'.toLowerCase();
    return words.every(text.contains);
  }

  final found = notes.where(matches).toList()
    ..sort((a, b) {
      if (a.pinned != b.pinned) return a.pinned ? -1 : 1;
      return b.day.compareTo(a.day);
    });
  return found;
}

/// Every day note in one place, with search and pinning.
class NotesScreen extends ConsumerStatefulWidget {
  const NotesScreen({super.key});

  @override
  ConsumerState<NotesScreen> createState() => _NotesScreenState();
}

class _NotesScreenState extends ConsumerState<NotesScreen> {
  String _query = '';

  Future<void> _edit(DayNote note) async {
    final day = parseDayKey(note.day);
    final text = await showNoteDialog(
      context,
      title: DateFormat('EEEE, d MMM yyyy').format(day),
      initialText: note.note,
      hintText: 'How did this day go?',
    );
    if (text == null) return;
    await ref.read(habitActionsProvider).saveNote(day, text);
  }

  @override
  Widget build(BuildContext context) {
    final notes = ref.watch(allNotesProvider).valueOrNull;
    final shown = notes == null ? const <DayNote>[] : filterNotes(notes, _query);
    return Scaffold(
      appBar: AppBar(title: const Text('All notes')),
      body: notes == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
              children: [
                TextField(
                  key: const Key('notes-search'),
                  decoration: const InputDecoration(
                    hintText: 'Search notes',
                    prefixIcon: Icon(Icons.search_rounded),
                    isDense: true,
                  ),
                  onChanged: (v) => setState(() => _query = v),
                ),
                const SizedBox(height: 16),
                if (shown.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 32),
                    child: Text(
                      notes.isEmpty ? 'No notes yet. Add one from the note button on Home.' : 'No note matches that.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: EmberColors.textMuted),
                    ),
                  ),
                for (final note in shown)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Material(
                      color: EmberColors.surface,
                      borderRadius: BorderRadius.circular(16),
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        key: Key('note-${note.day}'),
                        onTap: () => _edit(note),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(16, 12, 4, 12),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      DateFormat('EEEE, d MMM yyyy').format(parseDayKey(note.day)),
                                      style: Theme.of(context).textTheme.labelLarge?.copyWith(color: EmberColors.glow),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(note.note, maxLines: 6, overflow: TextOverflow.ellipsis),
                                  ],
                                ),
                              ),
                              IconButton(
                                key: Key('pin-${note.day}'),
                                tooltip: note.pinned ? 'Unpin' : 'Pin to the top',
                                onPressed: () => ref.read(habitActionsProvider).setNotePinned(note.day, !note.pinned),
                                icon: Icon(
                                  note.pinned ? Icons.push_pin_rounded : Icons.push_pin_outlined,
                                  color: note.pinned ? EmberColors.ember : EmberColors.textMuted,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
}
