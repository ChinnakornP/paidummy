/// Bet-tier card — vertical/portrait. Sits in a horizontally scrolling row.
/// Top: tier label badge.  Middle: giant stake, "🪙 ต่อมือ", live player
/// count + room count.  Bottom: full-width "เข้าเล่น" CTA, or a padlock chip
/// if the wallet can't afford the stake.
library;

import 'package:flutter/material.dart';

import '../../../core/models/index.dart';

class TierCard extends StatelessWidget {
  const TierCard({
    super.key,
    required this.tier,
    required this.coins,
    required this.onEnter,
  });
  final TierInfo tier;
  final int coins;
  final VoidCallback onEnter;

  int get _bet => tier.bet;
  // Lock = wallet < stake (server also enforces; client just disables).
  bool get _canAfford => coins >= _bet;

  TierVisual get _v {
    final bet = _bet;
    if (bet <= 50) {
      return const TierVisual(
        label: 'ห้องมือใหม่',
        sub: 'เริ่มต้นง่ายๆ',
        bg: [Color(0xFF2D8A6E), Color(0xFF1E6E54)],
        accent: Color(0xFF8AE6B5),
        suit: '♣',
        suitColor: Color(0x331A1A1A),
      );
    }
    if (bet <= 100) {
      return const TierVisual(
        label: 'ห้องเริ่มต้น',
        sub: 'เดิมพันเบาๆ',
        bg: [Color(0xFF2D6E9E), Color(0xFF1E4D70)],
        accent: Color(0xFF7FCFFF),
        suit: '♦',
        suitColor: Color(0x33D63333),
      );
    }
    if (bet <= 500) {
      return const TierVisual(
        label: 'ห้องกลาง',
        sub: 'พอลุ้นได้',
        bg: [Color(0xFFB8804A), Color(0xFF8A5A2F)],
        accent: Color(0xFFFFE0A6),
        suit: '♠',
        suitColor: Color(0x331A1A1A),
      );
    }
    if (bet <= 1000) {
      return const TierVisual(
        label: 'ห้องไฮโรลเลอร์',
        sub: 'แต้มสูง ใจถึง',
        bg: [Color(0xFFA42B72), Color(0xFF6E1A4D)],
        accent: Color(0xFFFFB4DA),
        suit: '♥',
        suitColor: Color(0x33D63333),
      );
    }
    return const TierVisual(
      label: 'ห้อง VIP',
      sub: 'จัดเต็มทุกตา',
      bg: [Color(0xFFE8902E), Color(0xFFC0392B)],
      accent: Color(0xFFFFE0A6),
      suit: '♠',
      suitColor: Color(0x331A1A1A),
    );
  }

  @override
  Widget build(BuildContext context) {
    final v = _v;
    // Rough max pot ≈ stake × 4 (max table size); server payout is exact.
    final pot = _bet * 4;
    return SizedBox(
      width: 200, // portrait card; height fills the parent's Expanded.
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          onTap: _canAfford ? onEnter : null,
          borderRadius: BorderRadius.circular(20),
          child: Stack(
            children: [
              Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: v.bg,
                  ),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.18),
                    width: 1.4,
                  ),
                  boxShadow: const [
                    BoxShadow(
                      color: Colors.black54,
                      blurRadius: 14,
                      offset: Offset(0, 8),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(18),
                  child: Stack(
                    children: [
                      // Suit watermark — large, low-contrast, behind content.
                      Positioned(
                        right: -28,
                        bottom: -36,
                        child: IgnorePointer(
                          child: Text(
                            v.suit,
                            style: TextStyle(
                              color: v.suitColor,
                              fontSize: 200,
                              height: 1,
                              shadows: const [
                                Shadow(
                                  color: Colors.black38,
                                  blurRadius: 10,
                                  offset: Offset(0, 6),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      Padding(
                        padding:
                            const EdgeInsets.fromLTRB(12, 10, 12, 10),
                        // Compact portrait layout. Landscape phones can be
                        // as short as ~180 px in the tier-list row, so this
                        // column has to fit ≤ ~170 px of content. We
                        // collapse "ผู้เล่น/ห้อง" into one row and elide the
                        // italic sub line for screens where every pixel
                        // matters; Flexible+FittedBox absorbs slack.
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.max,
                          children: [
                            TierBadge(label: v.label, accent: v.accent),
                            const SizedBox(height: 6),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Flexible(
                                  child: FittedBox(
                                    fit: BoxFit.scaleDown,
                                    alignment: Alignment.bottomLeft,
                                    child: Text(
                                      '$_bet',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 38,
                                        fontWeight: FontWeight.w900,
                                        height: 1,
                                        letterSpacing: -1,
                                        shadows: [
                                          Shadow(
                                            color: Colors.black54,
                                            blurRadius: 5,
                                            offset: Offset(0, 2),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 4),
                                const Padding(
                                  padding: EdgeInsets.only(bottom: 4),
                                  child: Text(
                                    '🪙',
                                    style: TextStyle(fontSize: 15),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            // ผู้เล่น/ห้อง — headline live signal, on one
                            // row so the card stays short.
                            Row(
                              children: [
                                Icon(Icons.person,
                                    size: 14, color: v.accent),
                                const SizedBox(width: 4),
                                Text(
                                  '${tier.players} คน',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Icon(Icons.meeting_room_outlined,
                                    size: 14, color: v.accent),
                                const SizedBox(width: 4),
                                Text(
                                  '${tier.rooms} ห้อง',
                                  style: const TextStyle(
                                    color: Colors.white70,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                Icon(Icons.emoji_events_outlined,
                                    size: 13, color: v.accent),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: Text(
                                    'พูลสูงสุด ~$pot 🪙',
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: Colors.white70,
                                      fontSize: 11,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const Spacer(),
                            SizedBox(
                              width: double.infinity,
                              child: TierCta(canAfford: _canAfford),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (!_canAfford)
                Positioned.fill(
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.4),
                        borderRadius: BorderRadius.circular(20),
                      ),
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

class TierVisual {
  const TierVisual({
    required this.label,
    required this.sub,
    required this.bg,
    required this.accent,
    required this.suit,
    required this.suitColor,
  });
  final String label;
  final String sub;
  final List<Color> bg;
  final Color accent;
  final String suit;
  final Color suitColor;
}

class TierBadge extends StatelessWidget {
  const TierBadge({super.key, required this.label, required this.accent});
  final String label;
  final Color accent;
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: accent.withValues(alpha: 0.55)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: accent,
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }
}

class TierCta extends StatelessWidget {
  const TierCta({super.key, required this.canAfford});
  final bool canAfford;
  @override
  Widget build(BuildContext context) {
    if (!canAfford) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.45),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white24),
        ),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.lock, color: Colors.white70, size: 16),
            SizedBox(width: 4),
            Text(
              'เงินไม่พอ',
              style: TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      );
    }
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFFFD24A), Color(0xFFC8932A)],
        ),
        borderRadius: BorderRadius.circular(14),
        boxShadow: const [BoxShadow(color: Color(0x88FFD24A), blurRadius: 14)],
      ),
      child: const Padding(
        padding: EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'เข้าเล่น',
              style: TextStyle(
                color: Color(0xFF1A1A1A),
                fontSize: 14,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.4,
              ),
            ),
            SizedBox(width: 4),
            Icon(Icons.arrow_forward_rounded,
                color: Color(0xFF1A1A1A), size: 18),
          ],
        ),
      ),
    );
  }
}
