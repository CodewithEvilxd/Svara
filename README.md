# Svara

Svara is a Flutter music app focused on smooth streaming, offline listening, and a clean playback experience on Android.

It includes search, queue management, background playback, deep links for jam sessions, local caching, and polished UI interactions.

## Table of Contents

- [What You Get](#what-you-get)
- [Tech Stack](#tech-stack)
- [Project Structure](#project-structure)
- [Getting Started](#getting-started)
- [Build Release APK](#build-release-apk)
- [Configuration](#configuration)
- [Deep Linking](#deep-linking)
- [Troubleshooting](#troubleshooting)
- [Contributing](#contributing)
- [Links](#links)
- [License](#license)

## What You Get

- Song, album, artist, and playlist search
- Audio playback with background support
- Queue loading, seeking, and session restore style behavior
- Offline support for downloaded content
- Liked songs and local persistence features
- Dynamic theming support with custom brand typography
- Jam link handling through app links

## Tech Stack

- Flutter (Dart)
- Riverpod for app state
- just_audio + audio_service for playback and background audio
- Hive + SharedPreferences for local persistence
- HTTP/Dio based API integrations
- Supabase Flutter client (project integrated)

## Project Structure

```text
lib/
	main.dart                # App bootstrap, theme, routes, deep-link wiring
	components/              # Reusable UI widgets
	models/                  # App data models and DB helpers
	screens/                 # Feature screens (home, search, library, etc.)
	services/                # API, audio, notifications, offline, utilities
	shared/                  # Constants and shared global values
	utils/                   # Theme and helper utilities
assets/
	fonts/
	icons/
test/
```

## Getting Started

### 1) Prerequisites

- Flutter SDK installed
- Android Studio or VS Code with Flutter tooling
- Android device/emulator

Current Dart constraint in this project:

```yaml
sdk: ">3.7.2 < 4.0.0"
```

### 2) Clone and Install

```bash
git clone https://github.com/codewithevilxd/svara.git
cd svara
flutter pub get
```

### 3) Run in Debug

```bash
flutter run
```

## Build Release APK

```bash
flutter build apk --release
```

Generated APK is typically available under:

```text
build/app/outputs/flutter-apk/
```

## Configuration

### App Identity

- App name: `Svara`
- Android package: `com.codewithevilxd.svara`
- Deep link scheme: `svara`

### API Base URL

Default API endpoint is set in `lib/shared/constants.dart`:

```dart
const apiBaseUrl = 'https://rf-snowy.vercel.app/';
```

If you switch backend:

- Keep endpoint shapes and response contracts compatible
- Validate search, song details, playlist, and queue related flows
- Re-test offline/download and playback actions end-to-end

### Supabase

Supabase keys and URL are currently configured in app constants.
For production-grade deployments, move secrets and environment-specific values to a secure config strategy.

## Deep Linking

Svara listens for incoming app links and can restore playback context from jam payloads.

High-level flow:

- Parse incoming URI
- Resolve queue/song payload
- Load queue or seed track
- Seek to incoming position (if provided)

## Troubleshooting

- `flutter pub get` fails:
	- Run `flutter clean`
	- Ensure stable internet and rerun

- App launches but music data does not load:
	- Verify API endpoint availability
	- Check internet permissions and connectivity

- Build issues on Android:
	- Confirm Android SDK and Gradle toolchain setup
	- Run `flutter doctor` and fix reported issues

## Contributing

Contributions are welcome.

1. Fork the repository
2. Create a feature branch
3. Commit changes with clear messages
4. Open a pull request with context and screenshots (if UI changes)

## Links

- Repository: https://github.com/codewithevilxd/svara
- Developer: https://github.com/codewithevilxd
- Portfolio: https://nishantdev.space
- Contact: codewithevilxd@gmail.com

## License

MIT License
