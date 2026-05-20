/// Gift-icon CTA in the lobby top bar. When today's bonus is claimable it
/// pulses and shows a small "+N🪙" hint; once claimed it dims and labels
/// itself with the streak.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/index.dart';

class DailyBonusButton extends ConsumerWidget {
  const DailyBonusButton({super.key});

  Future<void> _claim(BuildContext context, WidgetRef ref) async {
    final g = ref.read(sessionProvider);
    if (g == null) return;
    HapticFeedback.lightImpact();
    try {
      final r = await ref.read(apiClientProvider).claimDaily(g.token);
      ref.invalidate(meProvider);
      ref.invalidate(dailyBonusProvider);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: const Color(0xFF3E8A25),
          content: Text(
            '🎁  +${r.coinsAdded} 🪙   ·   streak ${r.streak} วัน',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('รับโบนัสไม่สำเร็จ: $e')));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final daily = ref.watch(dailyBonusProvider).value;
    final claimable = daily?.claimable ?? false;
    final tooltip = daily == null
        ? 'โบนัสรายวัน'
        : claimable
            ? 'รับโบนัสรายวัน (+${daily.nextReward} 🪙, streak ${daily.streak} วัน)'
            : 'มาใหม่พรุ่งนี้  ·  streak ${daily.streak} วัน';

    return Tooltip(
      message: tooltip,
      child: Material(
        color: claimable
            ? const Color(0xFFFFD24A).withValues(alpha: 0.18)
            : Colors.black.withValues(alpha: 0.3),
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: claimable ? () => _claim(context, ref) : null,
          child: SizedBox(
            width: 38,
            height: 38,
            child: Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.center,
              children: [
                Opacity(
                  opacity: claimable ? 1 : 0.6,
                  child: const Text('🎁', style: TextStyle(fontSize: 20)),
                ),
                if (claimable)
                  Positioned(
                    right: -2,
                    top: -2,
                    child: Container(
                      width: 10,
                      height: 10,
                      decoration: const BoxDecoration(
                        color: Color(0xFFD63333),
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
