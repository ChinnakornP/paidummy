/// Round-by-round replay viewer for a finished match — opened by tapping a
/// row in the history sheet. Shows each round's end reason and per-player
/// scores. (Score-log replay; a full move scrubber can layer on later.)
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/index.dart';
import '../../../core/providers/index.dart';

Future<void> showReplayDialog(BuildContext context, String matchId) {
  return showDialog<void>(
    context: context,
    builder: (_) => _ReplayDialog(matchId: matchId),
  );
}

class _ReplayDialog extends ConsumerWidget {
  const _ReplayDialog({required this.matchId});
  final String matchId;

  String _reasonLabel(String r) => switch (r) {
        'knock' => 'น็อค',
        'deck_exhaust' => 'ไพ่กองหมด',
        _ => r.isEmpty ? 'จบรอบ' : r,
      };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final g = ref.watch(sessionProvider);
    return AlertDialog(
      backgroundColor: const Color(0xFF0F2E22),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      title: const Text('🎬  รีเพลย์การแข่ง'),
      content: SizedBox(
        width: 360,
        child: g == null
            ? const Text('ไม่มี session')
            : FutureBuilder<List<ReplayRound>>(
                future: ref.read(apiClientProvider).matchReplay(g.token, matchId),
                builder: (_, snap) {
                  if (snap.connectionState != ConnectionState.done) {
                    return const Padding(
                      padding: EdgeInsets.all(24),
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }
                  if (snap.hasError) {
                    return Text('โหลดรีเพลย์ไม่ได้: ${snap.error}',
                        style: const TextStyle(color: Colors.white70));
                  }
                  final rounds = snap.data ?? const [];
                  if (rounds.isEmpty) {
                    return const Text('ไม่มีข้อมูลรอบ',
                        style: TextStyle(color: Colors.white60));
                  }
                  return SizedBox(
                    height: 360,
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: rounds.length,
                      separatorBuilder: (_, _) =>
                          const Divider(color: Colors.white12, height: 14),
                      itemBuilder: (_, i) {
                        final r = rounds[i];
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'รอบ ${r.roundNo} · ${_reasonLabel(r.reason)}',
                              style: const TextStyle(
                                color: Color(0xFFFFE7A6),
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 4),
                            for (final s in r.scores)
                              Padding(
                                padding: const EdgeInsets.symmetric(vertical: 1),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        s.name,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                            color: Colors.white70, fontSize: 13),
                                      ),
                                    ),
                                    Text(
                                      '${s.score >= 0 ? '+' : ''}${s.score}',
                                      style: TextStyle(
                                        color: s.score >= 0
                                            ? const Color(0xFF7FE08A)
                                            : const Color(0xFFFF8A8A),
                                        fontWeight: FontWeight.bold,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        );
                      },
                    ),
                  );
                },
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('ปิด'),
        ),
      ],
    );
  }
}
