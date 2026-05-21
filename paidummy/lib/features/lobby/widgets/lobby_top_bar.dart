/// Top bar of the lobby: avatar + identity column, wallet, quick actions.
library;

import 'package:flutter/material.dart';

import '../../../core/models/index.dart';
import 'daily_bonus_button.dart';
import 'missions_sheet.dart';
import 'ref_code_button.dart';
import 'wallet_pill.dart';

class LobbyTopBar extends StatelessWidget {
  const LobbyTopBar({
    super.key,
    required this.name,
    required this.rank,
    required this.coins,
    required this.walletLoading,
    required this.onWalletTap,
    required this.onHistory,
    required this.onShop,
    required this.onLeaderboard,
    required this.onSignOut,
  });
  final String name;
  final Rank? rank;
  final int coins;
  final bool walletLoading;
  final VoidCallback onWalletTap;
  final VoidCallback onHistory;
  final VoidCallback onShop;
  final VoidCallback onLeaderboard;
  final VoidCallback onSignOut;

  @override
  Widget build(BuildContext context) {
    final initial = name.isEmpty ? '?' : name.characters.first.toUpperCase();
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 8, 8),
      child: Row(
        children: [
          // Avatar circle — same gold palette as the in-game self seat.
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFFFFE7A6), Color(0xFFC89A48)],
              ),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.45),
                width: 2,
              ),
            ),
            alignment: Alignment.center,
            child: Text(
              initial,
              style: const TextStyle(
                color: Color(0xFF3D2900),
                fontSize: 20,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    shadows: [
                      Shadow(color: Colors.black54, blurRadius: 4),
                    ],
                  ),
                ),
                if (rank != null) RankPill(rank: rank!),
                const SizedBox(height: 2),
                const RefCodeButton(),
              ],
            ),
          ),
          WalletPill(
            coins: coins,
            loading: walletLoading,
            onRefresh: onWalletTap,
          ),
          const SizedBox(width: 2),
          const DailyBonusButton(),
          LobbyIconButton(
            emoji: '📋',
            tooltip: 'ภารกิจ',
            onTap: () => showMissionsSheet(context),
          ),
          LobbyIconButton(
            emoji: '📜',
            tooltip: 'ประวัติ',
            onTap: onHistory,
          ),
          LobbyIconButton(
            emoji: '🏆',
            tooltip: 'อันดับ',
            onTap: onLeaderboard,
          ),
          LobbyIconButton(
            emoji: '🛒',
            tooltip: 'ร้านค้า',
            onTap: onShop,
          ),
          IconButton(
            onPressed: onSignOut,
            icon: const Icon(Icons.logout, color: Colors.white70, size: 20),
            tooltip: 'ออก',
          ),
        ],
      ),
    );
  }
}

class LobbyIconButton extends StatelessWidget {
  const LobbyIconButton({
    super.key,
    required this.emoji,
    required this.tooltip,
    required this.onTap,
  });
  final String emoji;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.black.withValues(alpha: 0.3),
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox(
            width: 38,
            height: 38,
            child: Center(child: Text(emoji, style: const TextStyle(fontSize: 18))),
          ),
        ),
      ),
    );
  }
}

/// Section header for the tier list — gold accent bar + Thai+English labels.
class LobbySectionHeader extends StatelessWidget {
  const LobbySectionHeader({super.key});
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 4,
            height: 28,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xFFFFD24A), Color(0xFFC89A48)],
              ),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: const [
                Text(
                  'เลือกห้องเดิมพัน',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 19,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                SizedBox(height: 1),
                Text(
                  'ระบบจะหาห้องว่างที่ใกล้ที่สุดให้อัตโนมัติ',
                  style: TextStyle(
                    color: Colors.white60,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
