# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project state

`paidummy` is the Flutter client for **Pai Dummy** (Thai Dummy card game). It talks to the Go server in the sibling `../server/` folder over REST + WebSocket. See `../README.md` for the full system and how to run both.

Client layering (all under `lib/`, no codegen — hand-rolled models keep `flutter analyze` clean):
- `env.dart` — `API_BASE`/`WS_BASE`, overridable via `--dart-define`.
- `models.dart` — immutable wire models; `GameView` is the client's single source of truth.
- `network.dart` — `ApiClient` (REST) and `WsClient` (WebSocket).
- `providers.dart` — Riverpod: `sessionProvider`, `roomListProvider`, `currentRoomProvider`, and `gameControllerProvider` (the only state mutator; it *reduces* server events, never computes game logic — the server is authoritative).
- `game_table.dart` — Flame `TableGame`, purely visual; it paints whatever `GameView` it is given.
- `ui.dart` — app shell + Home → Lobby → Game screens; interaction is Flutter widgets driving `GameController` intents.

Run with: `flutter run --dart-define=API_BASE=http://localhost:8887 --dart-define=WS_BASE=ws://localhost:8887`.

Dart SDK constraint: `^3.11.0`. Key deps: `flutter_riverpod`, `flame`, `web_socket_channel`, `http`; `flutter_lints` ^6.0.0 dev.

## Commands

Run all commands from the `paidummy/` directory (the Flutter project root, one level below the repo root).

- Install/sync deps: `flutter pub get`
- Run app: `flutter run` (add `-d chrome`, `-d macos`, `-d linux`, `-d windows`, or a device id; this project has android/ios/web/macos/linux/windows targets enabled)
- Static analysis (must pass clean): `flutter analyze`
- Format: `dart format .`
- Run all tests: `flutter test`
- Run a single test file: `flutter test test/widget_test.dart`
- Run a single test by name: `flutter test --plain-name "Counter increments smoke test"`
- Build release: `flutter build apk` / `flutter build ios` / `flutter build web` (etc.)

## Conventions

- Lints are enforced via `analysis_options.yaml` which includes `package:flutter_lints/flutter.yaml`. Treat `flutter analyze` warnings as failures. Customize rules under the `linter: rules:` block in that file rather than scattering `// ignore:` comments.
- `test/widget_test.dart` is a smoke test that pumps `ProviderScope(child: PaiDummyApp())` and asserts `HomeScreen` renders (no backend needed — no network call until "Play as guest"). Keep it compiling when you restructure `ui.dart`/`main.dart`.
- The server's pure rules engine and ruleset live in `../server/internal/game/` (`ruleset.go` centralizes every tunable with `// TODO(spec)` markers). Do not reimplement game logic client-side.

## Notes

- This directory is not currently a git repository. Do not assume git history exists; if version control is needed, initialize it explicitly.
