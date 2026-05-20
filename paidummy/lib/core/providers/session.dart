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

  Future<void> createGuest(String name) async {
    state = await _api.createGuest(
      name.trim().isEmpty ? 'Player' : name.trim(),
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
