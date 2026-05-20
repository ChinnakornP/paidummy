/// Live wallet pill (🪙 + balance + tap to refresh) and the compact rank
/// chip shown next to the player name.
library;

import 'package:flutter/material.dart';

import '../../../core/models/index.dart';

/// Live wallet pill: 🪙 + current coin balance + tap to refresh.
class WalletPill extends StatelessWidget {
  const WalletPill({
    super.key,
    required this.coins,
    required this.loading,
    required this.onRefresh,
  });
  final int coins;
  final bool loading;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withValues(alpha: 0.35),
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onRefresh,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('🪙 ', style: TextStyle(fontSize: 18)),
              Text(
                '$coins',
                style: const TextStyle(
                  color: Color(0xFFFFD24A),
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              if (loading)
                const Padding(
                  padding: EdgeInsets.only(left: 8),
                  child: SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Color(0xFFFFD24A),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Compact rank chip — gold gradient with ⭐ pips matching level + title.
class RankPill extends StatelessWidget {
  const RankPill({super.key, required this.rank});
  final Rank rank;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFFFFE9A3), Color(0xFFC89D3A)],
          ),
          borderRadius: BorderRadius.circular(12),
          boxShadow: const [
            BoxShadow(
              color: Colors.black45,
              blurRadius: 4,
              offset: Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              List.filled(rank.level + 1, '★').join(),
              style: const TextStyle(color: Color(0xFF5A3A06), fontSize: 11),
            ),
            const SizedBox(width: 4),
            Text(
              rank.title,
              style: const TextStyle(
                color: Color(0xFF3D2900),
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            ),
            if (rank.nextTitle != null && rank.nextWins != null) ...[
              const SizedBox(width: 6),
              // Hint is the longest part of the pill and the column it sits
              // in can be narrow on landscape phones — Flexible + ellipsis
              // lets it shrink instead of overflowing the row.
              Flexible(
                child: Text(
                  '(${rank.nextWins! - rank.wins} ครั้งสู่ ${rank.nextTitle})',
                  overflow: TextOverflow.ellipsis,
                  softWrap: false,
                  style: const TextStyle(
                    color: Color(0xFF5A3A06),
                    fontSize: 10,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
