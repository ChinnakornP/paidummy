/// Player-card panel: avatar, name, coin pill, hand-count badge, ready pip
/// and turn glow. Used for both opponents (color palettes from kSeatPalettes)
/// and self (warm gold palette).
library;

import 'package:flutter/material.dart';

import '../../../core/models/index.dart';

class SeatPalette {
  const SeatPalette(this.bg, this.avatar);
  final List<Color> bg;
  final List<Color> avatar;
}

/// Seat-card colour scheme (matches `.player-card` / `.avatar` variants in
/// game_design_v1.html). Slot index decides which palette is used.
const kSeatPalettes = [
  // p1: blue
  SeatPalette(
    [Color(0xFF2D6E9E), Color(0xFF1E4D70)],
    [Color(0xFF7A8A9A), Color(0xFF4A5560)],
  ),
  // p2: green
  SeatPalette(
    [Color(0xFF2D8A6E), Color(0xFF1E6E54)],
    [Color(0xFFD4A878), Color(0xFF8A6848)],
  ),
  // p3: yellow / olive
  SeatPalette(
    [Color(0xFF8A8048), Color(0xFF6E6332)],
    [Color(0xFF2A2A2A), Color(0xFF1A1A1A)],
  ),
  // p4: dark / maroon
  SeatPalette(
    [Color(0xFF5A4040), Color(0xFF3A2828)],
    [Color(0xFF6A8A4A), Color(0xFF2A4A1A)],
  ),
];

/// Self seat uses a warm gold palette so the local player can pick their own
/// card out of the line-up at a glance, distinct from any opponent colour.
const kSelfSeatPalette = SeatPalette(
  [Color(0xFFC8923A), Color(0xFF8E6420)],
  [Color(0xFFFFE7A6), Color(0xFFC89A48)],
);

/// Circular avatar with hand-count badge, score pill and turn glow.
class Seat extends StatelessWidget {
  const Seat({
    super.key,
    required this.player,
    required this.active,
    required this.palette,
  });
  final PlayerPublic player;
  final bool active;
  final SeatPalette palette;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 110,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            margin: const EdgeInsets.only(top: 6),
            padding: const EdgeInsets.fromLTRB(6, 10, 6, 8),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: palette.bg,
              ),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: active
                    ? const Color(0xFFFFD24A)
                    : Colors.black.withValues(alpha: 0.2),
                width: active ? 2.5 : 1,
              ),
              boxShadow: [
                const BoxShadow(
                  color: Colors.black54,
                  blurRadius: 10,
                  offset: Offset(0, 4),
                ),
                if (active)
                  const BoxShadow(
                    color: Color(0x99FFD24A),
                    blurRadius: 16,
                    spreadRadius: 1,
                  ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Avatar
                Container(
                  width: 70,
                  height: 70,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: palette.avatar,
                    ),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.6),
                      width: 3,
                    ),
                  ),
                  child: Icon(
                    player.connected ? Icons.person : Icons.person_off,
                    color: Colors.white70,
                    size: 36,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  player.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    shadows: [
                      Shadow(
                        color: Colors.black54,
                        offset: Offset(1, 1),
                        blurRadius: 2,
                      ),
                    ],
                  ),
                ),
                Container(
                  margin: const EdgeInsets.only(top: 4),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.35),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '🪙 ${player.coins}',
                    style: const TextStyle(
                      color: Color(0xFFFFD24A),
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Bottom-right rectangular badge with the card count.
          Positioned(
            right: 0,
            bottom: 56,
            child: Container(
              width: 22,
              height: 28,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(3),
                boxShadow: const [
                  BoxShadow(
                    color: Colors.black45,
                    blurRadius: 4,
                    offset: Offset(0, 2),
                  ),
                ],
              ),
              child: Text(
                '${player.handCount}',
                style: const TextStyle(
                  color: Color(0xFFD63333),
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          // Ready pip (small green tick) on the top-left.
          if (player.ready && !active)
            const Positioned(
              left: 4,
              top: 0,
              child: Icon(
                Icons.check_circle,
                color: Color(0xFF7FE08A),
                size: 16,
              ),
            ),
        ],
      ),
    );
  }
}
