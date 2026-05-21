/// Modal sheet listing the player's recent match outcomes with coin deltas
/// plus a small stats header (played / won / lifetime profit).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/index.dart';
import 'widgets/history_row.dart';
import 'widgets/replay_dialog.dart';
import 'widgets/stat_chip.dart';

/// Opens the history bottom sheet — my recent match outcomes.
Future<void> showHistorySheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: const Color(0xFF12313B),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => const HistorySheet(),
  );
}

class HistorySheet extends ConsumerWidget {
  const HistorySheet({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final history = ref.watch(coinHistoryProvider);
    final stats = ref.watch(meProvider).value?.stats;
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
                  '📜  ประวัติของฉัน',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
            if (stats != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                child: Row(
                  children: [
                    StatChip(label: 'เล่น', value: '${stats.matchesPlayed}'),
                    const SizedBox(width: 6),
                    StatChip(label: 'ชนะ', value: '${stats.matchesWon}'),
                    const SizedBox(width: 6),
                    StatChip(
                      label: 'กำไร',
                      value: '${stats.lifetimeProfit} 🪙',
                      positive: stats.lifetimeProfit >= 0,
                    ),
                  ],
                ),
              ),
            Flexible(
              child: history.when(
                loading: () => const Padding(
                  padding: EdgeInsets.all(24),
                  child: CircularProgressIndicator(),
                ),
                error: (e, _) => Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    'โหลดประวัติไม่ได้: $e',
                    style: const TextStyle(color: Colors.white70),
                  ),
                ),
                data: (list) {
                  if (list.isEmpty) {
                    return const Padding(
                      padding: EdgeInsets.all(24),
                      child: Text(
                        'ยังไม่มีประวัติ — ลองเล่นสักรอบก่อน',
                        style: TextStyle(color: Colors.white60),
                      ),
                    );
                  }
                  return ListView.separated(
                    shrinkWrap: true,
                    padding: const EdgeInsets.all(4),
                    itemCount: list.length,
                    separatorBuilder: (_, i) => const SizedBox(height: 6),
                    itemBuilder: (_, i) => HistoryRow(
                      row: list[i],
                      onTap: () => showReplayDialog(context, list[i].matchId),
                    ),
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
