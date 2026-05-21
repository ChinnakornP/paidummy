/// App shell: MaterialApp + the RootScreen that gates Home → Lobby → Game
/// based on the current Riverpod session/room state.
library;

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/i18n/strings.dart';
import 'core/providers/index.dart';
import 'core/theme/felt_theme.dart';
import 'features/game/game_screen.dart';
import 'features/home/home_screen.dart';
import 'features/lobby/lobby_screen.dart';

class PaiDummyApp extends ConsumerWidget {
  const PaiDummyApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp(
      title: 'Pai Dummy',
      debugShowCheckedModeBanner: false,
      theme: buildFeltTheme(),
      locale: ref.watch(localeProvider),
      supportedLocales: supportedLocales,
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: const RootScreen(),
    );
  }
}

class RootScreen extends ConsumerWidget {
  const RootScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final guest = ref.watch(sessionProvider);
    if (guest == null) return const HomeScreen();
    final room = ref.watch(currentRoomProvider);
    if (room == null) return const LobbyScreen();
    return GameScreen(roomId: room);
  }
}
