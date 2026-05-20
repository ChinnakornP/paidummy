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
  });
  final String id;
  final String name;
  final String token;
  final int coins;

  factory Guest.fromJson(Map<String, dynamic> j) => Guest(
    id: j['id'] as String? ?? '',
    name: j['name'] as String? ?? '',
    token: j['token'] as String? ?? '',
    coins: (j['coins'] as num?)?.toInt() ?? 0,
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
    this.lastError,
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
  final String? lastError;
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
    String? lastError,
    bool clearError = false,
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
      lastError: clearError ? null : (lastError ?? this.lastError),
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
      selected: const {},
    );
  }
}
