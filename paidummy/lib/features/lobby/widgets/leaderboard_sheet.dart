/// Modal leaderboard sheet — gold/silver/bronze top 3 plus a scrollable
/// list. The period segmented control switches between all-time, weekly,
/// and daily rankings (each is its own server query).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/index.dart';
import '../../../core/providers/index.dart';

Future<void> showLeaderboardSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: const Color(0xFF12313B),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => const LeaderboardSheet(),
  );
}

class LeaderboardSheet extends ConsumerStatefulWidget {
  const LeaderboardSheet({super.key});
  @override
  ConsumerState<LeaderboardSheet> createState() => _LeaderboardSheetState();
}

class _LeaderboardSheetState extends ConsumerState<LeaderboardSheet> {
  String _period = 'alltime';

  static const _periods = [
    ('alltime', 'ตลอดกาล'),
    ('weekly', 'สัปดาห์นี้'),
    ('daily', 'วันนี้'),
  ];

  @override
  Widget build(BuildContext context) {
    final rows = ref.watch(leaderboardProvider(_period));
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(8, 0, 8, 4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '🏆  ตารางอันดับ',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              child: SegmentedButton<String>(
                segments: [
                  for (final p in _periods)
                    ButtonSegment(value: p.$1, label: Text(p.$2)),
                ],
                selected: {_period},
                onSelectionChanged: (s) => setState(() => _period = s.first),
              ),
            ),
            Flexible(
              child: rows.when(
                loading: () => const Padding(
                  padding: EdgeInsets.all(24),
                  child: CircularProgressIndicator(),
                ),
                error: (e, _) => Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    'โหลดอันดับไม่ได้: $e',
                    style: const TextStyle(color: Colors.white70),
                  ),
                ),
                data: (list) {
                  if (list.isEmpty) {
                    return const Padding(
                      padding: EdgeInsets.all(24),
                      child: Text(
                        'ยังไม่มีอันดับในช่วงนี้',
                        style: TextStyle(color: Colors.white60),
                      ),
                    );
                  }
                  return ListView.separated(
                    shrinkWrap: true,
                    padding: const EdgeInsets.all(4),
                    itemCount: list.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 4),
                    itemBuilder: (_, i) =>
                        _LeaderboardRow(rank: i + 1, row: list[i]),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LeaderboardRow extends StatelessWidget {
  const _LeaderboardRow({required this.rank, required this.row});
  final int rank;
  final LeaderboardRow row;

  Color _rankColor() {
    if (rank == 1) return const Color(0xFFFFD24A); // gold
    if (rank == 2) return const Color(0xFFE0E0E0); // silver
    if (rank == 3) return const Color(0xFFCD7F32); // bronze
    return Colors.white24;
  }

  @override
  Widget build(BuildContext context) {
    final pos = row.profit >= 0;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(10),
        border: Border(
          left: BorderSide(color: _rankColor(), width: 4),
        ),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 32,
            child: Text(
              '#$rank',
              style: TextStyle(
                color: _rankColor(),
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  row.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  'ชนะ ${row.wins} ตา',
                  style: const TextStyle(color: Colors.white60, fontSize: 11),
                ),
              ],
            ),
          ),
          Text(
            '${pos ? '+' : ''}${row.profit} 🪙',
            style: TextStyle(
              color: pos
                  ? const Color(0xFF7FE08A)
                  : const Color(0xFFFF8A8A),
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
        ],
      ),
    );
  }
}
