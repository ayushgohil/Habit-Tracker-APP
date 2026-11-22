# Contributing to Ember

Thanks for wanting to help. Ember is a small, friendly project, and every kind of contribution counts: a bug report, a typo fix, a new icon, a better chart, or a whole feature.

By taking part you agree to follow the [Code of Conduct](CODE_OF_CONDUCT.md).

## Ways to help

- **Report a bug** with the [bug form](https://github.com/ayushgohil/Habit-Tracker-APP/issues/new?template=bug_report.yml). The more exact the steps, the faster it gets fixed.
- **Suggest a feature** with the [feature form](https://github.com/ayushgohil/Habit-Tracker-APP/issues/new?template=feature_request.yml). Explain the problem you want solved, not only the solution.
- **Pick up an issue.** Issues labelled `good first issue` are small and self-contained. Comment on one so nobody else starts the same work.
- **Test on your phone.** Try a release on a different Android version or brand and tell us what breaks.

For anything bigger than a small fix, please open an issue first and say what you plan to do. It saves you from building something that does not fit.

## Set up

You need the Flutter SDK (3.27 or newer), JDK 17 and the Android SDK. Android Studio installs the last two.

```bash
git clone https://github.com/<your-username>/Habit-Tracker-APP.git
cd Habit-Tracker-APP

flutter pub get
dart run build_runner build --delete-conflicting-outputs
flutter run
```

Drift generates the database code, which is not committed. Run the `build_runner` command again whenever you change `lib/data/database.dart`.

Debug builds are signed with Android's debug key, so you do not need any secrets.

## Before you open a pull request

```bash
flutter analyze   # must report no issues, including infos
flutter test      # must pass
```

CI runs the same two commands on every pull request, and compiles a debug APK when your change touches `android/` or `pubspec.yaml`.

## Making a change

1. Fork the repo and create a branch from `main`, for example `fix-streak-reset` or `feat-icon-search`.
2. Keep the change focused. One pull request should do one thing.
3. Add or update tests. Logic in `lib/core/` and `lib/data/` should always have unit tests; screens should have a widget test for the main flow.
4. Write clear commit messages in the imperative mood ("Fix streak reset after a paused day").
5. Open the pull request against `main` and fill in the template. Screenshots help a lot for anything visual.

A maintainer reviews every pull request. Expect questions and small requests; they are about the code, not about you.

## Code guidelines

- Follow the lints in `analysis_options.yaml` (`flutter_lints`, plus `prefer_const_constructors` and `avoid_print`).
- Keep pure logic (streaks, schedules, dates) in `lib/core/` with no Flutter imports, so it stays easy to test.
- Use the colours from `EmberColors` and the active palette rather than hard-coded values, so every theme works.
- Never rename an icon key in `lib/core/habit_icons.dart`; keys are saved in people's data and in backups.
- A change to the database needs a schema version bump, a migration in `database.dart` that keeps old data, and a test for it. Backups from older versions must still restore.
- Do not add network access, analytics or tracking. Ember is local-first.
- Think about the day boundary: Ember lets people choose when their day starts, so use the helpers in `lib/core/day.dart` instead of raw `DateTime.now()` comparisons.

### Tests that behave

Widget tests here have a few habits worth knowing:

- Use the `settle` helper from `test/home_flow_test.dart` after anything that touches the database.
- Lazy lists do not build items that are off screen. Use a tall test window or `ensureVisible`.
- Reset global state between tests (shared preferences mocks, `EmberColors`, `dayStartOffsetMinutes`, the `healthWriter` and `linkOpener` globals).
- Avoid calling `.first` on a Drift stream.

## Android code

The native side lives in `android/`: the home-screen widgets, the Quick Settings tile and the automation receiver, in `android/app/src/main/kotlin/com/nextlyr/ember/`. If you change it, test on a real device or emulator, because the unit tests cannot cover it. The widget images themselves are drawn in Dart (see [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)).

## Translations

All text is currently English and written directly in the code. Proper translation support is planned. If you would like to help with that, open an issue and we will plan it together.

## License of your contribution

Ember is released under the [GPL-3.0](LICENSE). By submitting a pull request you confirm that you wrote the code (or have the right to share it) and that it may be distributed under the same license. You keep the copyright to your work.

## Questions

Open an issue and say what you are trying to do. There are no silly questions.
