<h1 align="center">Ember</h1>

<p align="center">
  A private, local-first habit and streak tracker for Android.<br>
  Tap a ring, keep the streak burning, and keep your data on your own phone.
</p>

<p align="center">
  <a href="LICENSE"><img alt="License: GPL-3.0" src="https://img.shields.io/badge/license-GPL--3.0-blue"></a>
  <a href="https://github.com/ayushgohil/Habit-Tracker-APP/releases/latest"><img alt="Latest release" src="https://img.shields.io/github/v/release/ayushgohil/Habit-Tracker-APP?include_prereleases"></a>
  <img alt="Android 8.0+" src="https://img.shields.io/badge/Android-8.0%2B-3DDC84">
  <img alt="Built with Flutter" src="https://img.shields.io/badge/built%20with-Flutter-02569B">
  <a href="https://github.com/ayushgohil/Habit-Tracker-APP/releases"><img alt="Downloads" src="https://img.shields.io/github/downloads/ayushgohil/Habit-Tracker-APP/total"></a>
  <a href="https://github.com/ayushgohil/Habit-Tracker-APP/stargazers"><img alt="Stars" src="https://img.shields.io/github/stars/ayushgohil/Habit-Tracker-APP?style=flat"></a>
</p>

<!--
Screenshots go here once they are added to docs/screenshots/, for example:

<p align="center">
  <img src="docs/screenshots/home.png" width="22%" alt="Home">
  <img src="docs/screenshots/stats.png" width="22%" alt="Stats">
  <img src="docs/screenshots/widgets.png" width="22%" alt="Widgets">
  <img src="docs/screenshots/themes.png" width="22%" alt="Themes">
</p>
-->

## Why Ember

- **Yours alone.** No account, no ads, no analytics and no server. Everything is stored in a database on your phone, and Ember's own manifest does not ask for internet access.
- **Built around streaks.** Rings, flexible schedules, streaks that warn you before they break, and a stats screen that shows how you are really doing.
- **Lives on your home screen.** Seven widgets, a Quick Settings tile and launcher shortcuts let you log a habit without opening the app.
- **Open and changeable.** Ember is free software under the GPL-3.0. Read it, change it, and help make it better.

## Features

**Tracking**
- Ring-grid home screen: tap to log, long-press for details, edit, pause, archive or delete
- Normal, negative ("keep under this limit") and timed habits; habits that need several taps a day, such as 8 glasses of water
- Schedules: every day, chosen weekdays, N times a week, every N days, and weekly, fortnightly, monthly or yearly goals
- Log past days, add a note for each day, undo, and set the hour your day starts
- Reminders for every habit at the times you choose
- Habit templates, a habit library for pausing, restoring and reordering, and an Up Next list

**Timers**
- A full-screen timer with a progress ring that keeps running with the app closed
- Split a goal into sessions (for example four 25-minute focus rounds), with a notification when each one ends
- A session that crosses midnight is credited to each day it ran on

**Streaks and stats**
- Current and best streak, completion rate and total done for every habit and schedule
- A warning when today's streak is about to be lost
- A calendar you can tap to fix any day, and week, month and year charts you can touch for details

**Widgets and shortcuts**
- A today's-list widget, plus six card widgets (streak, ring, week, trend, month and grid) in Dark, Glass and Colour styles
- A Quick Settings tile that logs your next habit, and launcher shortcuts
- Broadcast actions for Tasker and similar automation apps

**Look and feel**
- 32 colour themes, light, dark and follow-the-phone modes, and almost 300 habit icons

**Your data**
- Optional Health Connect: read steps, workouts and sleep to complete habits, and write water you log
- Back up to a file and restore it, import from CSV
- Optional app lock using your fingerprint, face or screen lock

## Download

Get the latest APK from the [Releases page](https://github.com/ayushgohil/Habit-Tracker-APP/releases/latest).

| Your phone | File to pick |
| --- | --- |
| Almost every phone from the last several years | `ember-…-arm64-v8a.apk` |
| Older 32-bit phones | `ember-…-armeabi-v7a.apk` |
| Emulators and some Chromebooks | `ember-…-x86_64.apk` |

Every release is signed with the same key, so a new APK installs over the old one and keeps your habits. `SHA256SUMS.txt` on each release lets you check your download.

**Obtainium (automatic updates).** Add `https://github.com/ayushgohil/Habit-Tracker-APP` in [Obtainium](https://github.com/ImranR98/Obtainium) and set the APK filter to `arm64`.

F-Droid and IzzyOnDroid listings are planned.

## Privacy

Ember stores habits, notes and settings in a local SQLite database. Nothing leaves your phone unless you export a backup yourself. Optional features ask for their own permissions: notifications and exact alarms for reminders, and Health Connect access if you turn on health syncing. You can remove any of them in Android settings.

## Build it yourself

You need the [Flutter SDK](https://docs.flutter.dev/get-started/install) (3.27 or newer), JDK 17 and the Android SDK (Android Studio installs both).

```bash
git clone https://github.com/ayushgohil/Habit-Tracker-APP.git
cd Habit-Tracker-APP

flutter pub get
dart run build_runner build --delete-conflicting-outputs   # database code
flutter run                                                # on a phone or emulator
```

Run `flutter analyze` and `flutter test` before you open a pull request. A local build is signed with Android's debug key, which is fine for trying things out. Release signing is explained in [docs/RELEASING.md](docs/RELEASING.md).

## Contributing

Bug reports, ideas and pull requests are welcome, whether it is a typo, a new icon, a translation fix or a whole feature.

1. Read [CONTRIBUTING.md](CONTRIBUTING.md) for setup, checks and what a good pull request looks like.
2. Skim [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) to find your way around the code.
3. Look for issues labelled `good first issue`, or open one to talk through your idea first.

Please follow the [Code of Conduct](CODE_OF_CONDUCT.md). To report a security problem privately, see [SECURITY.md](SECURITY.md).

## Roadmap

- Release polish, store listings and screenshots
- Optional backup to your own Google Drive
- Translations
- A Wear OS companion

Not planned: Screen Time tracking (Android only allows it with a special usage-access permission), accounts and cloud sync.

## License

Ember is free software, released under the [GNU General Public License v3.0](LICENSE). You can use, study, change and share it, and any version you share must stay open under the same license.

Copyright (C) 2026 Ayush Gohil.
