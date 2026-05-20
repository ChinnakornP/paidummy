/// Guest session + rank + stats + coin history. Hand-rolled JSON.
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

/// Server-side daily login bonus state. `claimable` flips to false once
/// the player claims, and back to true the next Asia/Bangkok calendar day.
class DailyBonus {
  const DailyBonus({
    required this.claimable,
    required this.streak,
    required this.nextReward,
    this.lastClaimAt,
    this.nextClaimAt,
  });
  final bool claimable;
  final int streak;
  final int nextReward;
  final DateTime? lastClaimAt;
  final DateTime? nextClaimAt;

  factory DailyBonus.fromJson(Map<String, dynamic> j) => DailyBonus(
    claimable: j['claimable'] as bool? ?? false,
    streak: (j['streak'] as num?)?.toInt() ?? 0,
    nextReward: (j['next_reward'] as num?)?.toInt() ?? 0,
    lastClaimAt: j['last_claim_at'] is String
        ? DateTime.tryParse(j['last_claim_at'] as String)
        : null,
    nextClaimAt: j['next_claim_at'] is String
        ? DateTime.tryParse(j['next_claim_at'] as String)
        : null,
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
