/// Plain immutable models mirroring the Go server's JSON wire format.
/// Hand-rolled (no codegen) to keep `flutter analyze` clean with zero
/// generated files.
library;

class Guest {
  const Guest({
    required this.id,
    required this.name,
    required this.token,
    this.coins = 0,
    this.rank,
    this.stats,
  });
  final String id;
  final String name;
  final String token;
  final int coins;
  final Rank? rank;
  final GuestStats? stats;

  factory Guest.fromJson(Map<String, dynamic> j) => Guest(
    id: j['id'] as String? ?? '',
    name: j['name'] as String? ?? '',
    token: j['token'] as String? ?? '',
    coins: (j['coins'] as num?)?.toInt() ?? 0,
    rank: j['rank'] is Map<String, dynamic>
        ? Rank.fromJson(j['rank'] as Map<String, dynamic>)
        : null,
    stats: j['stats'] is Map<String, dynamic>
        ? GuestStats.fromJson(j['stats'] as Map<String, dynamic>)
        : null,
  );
}

/// Player rank ("ยศ") derived from cumulative match wins.
class Rank {
  const Rank({
    required this.title,
    required this.level,
    required this.wins,
    this.nextTitle,
    this.nextWins,
  });
  final String title;
  final int level;
  final int wins;
  final String? nextTitle;
  final int? nextWins;

  factory Rank.fromJson(Map<String, dynamic> j) => Rank(
    title: j['title'] as String? ?? 'มือใหม่',
    level: (j['level'] as num?)?.toInt() ?? 0,
    wins: (j['wins'] as num?)?.toInt() ?? 0,
    nextTitle: j['next_title'] as String?,
    nextWins: (j['next_wins'] as num?)?.toInt(),
  );
}

class GuestStats {
  const GuestStats({
    required this.matchesPlayed,
    required this.matchesWon,
    required this.lifetimeProfit,
  });
  final int matchesPlayed;
  final int matchesWon;
  final int lifetimeProfit;

  factory GuestStats.fromJson(Map<String, dynamic> j) => GuestStats(
    matchesPlayed: (j['matches_played'] as num?)?.toInt() ?? 0,
    matchesWon: (j['matches_won'] as num?)?.toInt() ?? 0,
    lifetimeProfit: (j['lifetime_profit'] as num?)?.toInt() ?? 0,
  );
}

class CoinHistoryRow {
  const CoinHistoryRow({
    required this.matchId,
    required this.roomId,
    required this.bet,
    required this.coinDelta,
    required this.balanceAfter,
    required this.isWinner,
    required this.createdAt,
  });
  final String matchId;
  final String roomId;
  final int bet;
  final int coinDelta;
  final int balanceAfter;
  final bool isWinner;
  final DateTime createdAt;

  factory CoinHistoryRow.fromJson(Map<String, dynamic> j) => CoinHistoryRow(
    matchId: j['match_id'] as String? ?? '',
    roomId: j['room_id'] as String? ?? '',
    bet: (j['bet'] as num?)?.toInt() ?? 0,
    coinDelta: (j['coin_delta'] as num?)?.toInt() ?? 0,
    balanceAfter: (j['balance_after'] as num?)?.toInt() ?? 0,
    isWinner: j['is_winner'] as bool? ?? false,
    createdAt:
        DateTime.tryParse(j['created_at'] as String? ?? '') ??
        DateTime.fromMillisecondsSinceEpoch(0),
  );
}

class RoomHistoryPlayer {
  const RoomHistoryPlayer({
    required this.name,
    required this.coinDelta,
    required this.isWinner,
  });
  final String name;
  final int coinDelta;
  final bool isWinner;

  factory RoomHistoryPlayer.fromJson(Map<String, dynamic> j) =>
      RoomHistoryPlayer(
        name: j['name'] as String? ?? '',
        coinDelta: (j['coin_delta'] as num?)?.toInt() ?? 0,
        isWinner: j['is_winner'] as bool? ?? false,
      );
}

class RoomHistoryMatch {
  const RoomHistoryMatch({
    required this.matchId,
    required this.bet,
    this.finishedAt,
    required this.players,
  });
  final String matchId;
  final int bet;
  final DateTime? finishedAt;
  final List<RoomHistoryPlayer> players;

  factory RoomHistoryMatch.fromJson(Map<String, dynamic> j) => RoomHistoryMatch(
    matchId: j['match_id'] as String? ?? '',
    bet: (j['bet'] as num?)?.toInt() ?? 0,
    finishedAt: j['finished_at'] is String
        ? DateTime.tryParse(j['finished_at'] as String)
        : null,
    players: ((j['players'] as List?) ?? const [])
        .map((e) => RoomHistoryPlayer.fromJson(e as Map<String, dynamic>))
        .toList(),
  );
}

/// A purchasable bundle of in-game coins, defined by the server.
class CoinPackage {
  const CoinPackage({
    required this.id,
    required this.title,
    required this.coins,
    required this.priceTHB,
    this.badge,
  });
  final String id;
  final String title;
  final int coins;
  final int priceTHB;
  final String? badge; // "popular" / "best_value" / null

  factory CoinPackage.fromJson(Map<String, dynamic> j) => CoinPackage(
    id: j['id'] as String? ?? '',
    title: j['title'] as String? ?? '',
    coins: (j['coins'] as num?)?.toInt() ?? 0,
    priceTHB: (j['price_thb'] as num?)?.toInt() ?? 0,
    badge: j['badge'] as String?,
  );
}

class RoomInfo {
  const RoomInfo({
    required this.id,
    required this.name,
    required this.players,
    required this.max,
  });
  final String id;
  final String name;
  final int players;
  final int max;

  factory RoomInfo.fromJson(Map<String, dynamic> j) => RoomInfo(
    id: j['id'] as String? ?? '',
    name: j['name'] as String? ?? '',
    players: (j['players'] as num?)?.toInt() ?? 0,
    max: (j['max'] as num?)?.toInt() ?? 4,
  );
}

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
    Set<String>? selected,
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
      roundResult: roundResult ?? this.roundResult,
      matchResult: matchResult ?? this.matchResult,
      selected: selected ?? this.selected,
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
