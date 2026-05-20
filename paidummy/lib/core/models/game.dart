/// In-game per-player view: seats, melds, hand, penalties, and the
/// reduced GameView that drives the table UI.
library;

class PlayerPublic {
  const PlayerPublic({
    required this.seat,
    required this.name,
    required this.ready,
    required this.handCount,
    required this.connected,
    this.coins = 0,
  });
  final int seat;
  final String name;
  final bool ready;
  final int handCount;
  final bool connected;
  final int coins;

  factory PlayerPublic.fromJson(Map<String, dynamic> j) => PlayerPublic(
    seat: (j['seat'] as num?)?.toInt() ?? 0,
    name: j['name'] as String? ?? '',
    ready: j['ready'] as bool? ?? false,
    handCount: (j['hand_count'] as num?)?.toInt() ?? 0,
    connected: j['connected'] as bool? ?? false,
    coins: (j['coins'] as num?)?.toInt() ?? 0,
  );
}

/// Transient penalty notification surfaced to the affected player.
/// `reason` is "full" (ทิ้งเต็ม — discarder pays) or "dummy" (ทิ้งดัมมี่ —
/// the previous discarder pays after an opponent picks it up).
class PenaltyToast {
  const PenaltyToast({required this.points, required this.reason});
  final int points;
  final String reason;
}

/// One chat line as received over the WS `chat` envelope. `seat == -1`
/// means a system message (unused today; reserved for future "X joined"
/// notices).
class ChatMessage {
  const ChatMessage({
    required this.seat,
    required this.name,
    required this.text,
    required this.timestampMs,
  });
  final int seat;
  final String name;
  final String text;
  final int timestampMs;

  factory ChatMessage.fromJson(Map<String, dynamic> j) => ChatMessage(
    seat: (j['seat'] as num?)?.toInt() ?? -1,
    name: j['name'] as String? ?? '',
    text: j['text'] as String? ?? '',
    timestampMs: (j['ts'] as num?)?.toInt() ?? 0,
  );
}

class MeldView {
  const MeldView({
    required this.id,
    required this.kind,
    required this.cards,
    required this.owner,
  });
  final String id;
  final String kind;
  final List<String> cards;
  final int owner;

  factory MeldView.fromJson(Map<String, dynamic> j) => MeldView(
    id: j['id'] as String? ?? '',
    kind: j['kind'] as String? ?? 'set',
    cards: ((j['cards'] as List?) ?? const []).map((e) => e as String).toList(),
    owner: (j['owner'] as num?)?.toInt() ?? 0,
  );
}

/// GameView is the client's single source of truth, reduced from the server's
/// per-player `room_state` plus transient turn/error/result signals.
class GameView {
  const GameView({
    this.connected = false,
    this.started = false,
    this.bet = 0,
    this.countdownEndMs = 0,
    this.turnEndMs = 0,
    this.phase = 'waiting',
    this.turn = -1,
    this.yourSeat = -1,
    this.players = const [],
    this.yourHand = const [],
    this.melds = const [],
    this.discardTop = '',
    this.discardPile = const [],
    this.drawCount = 0,
    this.headCard = '',
    this.matchScores = const {},
    this.allowed = const [],
    this.canAutoKnock = false,
    this.lastError,
    this.lastActionPoints,
    this.lastPenalty,
    this.roundResult,
    this.matchResult,
    this.selected = const {},
    this.chatMessages = const [],
    this.chatUnread = 0,
  });

  final bool connected;
  final bool started;
  final int bet;
  final int countdownEndMs; // unix ms; 0 = no pre-start countdown
  final int turnEndMs; // unix ms; 0 = no active turn timer
  final String phase;
  final int turn;
  final int yourSeat;
  final List<PlayerPublic> players;
  final List<String> yourHand;
  final List<MeldView> melds;
  final String discardTop;
  final List<String> discardPile; // oldest→newest, lined up on the table
  final int drawCount;
  final String headCard;
  final Map<String, int> matchScores;
  final List<String> allowed;
  /// True iff the server's solver can find a going-out partition of the
  /// local player's hand right now (`PhaseMeld`, viewer's turn). The "นอค"
  /// button is enabled solely off this flag — clicking it sends
  /// `auto_knock` and the server lays melds + layoffs + knock atomically.
  final bool canAutoKnock;
  final String? lastError;
  /// Most recent per-action point gain (e.g. from a meld/layoff/pickup).
  /// One-shot: the UI consumes the value once, then `clearActionPoints` nils
  /// it so the next gain triggers a fresh listener.
  final int? lastActionPoints;
  /// Most recent ทิ้งเต็ม / ทิ้งดัมมี่ penalty pushed to this seat. One-shot,
  /// cleared by `clearPenalty`.
  final PenaltyToast? lastPenalty;
  final Map<String, dynamic>? roundResult;
  final Map<String, dynamic>? matchResult;

  /// Cards the local player has tapped to stage a meld/discard.
  final Set<String> selected;

  /// In-room chat backlog (oldest→newest), capped client-side to 50.
  final List<ChatMessage> chatMessages;
  /// Number of chat messages received since the user last opened the chat
  /// sheet. Drives the red dot on the chat button.
  final int chatUnread;

  bool get isMyTurn => turn >= 0 && turn == yourSeat;

  GameView copyWith({
    bool? connected,
    bool? started,
    int? bet,
    int? countdownEndMs,
    int? turnEndMs,
    String? phase,
    int? turn,
    int? yourSeat,
    List<PlayerPublic>? players,
    List<String>? yourHand,
    List<MeldView>? melds,
    String? discardTop,
    List<String>? discardPile,
    int? drawCount,
    String? headCard,
    Map<String, int>? matchScores,
    List<String>? allowed,
    bool? canAutoKnock,
    String? lastError,
    bool clearError = false,
    int? lastActionPoints,
    bool clearActionPoints = false,
    PenaltyToast? lastPenalty,
    bool clearPenalty = false,
    Map<String, dynamic>? roundResult,
    Map<String, dynamic>? matchResult,
    bool clearResults = false,
    Set<String>? selected,
    List<ChatMessage>? chatMessages,
    int? chatUnread,
  }) {
    return GameView(
      connected: connected ?? this.connected,
      started: started ?? this.started,
      bet: bet ?? this.bet,
      countdownEndMs: countdownEndMs ?? this.countdownEndMs,
      turnEndMs: turnEndMs ?? this.turnEndMs,
      phase: phase ?? this.phase,
      turn: turn ?? this.turn,
      yourSeat: yourSeat ?? this.yourSeat,
      players: players ?? this.players,
      yourHand: yourHand ?? this.yourHand,
      melds: melds ?? this.melds,
      discardTop: discardTop ?? this.discardTop,
      discardPile: discardPile ?? this.discardPile,
      drawCount: drawCount ?? this.drawCount,
      headCard: headCard ?? this.headCard,
      matchScores: matchScores ?? this.matchScores,
      allowed: allowed ?? this.allowed,
      canAutoKnock: canAutoKnock ?? this.canAutoKnock,
      lastError: clearError ? null : (lastError ?? this.lastError),
      lastActionPoints: clearActionPoints
          ? null
          : (lastActionPoints ?? this.lastActionPoints),
      lastPenalty: clearPenalty
          ? null
          : (lastPenalty ?? this.lastPenalty),
      roundResult: clearResults ? null : (roundResult ?? this.roundResult),
      matchResult: clearResults ? null : (matchResult ?? this.matchResult),
      selected: selected ?? this.selected,
      chatMessages: chatMessages ?? this.chatMessages,
      chatUnread: chatUnread ?? this.chatUnread,
    );
  }

  factory GameView.fromRoomState(
    Map<String, dynamic> j, {
    required GameView prev,
  }) {
    return prev.copyWith(
      connected: true,
      started: j['started'] as bool? ?? false,
      bet: (j['bet'] as num?)?.toInt() ?? prev.bet,
      countdownEndMs: (j['countdown_end_ms'] as num?)?.toInt() ?? 0,
      turnEndMs: (j['turn_end_ms'] as num?)?.toInt() ?? 0,
      phase: j['phase'] as String? ?? 'waiting',
      turn: (j['turn'] as num?)?.toInt() ?? -1,
      yourSeat: (j['your_seat'] as num?)?.toInt() ?? -1,
      players: ((j['players'] as List?) ?? const [])
          .map((e) => PlayerPublic.fromJson(e as Map<String, dynamic>))
          .toList(),
      yourHand: ((j['your_hand'] as List?) ?? const [])
          .map((e) => e as String)
          .toList(),
      melds: ((j['melds'] as List?) ?? const [])
          .map((e) => MeldView.fromJson(e as Map<String, dynamic>))
          .toList(),
      discardTop: j['discard_top'] as String? ?? '',
      discardPile: ((j['discard_pile'] as List?) ?? const [])
          .map((e) => e as String)
          .toList(),
      drawCount: (j['draw_count'] as num?)?.toInt() ?? 0,
      headCard: j['head_card'] as String? ?? '',
      matchScores: ((j['match_scores'] as Map?) ?? const {}).map(
        (k, v) => MapEntry(k as String, (v as num).toInt()),
      ),
      canAutoKnock: j['can_auto_knock'] as bool? ?? false,
      selected: const {},
    );
  }
}
