/// A daily mission with the player's progress for today.
library;

class MissionStatus {
  const MissionStatus({
    required this.id,
    required this.title,
    required this.goal,
    required this.reward,
    required this.progress,
    required this.claimed,
    required this.complete,
  });
  final String id;
  final String title;
  final int goal;
  final int reward;
  final int progress;
  final bool claimed;
  final bool complete;

  factory MissionStatus.fromJson(Map<String, dynamic> j) => MissionStatus(
    id: j['id'] as String? ?? '',
    title: j['title'] as String? ?? '',
    goal: (j['goal'] as num?)?.toInt() ?? 0,
    reward: (j['reward'] as num?)?.toInt() ?? 0,
    progress: (j['progress'] as num?)?.toInt() ?? 0,
    claimed: j['claimed'] as bool? ?? false,
    complete: j['complete'] as bool? ?? false,
  );
}
