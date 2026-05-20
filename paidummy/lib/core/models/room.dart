/// Room + tier + per-room match history wire models.
library;

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

/// One row in the lobby's bet-tier menu. `players` is a live snapshot of
/// seats currently in open rooms at this stake; `rooms` is how many such
/// rooms are in the lobby phase right now.
class TierInfo {
  const TierInfo({
    required this.bet,
    required this.players,
    required this.rooms,
  });
  final int bet;
  final int players;
  final int rooms;

  factory TierInfo.fromJson(Map<String, dynamic> j) => TierInfo(
    bet: (j['bet'] as num?)?.toInt() ?? 0,
    players: (j['players'] as num?)?.toInt() ?? 0,
    rooms: (j['rooms'] as num?)?.toInt() ?? 0,
  );
}
