import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../data/backup.dart';
import '../../data/providers.dart';
import '../../notifications/habit_notification_service.dart';
import '../../theme/ember_theme.dart';

class BackupScreen extends ConsumerStatefulWidget {
  const BackupScreen({super.key});

  @override
  ConsumerState<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends ConsumerState<BackupScreen> {
  bool _busy = false;

  void _say(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _run(Future<void> Function() task) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await task();
    } on BackupException catch (error) {
      _say(error.message);
    } catch (error) {
      _say('Something went wrong: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _share(String fileName, String content, String mime) async {
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/$fileName');
    await file.writeAsString(content);
    await SharePlus.instance.share(
      ShareParams(files: [XFile(file.path, mimeType: mime)], subject: fileName),
    );
  }

  String get _stamp => DateFormat('yyyy-MM-dd').format(DateTime.now());

  Future<void> _exportBackup() => _run(() async {
        final json = await exportBackupJson(ref.read(databaseProvider));
        await _share('ember-backup-$_stamp.json', json, 'application/json');
      });

  Future<void> _exportCsv() => _run(() async {
        final csv = await exportHistoryCsv(ref.read(databaseProvider));
        await _share('ember-history-$_stamp.csv', csv, 'text/csv');
      });

  Future<void> _restore() => _run(() async {
        final picked = await FilePicker.pickFiles();
        if (picked.isEmpty) return;
        final bytes = await picked.first.readAsBytes();
        final text = utf8.decode(bytes, allowMalformed: true);
        if (!mounted) return;
        final ok = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Replace everything?'),
            content: const Text('All habits and history in Ember now will be replaced by what is in this backup. This cannot be undone.'),
            actions: [
              TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: const Text('Cancel')),
              FilledButton(onPressed: () => Navigator.of(dialogContext).pop(true), child: const Text('Replace')),
            ],
          ),
        );
        if (ok != true) return;

        final db = ref.read(databaseProvider);
        final service = HabitNotificationService.instance;
        final before = await db.select(db.habits).get();
        final summary = await restoreBackupJson(db, text);
        // Reminders and timer notifications belong to the old data.
        for (final habit in before) {
          await service.cancelHabit(habit.id);
          await service.cancelTimer(habit.id);
        }
        await service.syncAll(await db.select(db.habits).get());
        _say('Restored ${summary.habits} habits and ${summary.days} logged days.');
      });

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Back up & restore')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          Text(
            'Everything in Ember stays on this phone. A backup file lets you move to a new phone or recover after a reset. Save it somewhere safe, such as Google Drive.',
            style: text.bodyMedium?.copyWith(color: EmberColors.textMuted),
          ),
          const SizedBox(height: 20),
          _ActionCard(
            key: const Key('backup-export'),
            icon: Icons.save_alt_rounded,
            title: 'Back up now',
            subtitle: 'Habits, goals, history and notes as one file',
            onTap: _busy ? null : _exportBackup,
          ),
          _ActionCard(
            key: const Key('backup-restore'),
            icon: Icons.restore_rounded,
            title: 'Restore from a backup',
            subtitle: 'Replaces everything in Ember with a backup file',
            onTap: _busy ? null : _restore,
          ),
          _ActionCard(
            key: const Key('backup-csv'),
            icon: Icons.table_chart_outlined,
            title: 'Export history as CSV',
            subtitle: 'One row per logged day, for spreadsheets',
            onTap: _busy ? null : _exportCsv,
          ),
          const SizedBox(height: 12),
          if (_busy) const LinearProgressIndicator(),
        ],
      ),
    );
  }
}

class _ActionCard extends StatelessWidget {
  const _ActionCard({super.key, required this.icon, required this.title, required this.subtitle, required this.onTap});
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: EmberColors.surface,
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: ListTile(
          leading: Icon(icon, color: EmberColors.ember),
          title: Text(title),
          subtitle: Text(subtitle),
          trailing: const Icon(Icons.chevron_right_rounded),
          onTap: onTap,
        ),
      ),
    );
  }
}
