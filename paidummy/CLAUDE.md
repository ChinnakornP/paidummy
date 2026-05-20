# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project state

`paidummy` is the Flutter client for **Pai Dummy** (Thai Dummy card game). It talks to the Go server in the sibling `../server/` folder over REST + WebSocket. See `../README.md` for the full system and how to run both.

Client layout is **feature-first** (all under `lib/`, no codegen — hand-rolled models keep `flutter analyze` clean). Each folder has an `index.dart` barrel so callers `import 'features/<x>/widgets/index.dart';` once.

```
lib/
├─ main.dart                 entry; locks landscape orientation then runs PaiDummyApp
├─ app.dart                  PaiDummyApp + RootScreen (Home → Lobby → Game gate)
├─ core/
│  ├─ env.dart               API_BASE / WS_BASE, overridable via --dart-define
│  ├─ theme/felt_theme.dart  ColorScheme.fromSeed(0xFF0B6B3A) + Material3
│  ├─ models/                immutable wire models, GameView is the single source of truth
│  │  ├─ guest.dart          Guest, Rank, GuestStats, CoinHistoryRow
│  │  ├─ room.dart           RoomInfo, RoomHistoryPlayer, RoomHistoryMatch, TierInfo
│  │  ├─ shop.dart           CoinPackage
│  │  └─ game.dart           PlayerPublic, MeldView, PenaltyToast, GameView
│  ├─ network/               REST + WS — no game logic, the server is authoritative
│  │  ├─ api_client.dart     ApiClient + QuickplayException
│  │  └─ ws_client.dart      WsClient (broadcast stream of {type,data} envelopes)
│  └─ providers/             Riverpod wiring
│     ├─ session.dart        SessionController, sessionProvider, apiClientProvider, meProvider, coinHistoryProvider
│     ├─ rooms.dart          tiersProvider, shopPackagesProvider, currentRoomProvider
│     └─ game_controller.dart  GameController (only state mutator; reduces server events),
│                              HandOrderController, wsClientProvider, gameControllerProvider,
│                              handOrderProvider, selectedMeldProvider, selectedDiscardCardsProvider
├─ features/
│  ├─ home/                  guest sign-in
│  │  ├─ home_screen.dart
│  │  └─ widgets/            HomeLogo, EntryCard
│  ├─ lobby/                 bet-tier picker (server-managed quickplay)
│  │  ├─ lobby_screen.dart   _LobbyScrollBehavior (mouse+trackpad drag)
│  │  └─ widgets/            LobbyTopBar+LobbyIconButton+LobbySectionHeader, TierCard+TierVisual+TierBadge+TierCta, WalletPill+RankPill
│  ├─ game/                  in-room felt + overlay
│  │  ├─ game_screen.dart    GameScreen — Flame felt + Flutter Stack overlay
│  │  ├─ game_table.dart     Flame TableGame (purely visual, paints whatever GameView it's given)
│  │  └─ widgets/            Seat+SeatPalette+kSeatPalettes/kSelfSeatPalette, HandAndControls+SortButton,
│  │                         HandFan, CenterPile, QuadrantMeldsLayer+MeldQuadrant, ResultBody,
│  │                         CountdownChip+TurnTimerChip+WaitingBanner, ShopButton+SideTab+ChatButton+RightChrome,
│  │                         GameButton+RoundIconButton
│  ├─ shop/                  modal coin shop sheet
│  │  ├─ shop_sheet.dart     showShopSheet() helper + ShopSheet
│  │  └─ widgets/            PackageCard
│  └─ history/               recent matches sheet
│     ├─ history_sheet.dart  showHistorySheet() helper + HistorySheet
│     └─ widgets/            StatChip, HistoryRow
└─ shared/widgets/           cross-feature: FeltBackground+FeltSheenPainter, FloatingSuit, PillButton
```

Architectural rules (unchanged by the split):
- `GameController` is the only place client state is mutated, and it *reduces* server events — it never computes game logic. The Go server in `../server/internal/game/` is authoritative.
- Flame `TableGame` is purely visual; seat / hand / controls are Flutter overlays.

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
- `test/widget_test.dart` is a smoke test that pumps `ProviderScope(child: PaiDummyApp())` and asserts `HomeScreen` renders (no backend needed — no network call until "Play as guest"). Keep it compiling when you restructure `app.dart` / `main.dart` / `features/home/`.
- Private-to-library underscore prefixes (`_FooState`, `_Helper`) are fine *within* a single file. If you need to use a widget across feature files, make it public (no underscore) and export it through the relevant `widgets/index.dart` barrel.
- The server's pure rules engine and ruleset live in `../server/internal/game/` (`ruleset.go` centralizes every tunable with `// TODO(spec)` markers). Do not reimplement game logic client-side.

## Notes

- This directory is not currently a git repository. Do not assume git history exists; if version control is needed, initialize it explicitly.
