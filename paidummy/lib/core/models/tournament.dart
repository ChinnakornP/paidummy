/// A scheduled tournament event. `live` means it's currently joinable; the
/// client enters via quickplay at [bet] when live.
library;

class Tournament {
  const Tournament({
    required this.name,
    required this.bet,
    required this.startMs,
    required this.live,
  });
  final String name;
  final int bet;
  final int startMs;
  final bool live;

  DateTime get startsAt => DateTime.fromMillisecondsSinceEpoch(startMs);

  factory Tournament.fromJson(Map<String, dynamic> j) => Tournament(
    name: j['name'] as String? ?? '',
    bet: (j['bet'] as num?)?.toInt() ?? 0,
    startMs: (j['start_ms'] as num?)?.toInt() ?? 0,
    live: j['live'] as bool? ?? false,
  );
}
