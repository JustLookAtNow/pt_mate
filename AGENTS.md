# Repository Guidelines

## Project Structure & Module Organization
This repository contains a Flutter client and a small Go backend.

- `lib/`: Flutter app code (`pages/`, `services/`, `providers/`, `widgets/`, `models/`).
- `test/`: Dart/Flutter tests, including widget and service tests (`*_test.dart`).
- `assets/`: app assets and site definitions (`assets/sites/` + generated `assets/sites_manifest.json`).
- `server/`: Go API service (`main.go`, `cmd/`, `migrations/`, `admin/`).
- Platform folders: `android/`, `ios/`, `linux/`, `macos/`, `windows/`, `web/`.

## Build, Test, and Development Commands
- `flutter pub get`: install Flutter dependencies.
- `flutter run`: run app in debug mode.
- `flutter build apk --release`: build Android release APK.
- `flutter analyze`: run static analysis with configured lints.
- `flutter test`: run all Flutter tests.
- `./generate_sites_manifest.sh`: regenerate site manifest after editing `assets/sites/*`.
- `cd server && go run .`: run backend locally.
- `cd server && go test ./...`: run backend tests.

## Coding Style & Naming Conventions
- Follow `analysis_options.yaml` (`flutter_lints`); keep analyzer warnings at zero.
- Use Dart formatting defaults (`dart format .`): 2-space indentation, trailing commas where helpful.
- File names: `snake_case.dart`; classes/enums: `PascalCase`; methods/variables: `camelCase`.
- Keep feature code grouped by domain (for example, adapter logic under `lib/services/api/`).

## Testing Guidelines
- Flutter tests use `flutter_test`; backend uses Go’s built-in `testing` package.
- Name tests with `*_test.dart` and `*_test.go`.
- Add or update tests for behavior changes in adapters, parsing, storage, and widgets.
- Run both app and server tests before opening a PR when touching both modules.
- No fixed coverage gate is enforced; prioritize meaningful assertions for changed paths.

## Commit & Pull Request Guidelines
- Use Conventional Commit-style prefixes seen in history: `feat:`, `fix:`, `refactor:`, `chore:`, `release:`.
- Keep commits focused and descriptive (example: `feat: add Unit3D category mapping`).
- PRs should include:
  - clear summary of behavior changes,
  - linked issue/PR number when applicable (for example `#93`),
  - screenshots/GIFs for UI changes,
  - notes for config/data updates (especially `assets/sites/` and manifest regeneration).
