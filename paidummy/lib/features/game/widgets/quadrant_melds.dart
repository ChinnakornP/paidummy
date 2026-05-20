/// Four spatial regions of the felt — one per player. Each quadrant holds
/// only the melds owned by its assigned player so the board reads as
/// "AAA 234 567 / KKK AKQJ10" per corner instead of a single mixed column.
library;

import 'package:flutter/material.dart';

import '../../../core/models/index.dart';

enum MeldQuadrant {
  a, // top-left      — first opponent (lowest non-self seat)
  b, // top-right     — second opponent, grows from screen-centre going right
  c, // bottom-left   — self (always)
  d, // bottom-right  — third opponent, grows from screen-centre going right
}

/// Maps a meld's `owner` seat index to its quadrant. Self is always C;
/// opponents are sorted ascending by absolute seat index and fill A → B → D.
/// Returns null if the owner isn't in `view.players` (e.g. stale event).
MeldQuadrant? quadrantFor(int owner, GameView view) {
  if (owner == view.yourSeat) return MeldQuadrant.c;
  final opps = [
    for (final p in view.players)
      if (p.seat != view.yourSeat) p.seat,
  ]..sort();
  final idx = opps.indexOf(owner);
  if (idx < 0) return null;
  if (idx == 0) return MeldQuadrant.a;
  if (idx == 1) return MeldQuadrant.b;
  return MeldQuadrant.d;
}

/// Lays out the four quadrant meld panels over the felt. Sits inside the
/// game-screen Stack as a `Positioned.fill` child so it occupies the same
/// box as the seat/centre-pile layer; each quadrant is then a `Positioned`
/// inside this layer's internal Stack.
class QuadrantMeldsLayer extends StatelessWidget {
  const QuadrantMeldsLayer({
    super.key,
    required this.view,
    required this.selectedId,
    required this.onTap,
  });
  final GameView view;
  final String? selectedId;
  final void Function(String meldId) onTap;

  // Vertical buffers that keep meld panels clear of the seat cards (top
  // ~70px) and the hand-and-controls strip (bottom ~140px).
  static const double _topInset = 78;
  static const double _bottomInset = 140;
  static const double _sideInset = 8;

  @override
  Widget build(BuildContext context) {
    // Group melds by quadrant in one pass.
    final byQuad = <MeldQuadrant, List<MeldView>>{};
    for (final m in view.melds) {
      final q = quadrantFor(m.owner, view);
      if (q == null) continue;
      byQuad.putIfAbsent(q, () => <MeldView>[]).add(m);
    }
    if (byQuad.isEmpty) return const SizedBox.shrink();

    return LayoutBuilder(
      builder: (ctx, c) {
        // Each quadrant takes ~46% of the screen width so A/B and C/D have
        // breathing room around the centre pile.
        final halfW = c.maxWidth * 0.46;

        Widget panel({
          required MeldQuadrant q,
          required double? left,
          required double? right,
          required double? top,
          required double? bottom,
        }) {
          final melds = byQuad[q];
          if (melds == null || melds.isEmpty) return const SizedBox.shrink();
          return Positioned(
            left: left,
            right: right,
            top: top,
            bottom: bottom,
            width: halfW,
            child: _QuadrantMelds(
              melds: melds,
              selectedId: selectedId,
              onTap: onTap,
            ),
          );
        }

        return Stack(
          children: [
            panel(
              q: MeldQuadrant.a,
              left: _sideInset,
              right: null,
              top: _topInset,
              bottom: null,
            ),
            panel(
              q: MeldQuadrant.b,
              left: null,
              right: _sideInset,
              top: _topInset,
              bottom: null,
            ),
            panel(
              q: MeldQuadrant.c,
              left: _sideInset,
              right: null,
              top: null,
              bottom: _bottomInset,
            ),
            panel(
              q: MeldQuadrant.d,
              left: null,
              right: _sideInset,
              top: null,
              bottom: _bottomInset,
            ),
          ],
        );
      },
    );
  }
}

/// A single quadrant's meld stack. Wraps the owner's melds in a left-aligned
/// `Wrap` so cards flow left→right and wrap down — exactly what the user's
/// "ลงซ้ายไปขวา แล้วค่อยลงล่าง" rule asks for.
class _QuadrantMelds extends StatelessWidget {
  const _QuadrantMelds({
    required this.melds,
    required this.selectedId,
    required this.onTap,
  });
  final List<MeldView> melds;
  final String? selectedId;
  final void Function(String meldId) onTap;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 6,
      alignment: WrapAlignment.start,
      crossAxisAlignment: WrapCrossAlignment.start,
      children: [
        for (final m in melds)
          _MeldRow(
            meld: m,
            selected: m.id == selectedId,
            onTap: () => onTap(m.id),
          ),
      ],
    );
  }
}

class _MeldRow extends StatelessWidget {
  const _MeldRow({
    required this.meld,
    required this.selected,
    required this.onTap,
  });
  final MeldView meld;
  final bool selected;
  final VoidCallback onTap;

  static const _cardW = 36.0;
  static const _cardH = 50.0;
  static const _overlap = 16.0;

  @override
  Widget build(BuildContext context) {
    final n = meld.cards.length;
    final width = n == 0 ? 0.0 : _cardW + (n - 1) * _overlap;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: selected ? 0.45 : 0.25),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: selected
                  ? const Color(0xFFFFD24A)
                  : Colors.white.withValues(alpha: 0.15),
              width: selected ? 2.5 : 1,
            ),
            boxShadow: selected
                ? const [BoxShadow(color: Color(0x99FFD24A), blurRadius: 14)]
                : null,
          ),
          child: SizedBox(
            width: width,
            height: _cardH,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                for (var i = 0; i < meld.cards.length; i++)
                  Positioned(
                    left: i * _overlap,
                    child: _MiniCard(label: meld.cards[i]),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MiniCard extends StatelessWidget {
  const _MiniCard({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    if (label.length < 2) return const SizedBox(width: 36, height: 50);
    final rank = label[0] == 'T' ? '10' : label[0];
    final suit = label[1];
    final isRed = suit == 'H' || suit == 'D';
    final color = isRed ? const Color(0xFFD63333) : const Color(0xFF1A1A1A);
    final suitGlyph = switch (suit) {
      'H' => '♥',
      'D' => '♦',
      'S' => '♠',
      _ => '♣',
    };
    return Container(
      width: 36,
      height: 50,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: const Color(0xFFCCCCCC)),
        boxShadow: const [
          BoxShadow(color: Colors.black45, blurRadius: 3, offset: Offset(0, 2)),
        ],
      ),
      padding: const EdgeInsets.all(3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            rank,
            style: TextStyle(
              color: color,
              fontSize: 13,
              fontWeight: FontWeight.bold,
              fontFamily: 'Georgia',
              height: 1,
            ),
          ),
          Text(
            suitGlyph,
            style: TextStyle(
              color: color,
              fontSize: 16,
              fontFamily: 'Georgia',
              height: 1,
            ),
          ),
        ],
      ),
    );
  }
}
