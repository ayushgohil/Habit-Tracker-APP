# Ember

A private, local-first habit and streak tracker for Android, built with Flutter.

Tap a ring to log a habit, keep the streak burning, and let your data live on
your own device. Optional daily backup to your own Google Drive is planned.

> Status: early scaffold. The licence is not decided yet; the repo is private
> for now.

## What works today

- Ring-grid home screen: tap to log, long-press for details, edit, pause, archive or delete
- Selectable date for logging past days, a per-day journal note, and undo
- Reorderable Up Next list, and a gold card when everything due today is done
- Habit library for reordering, and for resuming paused or restoring archived habits
- Task types: normal, negative (with an optional 2-day rule) and timed
- Schedules: every day, specific weekdays, N times a week, every N days, and
  weekly, fortnightly, monthly or yearly goals
- Habits that need several taps a day (for example 8 glasses of water)
- Current and best streak and completion rate for every schedule
- Everything stored locally in SQLite via [Drift](https://drift.simonbinder.eu)

## Getting started

You need the [Flutter SDK](https://docs.flutter.dev/get-started/install)
(3.27 or newer) and Android Studio or the Android command-line tools.

```bash
# 1. Generate the Android platform folder (once)
flutter create --org com.nextlyr --project-name ember --platforms android .

# 2. Install dependencies
flutter pub get

# 3. Generate the Drift database code
dart run build_runner build --delete-conflicting-outputs

# 4. Run on a device or emulator
flutter run

# Tests
flutter test
```

Re-run step 3 whenever you change `lib/data/database.dart`.

## Project layout

```
lib/
  main.dart, app.dart      app entry and lifecycle
  core/                    pure Dart: day helpers, schedules, streak maths
  data/                    Drift database and Riverpod providers
  theme/                   Ember colours and theme
  ui/
    home/                  ring grid, habit tile, details sheet
    add_habit/             new-habit form
test/                      streak logic tests
```

## Roadmap

1. Local reminders (per-habit notification times)
2. Stats and history (calendar heatmap, best streak, completion rate)
3. Optional daily backup to the Google Drive app-data folder
4. Manual export and import of a backup file
5. Home screen widget
6. Wear OS companion

## Notes for later

- Backups will use the `drive.appdata` scope, which keeps files in a hidden
  folder only this app can read.
- Never commit signing keys, `key.properties`, or Google OAuth client files.
  They are already in `.gitignore`.
