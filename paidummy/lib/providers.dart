/// Riverpod wiring: session, room list, and the WebSocket-driven game
/// controller. The controller is the only place client state is mutated, and
/// it never computes game logic — it reduces server events.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'models.dart';
import 'network.dart';

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

/// Live wallet balance (`GET /me`). autoDispose so each return to the lobby
/// refreshes after a match settles.
final walletProvider = FutureProvider.autoDispose<int>((ref) async {
  final g = ref.watch(sessionProvider);
  if (g == null) return 0;
  final fresh = await ref.read(apiClientProvider).me(g.token);
  return fresh.coins;
});

/// Server-defined bet-tier menu (`GET /tiers`).
final tiersProvider = FutureProvider.autoDispose<List<int>>((ref) async {
  final g = ref.watch(sessionProvider);
  if (g == null) return const [];
  return ref.read(apiClientProvider).tiers(g.token);
});

/// The room the player is currently in (null = in lobby).
final currentRoomProvider = StateProvider<String?>((ref) => null);

/// Currently selected table meld (for layoff "ฝาก"). Null = no meld targeted,
/// in which case the "ลง" button creates a new meld from selected hand cards.
final selectedMeldProvider = StateProvider<String?>((ref) => null);

class GameController extends StateNotifier<GameView> {
  GameController(this._ws) : super(const GameView()) {
    _ws.messages.listen(_onMessage);
  }
  final WsClient _ws;

  void connect(String token, String roomId) {
    state = const GameView();
    _ws.connect(token, roomId);
  }

  void _onMessage(Map<String, dynamic> m) {
    final type = m['type'] as String? ?? '';
    final data = (m['data'] as Map?)?.cast<String, dynamic>() ?? const {};
    switch (type) {
      case 'room_state':
        state = GameView.fromRoomState(data, prev: state);
        break;
      case 'your_turn':
        state = state.copyWith(
          phase: data['phase'] as String? ?? state.phase,
          allowed: ((data['allowed'] as List?) ?? const [])
              .map((e) => e as String)
              .toList(),
        );
        break;
      case 'round_result':
        state = state.copyWith(roundResult: data);
        break;
      case 'match_result':
        state = state.copyWith(matchResult: data);
        break;
      case 'error':
        state = state.copyWith(lastError: data['message'] as String?);
        break;
      case 'socket_closed':
      case 'socket_error':
        state = state.copyWith(connected: false);
        break;
    }
  }

  // --- player intents (server-authoritative) ---
  void ready() => _ws.send('ready');
  void drawDeck() => _ws.send('draw_deck');

  /// "เก็บ" — picking up the discard top requires committing it into a meld
  /// with [supportingCards] from the hand in the same action (server rule).
  void drawDiscard(List<String> supportingCards) =>
      _ws.send('draw_discard', {'cards': supportingCards});
  void knock(String card, {bool dark = false}) =>
      _ws.send('knock', {'card': card, 'dark': dark});
  void discard(String card) => _ws.send('discard', {'card': card});
  void meldSelected() {
    if (state.selected.isEmpty) return;
    _ws.send('meld', {'cards': state.selected.toList()});
    clearSelection();
  }

  void layoffSelected(String meldId) {
    if (state.selected.isEmpty) return;
    _ws.send('layoff', {'meld_id': meldId, 'cards': state.selected.toList()});
    clearSelection();
  }

  void discardSelectedFirst() {
    if (state.selected.isEmpty) return;
    discard(state.selected.first);
    clearSelection();
  }

  void leave() => _ws.send('leave');

  void toggleSelect(String card) {
    final s = Set<String>.from(state.selected);
    if (!s.add(card)) s.remove(card);
    state = state.copyWith(selected: s);
  }

  void clearSelection() => state = state.copyWith(selected: const {});

  void clearError() => state = state.copyWith(clearError: true);
}

/// Local display order for the player's own hand. The server's `your_hand`
/// is the authoritative *set* of cards; this notifier keeps a user-chosen
/// permutation of that set so drag-reordering survives server frames.
///
/// reconcile preserves existing positions for cards still in hand and appends
/// newly drawn cards at the end — exactly what you want when you draw or
/// discard.
class HandOrderController extends StateNotifier<List<String>> {
  HandOrderController() : super(const []);

  void reconcile(List<String> server) {
    final inServer = Set<String>.from(server);
    final next = <String>[
      for (final c in state)
        if (inServer.contains(c)) c,
    ];
    for (final c in server) {
      if (!next.contains(c)) next.add(c);
    }
    if (next.length != state.length ||
        !List.generate(
          next.length,
          (i) => next[i] == state[i],
        ).every((b) => b)) {
      state = next;
    }
  }

  /// Cycle between two useful arrangements:
  ///   • by rank then suit  → equal-rank cards cluster (good for sets / "คู่")
  ///   • by suit then rank  → consecutive same-suit cards cluster (good for
  ///     runs / "เรียง ตาม สี")
  /// One press of the "จัดไพ่" button toggles to the other view.
  int _sortPhase = 1; // start opposite of bySuit so first press → byRank
  void cycleSort() {
    _sortPhase = (_sortPhase + 1) % 2;
    int suitVal(String c) {
      const order = 'CDHS';
      return order.indexOf(c[1]);
    }

    int rankVal(String c) {
      final r = c[0];
      switch (r) {
        case 'A':
          return 1;
        case 'T':
          return 10;
        case 'J':
          return 11;
        case 'Q':
          return 12;
        case 'K':
          return 13;
      }
      return int.tryParse(r) ?? 0;
    }

    final next = List<String>.from(state)
      ..sort((a, b) {
        if (a.length < 2 || b.length < 2) return 0;
        if (_sortPhase == 0) {
          // by rank then suit
          final r = rankVal(a) - rankVal(b);
          return r != 0 ? r : suitVal(a) - suitVal(b);
        }
        // by suit then rank
        final s = suitVal(a) - suitVal(b);
        return s != 0 ? s : rankVal(a) - rankVal(b);
      });
    state = next;
  }

  void move(int from, int to) {
    if (from < 0 ||
        to < 0 ||
        from >= state.length ||
        to >= state.length ||
        from == to) {
      return;
    }
    final next = List<String>.from(state);
    final item = next.removeAt(from);
    next.insert(to, item);
    state = next;
  }
}

final handOrderProvider =
    StateNotifierProvider<HandOrderController, List<String>>(
      (_) => HandOrderController(),
    );

final wsClientProvider = Provider<WsClient>((ref) {
  final ws = WsClient();
  ref.onDispose(ws.dispose);
  return ws;
});

final gameControllerProvider = StateNotifierProvider<GameController, GameView>(
  (ref) => GameController(ref.read(wsClientProvider)),
);
