/// Tap-a-seat profile dialog. For opponents it surfaces only what the
/// server's `PlayerPublic` already exposes (name + connection + chip stack
/// + hand count). For the local player it additionally pulls rank + lifetime
/// stats from `meProvider` so this also doubles as the "my profile" screen.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/index.dart';
import '../../../core/providers/index.dart';

/// Opens the profile dialog for [player]. [isSelf] makes the dialog pull
/// rank + stats from `meProvider`.
Future<void> showProfileDialog(
  BuildContext context, {
  required PlayerPublic player,
  required bool isSelf,
}) {
  return showDialog<void>(
    context: context,
    builder: (_) => ProfileDialog(player: player, isSelf: isSelf),
  );
}

class ProfileDialog extends ConsumerWidget {
  const ProfileDialog({
    super.key,
    required this.player,
    required this.isSelf,
  });
  final PlayerPublic player;
  final bool isSelf;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final initial = player.name.isEmpty
        ? '?'
        : player.name.characters.first.toUpperCase();
    final me = isSelf ? ref.watch(meProvider).value : null;
    return AlertDialog(
      backgroundColor: const Color(0xFF0F2E22),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFFFFE7A6), Color(0xFFC89A48)],
              ),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.4),
                width: 2,
              ),
            ),
            alignment: Alignment.center,
            child: Text(
              initial,
              style: const TextStyle(
                color: Color(0xFF3D2900),
                fontSize: 22,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  player.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  player.connected ? 'ออนไลน์' : 'ตัดการเชื่อมต่อ',
                  style: TextStyle(
                    color: player.connected
                        ? const Color(0xFF7FE08A)
                        : const Color(0xFFFF8A8A),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 320),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _row('🪙  เหรียญในมือ', '${player.coins}'),
            _row('🂠  ไพ่ในมือ', '${player.handCount} ใบ'),
            if (isSelf && me?.rank != null) ...[
              const SizedBox(height: 6),
              _row('🏅  ยศ',
                  '${List.filled(me!.rank!.level + 1, '★').join()} ${me.rank!.title}'),
              if (me.rank!.nextTitle != null && me.rank!.nextWins != null)
                Padding(
                  padding: const EdgeInsets.only(left: 10, top: 2),
                  child: Text(
                    'อีก ${me.rank!.nextWins! - me.rank!.wins} ครั้งสู่ ${me.rank!.nextTitle}',
                    style: const TextStyle(color: Colors.white60, fontSize: 11),
                  ),
                ),
            ],
            if (isSelf && me?.stats != null) ...[
              const Divider(color: Colors.white24, height: 22),
              _row('เล่นทั้งหมด', '${me!.stats!.matchesPlayed} ครั้ง'),
              _row('ชนะ', '${me.stats!.matchesWon} ครั้ง'),
              _row('กำไร/ขาดทุนสะสม', '${me.stats!.lifetimeProfit} 🪙',
                  positive: me.stats!.lifetimeProfit >= 0),
            ],
            if (!isSelf) ...[
              const SizedBox(height: 8),
              const Text(
                'สถิติเต็มของผู้เล่นคนอื่นจะมาในอัพเดตหน้า',
                style: TextStyle(color: Colors.white38, fontSize: 11),
              ),
            ],
          ],
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

  Widget _row(String label, String value, {bool positive = true}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(color: Colors.white70, fontSize: 13),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              color: positive
                  ? const Color(0xFFFFD24A)
                  : const Color(0xFFFF8A8A),
              fontSize: 14,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}
