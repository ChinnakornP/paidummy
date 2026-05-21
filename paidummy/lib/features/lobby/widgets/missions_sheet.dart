/// Daily-missions bottom sheet. Each row shows a progress bar and a claim
/// button that lights up when the goal is met.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/index.dart';
import '../../../core/providers/index.dart';

Future<void> showMissionsSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: const Color(0xFF12313B),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => const MissionsSheet(),
  );
}

class MissionsSheet extends ConsumerWidget {
  const MissionsSheet({super.key});

  Future<void> _claim(
    BuildContext context,
    WidgetRef ref,
    MissionStatus m,
  ) async {
    final g = ref.read(sessionProvider);
    if (g == null) return;
    HapticFeedback.lightImpact();
    try {
      final r = await ref.read(apiClientProvider).claimMission(g.token, m.id);
      ref.invalidate(meProvider);
      ref.invalidate(missionsProvider);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: const Color(0xFF3E8A25),
          content: Text('รับรางวัล +${r.reward} 🪙'),
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('รับรางวัลไม่ได้: $e')));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final missions = ref.watch(missionsProvider);
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
              padding: EdgeInsets.fromLTRB(8, 0, 8, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '📋  ภารกิจวันนี้',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
            Flexible(
              child: missions.when(
                loading: () => const Padding(
                  padding: EdgeInsets.all(24),
                  child: CircularProgressIndicator(),
                ),
                error: (e, _) => Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    'โหลดภารกิจไม่ได้: $e',
                    style: const TextStyle(color: Colors.white70),
                  ),
                ),
                data: (list) => ListView.separated(
                  shrinkWrap: true,
                  padding: const EdgeInsets.all(4),
                  itemCount: list.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (_, i) => _MissionRow(
                    mission: list[i],
                    onClaim: () => _claim(context, ref, list[i]),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MissionRow extends StatelessWidget {
  const _MissionRow({required this.mission, required this.onClaim});
  final MissionStatus mission;
  final VoidCallback onClaim;

  @override
  Widget build(BuildContext context) {
    final pct =
        mission.goal == 0 ? 0.0 : (mission.progress / mission.goal).clamp(0, 1);
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  mission.title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: pct.toDouble(),
                    minHeight: 6,
                    backgroundColor: Colors.black.withValues(alpha: 0.3),
                    valueColor: const AlwaysStoppedAnimation(
                      Color(0xFF6DC94A),
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${mission.progress}/${mission.goal}  ·  +${mission.reward} 🪙',
                  style: const TextStyle(color: Colors.white60, fontSize: 11),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          _claimButton(),
        ],
      ),
    );
  }

  Widget _claimButton() {
    if (mission.claimed) {
      return const Padding(
        padding: EdgeInsets.symmetric(horizontal: 8),
        child: Text(
          'รับแล้ว',
          style: TextStyle(color: Colors.white38, fontSize: 12),
        ),
      );
    }
    final canClaim = mission.complete;
    return FilledButton(
      onPressed: canClaim ? onClaim : null,
      style: FilledButton.styleFrom(
        backgroundColor: const Color(0xFFFFD24A),
        foregroundColor: const Color(0xFF1A1A1A),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      ),
      child: const Text('รับรางวัล'),
    );
  }
}
