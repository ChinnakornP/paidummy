/// Round-by-round score log for a finished match (lightweight replay).
library;

class ReplayScore {
  const ReplayScore({required this.name, required this.score});
  final String name;
  final int score;

  factory ReplayScore.fromJson(Map<String, dynamic> j) => ReplayScore(
    name: j['name'] as String? ?? '',
    score: (j['score'] as num?)?.toInt() ?? 0,
  );
}

class ReplayRound {
  const ReplayRound({
    required this.roundNo,
    required this.reason,
    required this.scores,
  });
  final int roundNo;
  final String reason;
  final List<ReplayScore> scores;

  factory ReplayRound.fromJson(Map<String, dynamic> j) => ReplayRound(
    roundNo: (j['round_no'] as num?)?.toInt() ?? 0,
    reason: j['reason'] as String? ?? '',
    scores: ((j['scores'] as List?) ?? const [])
        .map((e) => ReplayScore.fromJson(e as Map<String, dynamic>))
        .toList(),
  );
}
