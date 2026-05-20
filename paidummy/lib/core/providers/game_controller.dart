/// WS-driven game controller plus the local hand-ordering notifier and
/// selection providers. The controller is the only place client state is
/// mutated, and it never computes game logic — it reduces server events.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/index.dart';
import '../network/index.dart';

/// Currently selected table meld (for layoff "ฝาก"). Null = no meld targeted,
/// in which case the "ลง" button creates a new meld from selected hand cards.
final selectedMeldProvider = StateProvider<String?>((ref) => null);

/// Discard-pile cards the player has tapped to include in a pickup ("เก็บ").
/// The deepest (oldest, smallest index) selected card becomes the target —
/// the pile is truncated there. Any other selected pile cards are passed to
/// the engine as part of the meld; unselected pile cards above the target
/// fall into the player's hand as extras.
final selectedDiscardCardsProvider = StateProvider<Set<String>>(
  (ref) => const {},
);

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
      case 'action_points':
        // One-shot "+N แต้ม" badge for the actor; UI listens, shows, clears.
        state = state.copyWith(
          lastActionPoints: (data['points'] as num?)?.toInt(),
        );
        break;
      case 'penalty_points':
        state = state.copyWith(
          lastPenalty: PenaltyToast(
            points: (data['points'] as num?)?.toInt() ?? 0,
            reason: data['reason'] as String? ?? '',
          ),
        );
        break;
      case 'chat':
        // Append to the bounded backlog (oldest evicted at 50) and bump
        // the unread counter; the UI clears it via clearChatUnread() when
        // the user opens the chat sheet.
        final msg = ChatMessage.fromJson(data);
        final next = [...state.chatMessages, msg];
        if (next.length > 50) next.removeRange(0, next.length - 50);
        state = state.copyWith(
          chatMessages: next,
          chatUnread: state.chatUnread + 1,
        );
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

  /// "เก็บ" — pick a card from the discard pile.
  ///
  /// If [meldId] is supplied the engine takes the **ฝากดัมมี่** path: the
  /// picked card is laid off directly onto that existing meld and no new
  /// meld is formed (supportingCards may be empty).
  ///
  /// Otherwise the picked card must immediately combine with
  /// [supportingCards] from the hand into a brand-new meld.
  ///
  /// If [targetCard] is null/empty the top of the discard pile is taken;
  /// otherwise the engine finds [targetCard] in the pile and (for non-top
  /// picks) pulls every card above it into the player's hand.
  void drawDiscard(
    List<String> supportingCards, {
    String? targetCard,
    String? meldId,
  }) => _ws.send('draw_discard', {
    'cards': supportingCards,
    if (targetCard != null && targetCard.isNotEmpty) 'card': targetCard,
    if (meldId != null && meldId.isNotEmpty) 'meld_id': meldId,
  });
  void knock(String card, {bool dark = false}) =>
      _ws.send('knock', {'card': card, 'dark': dark});

  /// Auto-knock — server's solver lays down every necessary meld/layoff and
  /// finalises the knock atomically. Enabled by `view.canAutoKnock`.
  void autoKnock() => _ws.send('auto_knock', const {});
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

  /// Sends a chat line to all seated players. Empty lines are dropped
   /// server-side; the client just trims here for snappier feedback.
  void sendChat(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    _ws.send('chat', {'text': trimmed});
  }

  /// Resets the unread chat badge. Call when the chat sheet opens.
  void clearChatUnread() {
    if (state.chatUnread == 0) return;
    state = state.copyWith(chatUnread: 0);
  }

  void leave() => _ws.send('leave');

  void toggleSelect(String card) {
    final s = Set<String>.from(state.selected);
    if (!s.add(card)) s.remove(card);
    state = state.copyWith(selected: s);
  }

  void clearSelection() => state = state.copyWith(selected: const {});

  void clearError() => state = state.copyWith(clearError: true);
  void clearActionPoints() =>
      state = state.copyWith(clearActionPoints: true);
  void clearPenalty() => state = state.copyWith(clearPenalty: true);
  /// Clears the cached round/match-result envelopes so the result dialog
  /// will re-open the next time the server emits a fresh round_result /
  /// match_result. Called by the "อีกตา" rematch button.
  void clearResults() => state = state.copyWith(clearResults: true);
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
