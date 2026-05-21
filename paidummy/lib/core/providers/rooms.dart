/// Lobby-side providers: bet tiers, shop packages, and which room the player
/// is currently in.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/index.dart';
import 'session.dart';

/// Server-defined coin shop menu (`GET /shop/packages`).
final shopPackagesProvider = FutureProvider.autoDispose<List<CoinPackage>>((
  ref,
) async {
  final g = ref.watch(sessionProvider);
  if (g == null) return const [];
  return ref.read(apiClientProvider).shopPackages(g.token);
});

/// Server-defined bet-tier menu (`GET /tiers`). Each `TierInfo` carries the
/// stake plus a live snapshot of how many players + rooms exist at it.
final tiersProvider = FutureProvider.autoDispose<List<TierInfo>>((ref) async {
  final g = ref.watch(sessionProvider);
  if (g == null) return const [];
  return ref.read(apiClientProvider).tiers(g.token);
});

/// The room the player is currently in (null = in lobby).
final currentRoomProvider = StateProvider<String?>((ref) => null);

/// True when the current room was entered as a view-only spectator. The
/// game screen connects with spectate=1 and hides all action controls.
final spectatingProvider = StateProvider<bool>((ref) => false);

/// Whether the first-run tutorial has been shown this session. The lobby
/// auto-opens the tutorial once when this is false, then flips it.
final tutorialSeenProvider = StateProvider<bool>((ref) => false);
