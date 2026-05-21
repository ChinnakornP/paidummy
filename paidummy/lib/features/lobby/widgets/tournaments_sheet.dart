/// Tournaments bottom sheet — upcoming scheduled high-stakes events with a
/// countdown. A live event is joinable now; tapping Join enters via the
/// normal quickplay flow at the event's stake.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/index.dart';
import '../../../core/network/index.dart';
import '../../../core/providers/index.dart';

Future<void> showTournamentsSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: const Color(0xFF12313B),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => const TournamentsSheet(),
  );
}

class TournamentsSheet extends ConsumerWidget {
  const TournamentsSheet({super.key});

  String _countdown(DateTime start) {
    final d = start.difference(DateTime.now());
    if (d.isNegative) return 'กำลังแข่ง';
    if (d.inHours >= 1) return 'อีก ${d.inHours} ชม. ${d.inMinutes % 60} นาที';
    return 'อีก ${d.inMinutes} นาที';
  }

  Future<void> _join(BuildContext context, WidgetRef ref, Tournament t) async {
    final g = ref.read(sessionProvider);
    if (g == null) return;
    try {
      final roomId = await ref.read(apiClientProvider).quickplay(g.token, t.bet);
      ref.read(currentRoomProvider.notifier).state = roomId;
      if (!context.mounted) return;
      Navigator.of(context).pop();
    } on QuickplayException catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message)),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final events = ref.watch(tournamentsProvider);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(14),
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
            const Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '🏟  ทัวร์นาเมนต์',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(height: 10),
            Flexible(
              child: events.when(
                loading: () => const Padding(
                  padding: EdgeInsets.all(24),
                  child: CircularProgressIndicator(),
                ),
                error: (e, _) => Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text('โหลดทัวร์นาเมนต์ไม่ได้: $e',
                      style: const TextStyle(color: Colors.white70)),
                ),
                data: (list) => list.isEmpty
                    ? const Padding(
                        padding: EdgeInsets.all(16),
                        child: Text('ยังไม่มีอีเวนต์เร็ว ๆ นี้',
                            style: TextStyle(color: Colors.white60)),
                      )
                    : ListView.separated(
                        shrinkWrap: true,
                        itemCount: list.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 8),
                        itemBuilder: (_, i) {
                          final t = list[i];
                          return Container(
                            padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.05),
                              borderRadius: BorderRadius.circular(12),
                              border: t.live
                                  ? Border.all(
                                      color: const Color(0xFFFFD24A), width: 1.5)
                                  : null,
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(t.name,
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 15,
                                            fontWeight: FontWeight.w600,
                                          )),
                                      const SizedBox(height: 3),
                                      Text(
                                        'เดิมพัน ${t.bet} 🪙  ·  ${t.live ? "🔴 LIVE" : _countdown(t.startsAt)}',
                                        style: const TextStyle(
                                            color: Colors.white60,
                                            fontSize: 12),
                                      ),
                                    ],
                                  ),
                                ),
                                FilledButton(
                                  onPressed:
                                      t.live ? () => _join(context, ref, t) : null,
                                  style: FilledButton.styleFrom(
                                    backgroundColor: const Color(0xFFFFD24A),
                                    foregroundColor: const Color(0xFF1A1A1A),
                                  ),
                                  child: Text(t.live ? 'เข้าร่วม' : 'เร็ว ๆ นี้'),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
