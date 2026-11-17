import 'package:material_ui/material_ui.dart';

// Both dialogs own their TextEditingController in their State.
//
// A controller must not be disposed right after `showDialog` returns: the
// future completes when the dialog starts closing, but its TextField stays on
// screen for the closing animation and still uses the controller. Disposing it
// early makes Flutter throw "TextEditingController was used after being
// disposed", which then breaks the widget tree and shows the red error screen.
// A State disposes its controller only once the dialog is really gone.

/// Asks for a short note. Returns the text, or null if cancelled.
Future<String?> showNoteDialog(
  BuildContext context, {
  required String title,
  String initialText = '',
  String hintText = '',
  int maxLength = 1000,
}) {
  return showDialog<String>(
    context: context,
    builder: (_) => _NoteDialog(
      title: title,
      initialText: initialText,
      hintText: hintText,
      maxLength: maxLength,
    ),
  );
}

class _NoteDialog extends StatefulWidget {
  const _NoteDialog({
    required this.title,
    required this.initialText,
    required this.hintText,
    required this.maxLength,
  });

  final String title;
  final String initialText;
  final String hintText;
  final int maxLength;

  @override
  State<_NoteDialog> createState() => _NoteDialogState();
}

class _NoteDialogState extends State<_NoteDialog> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.initialText);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _controller,
        autofocus: true,
        minLines: 3,
        maxLines: 6,
        maxLength: widget.maxLength,
        decoration: InputDecoration(hintText: widget.hintText),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_controller.text),
          child: const Text('Save'),
        ),
      ],
    );
  }
}

/// What [showLogTimeDialog] returns when the person clears the logged time.
const clearLoggedTime = -1;

/// Asks how many minutes to add to a timed habit.
///
/// Returns the minutes (always more than zero), [clearLoggedTime] if the
/// person chose to clear what was logged, or null if cancelled.
Future<int?> showLogTimeDialog(
  BuildContext context, {
  required String habitName,
  required bool canClear,
}) {
  return showDialog<int>(
    context: context,
    builder: (_) => _LogTimeDialog(habitName: habitName, canClear: canClear),
  );
}

class _LogTimeDialog extends StatefulWidget {
  const _LogTimeDialog({required this.habitName, required this.canClear});

  final String habitName;
  final bool canClear;

  @override
  State<_LogTimeDialog> createState() => _LogTimeDialogState();
}

class _LogTimeDialogState extends State<_LogTimeDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Log time · ${widget.habitName}'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        keyboardType: TextInputType.number,
        decoration: const InputDecoration(
          labelText: 'Minutes completed',
          suffixText: 'min',
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        if (widget.canClear)
          TextButton(
            onPressed: () => Navigator.of(context).pop(clearLoggedTime),
            child: const Text('Clear logged time'),
          ),
        FilledButton(
          onPressed: () {
            // Only positive input is accepted, so typing a negative number
            // can never be mistaken for the clear value.
            final typed = int.tryParse(_controller.text);
            Navigator.of(context).pop(typed != null && typed > 0 ? typed : null);
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}
