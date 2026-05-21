/// Session, "me" wallet, and coin history providers.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/index.dart';
import '../network/index.dart';

final apiClientProvider = Provider<ApiClient>((ref) => ApiClient());

/// Holds the current guest session (null until a name is entered).
class SessionController extends StateNotifier<Guest?> {
  SessionController(this._api) : super(null);
  final ApiClient _api;

  Future<void> createGuest(String name, {String ref = ''}) async {
    state = await _api.createGuest(
      name.trim().isEmpty ? 'Player' : name.trim(),
      ref: ref.trim(),
    );
  }

  void signOut() => state = null;
}

final sessionProvider = StateNotifierProvider<SessionController, Guest?>(
  (ref) => SessionController(ref.read(apiClientProvider)),
);

/// Live "me" — wallet + rank + stats from `GET /me`. autoDispose so each
/// return to the lobby refreshes after a match settles or a shop purchase.
final meProvider = FutureProvider.autoDispose<Guest>((ref) async {
  final g = ref.watch(sessionProvider);
  if (g == null) {
    return const Guest(id: '', name: '', token: '');
  }
  return ref.read(apiClientProvider).me(g.token);
});

/// My recent match outcomes for the history sheet.
final coinHistoryProvider = FutureProvider.autoDispose<List<CoinHistoryRow>>((
  ref,
) async {
  final g = ref.watch(sessionProvider);
  if (g == null) return const [];
  return ref.read(apiClientProvider).coinHistory(g.token);
});

/// Daily-login bonus state — `null` until a guest is signed in. The lobby
/// chip reads this to decide whether to show the gift CTA or the
/// "claimed — back tomorrow" pill.
final dailyBonusProvider = FutureProvider.autoDispose<DailyBonus?>((ref) async {
  final g = ref.watch(sessionProvider);
  if (g == null) return null;
  return ref.read(apiClientProvider).dailyStatus(g.token);
});

/// Leaderboard rows, parameterised by period ('alltime' | 'weekly' | 'daily').
final leaderboardProvider = FutureProvider.autoDispose
    .family<List<LeaderboardRow>, String>((ref, period) async {
  final g = ref.watch(sessionProvider);
  if (g == null) return const [];
  return ref.read(apiClientProvider).leaderboard(g.token, period: period);
});

/// Today's daily missions for the signed-in guest.
final missionsProvider =
    FutureProvider.autoDispose<List<MissionStatus>>((ref) async {
  final g = ref.watch(sessionProvider);
  if (g == null) return const [];
  return ref.read(apiClientProvider).missions(g.token);
});
