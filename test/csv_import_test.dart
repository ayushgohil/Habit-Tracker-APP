import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:ember/data/backup.dart';
import 'package:ember/data/csv_import.dart';
import 'package:ember/data/database.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  late int readId;
  final today = DateTime(2026, 11, 20);

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    readId = await db.insertHabit(HabitsCompanion.insert(
      name: 'Read, daily',
      iconKey: 'book',
      colorValue: 0xFFFF6B2C,
      createdAt: Value(DateTime(2026, 1, 1)),
    ));
  });
  tearDown(() => db.close());

  test('the parser handles quotes, commas, line breaks and a trailing row', () {
    final rows = parseCsv('a,b\r\n"x, y","say ""hi"""\n"two\nlines",z');
    expect(rows, [
      ['a', 'b'],
      ['x, y', 'say "hi"'],
      ['two\nlines', 'z'],
    ]);
  });

  test('its own export can be imported again into an empty history', () async {
    await db.setCompletion(habitId: readId, day: '2026-03-01', amount: 1);
    await db.setCompletion(habitId: readId, day: '2026-03-02', amount: 2);
    final csv = await exportHistoryCsv(db);
    await db.setCompletion(habitId: readId, day: '2026-03-01', amount: 0);
    await db.setCompletion(habitId: readId, day: '2026-03-02', amount: 0);
    final result = await importHistoryCsv(db, csv, today: today);
    expect(result.imported, 2);
    expect(result.habits, 1);
    expect(await db.loggedAmount(readId, '2026-03-02'), 2);
  });

  test('values never lower what is already logged; unknown habits are reported', () async {
    await db.setCompletion(habitId: readId, day: '2026-03-01', amount: 5);
    final result = await importHistoryCsv(
      db,
      'habit,date,amount\n"Read, daily",2026-03-01,3\n"Read, daily",2026-03-02,4\nRun,2026-03-02,1\n',
      today: today,
    );
    expect(result.imported, 1);
    expect(result.skipped, 2);
    expect(result.unknownHabits, {'Run'});
    expect(await db.loggedAmount(readId, '2026-03-01'), 5);
    expect(await db.loggedAmount(readId, '2026-03-02'), 4);
  });

  test('bad dates, future days and days before the start are skipped', () async {
    final result = await importHistoryCsv(
      db,
      'HABIT,Date,Amount\n"read, DAILY",2026-02-31,1\n"read, DAILY",not-a-date,1\n"read, DAILY",2027-01-01,1\n"read, DAILY",2025-12-31,1\n"read, DAILY",2026-05-05,-2\n"read, DAILY",2026-05-05,1\n',
      today: today,
    );
    expect(result.imported, 1);
    expect(result.skipped, 5);
    expect(await db.loggedAmount(readId, '2026-05-05'), 1);
  });

  test('a file that is not an Ember history is refused', () async {
    expect(() => importHistoryCsv(db, 'name,score\nA,1\n', today: today), throwsA(isA<CsvImportException>()));
    expect(() => importHistoryCsv(db, '', today: today), throwsA(isA<CsvImportException>()));
  });
}
