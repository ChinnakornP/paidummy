/// Overlapping fan of the player's own hand with drag-to-reorder.
///
/// Each card is wrapped in a GestureDetector keyed by the card code so its
/// element survives reorder rebuilds. A short tap toggles selection; a
/// horizontal drag past the gesture-arena threshold is treated as a reorder —
/// the card follows the pointer and swaps with neighbours in real time as
/// the accumulated offset crosses card-overlap boundaries.
library;

import 'package:flutter/material.dart';

class HandFan extends StatefulWidget {
  const HandFan({
    super.key,
    required this.hand,
    required this.selected,
    required this.onToggle,
    required this.onMove,
  });

  final List<String> hand;
  final Set<String> selected;
  final void Function(String card) onToggle;
  final void Function(int from, int to) onMove;

  @override
  State<HandFan> createState() => _HandFanState();
}

class _HandFanState extends State<HandFan> {
  // Sizes match game_design_v1.html `.hand .card` (75×105, overlap -35).
  static const _cardW = 75.0;
  static const _overlap = 40.0;
  static const _liftHeight = 18.0;

  String? _dragCard;
  double _dragDx = 0;

  @override
  Widget build(BuildContext context) {
    final n = widget.hand.length;
    final fanWidth = n == 0 ? 0.0 : _cardW + (n - 1) * _overlap;

    return SizedBox(
      height: 130,
      width: fanWidth + 24,
      child: Stack(
        alignment: Alignment.bottomLeft,
        clipBehavior: Clip.none,
        children: [for (var i = 0; i < n; i++) _buildCard(i, widget.hand[i])],
      ),
    );
  }

  Widget _buildCard(int i, String card) {
    final isDragging = _dragCard == card;
    final selected = widget.selected.contains(card);
    final left = i * _overlap + (isDragging ? _dragDx : 0);
    final bottom = selected ? 18.0 : (isDragging ? _liftHeight : 0.0);

    return AnimatedPositioned(
      key: ValueKey(card),
      duration: isDragging
          ? Duration
                .zero // follow the pointer 1:1 while dragging
          : const Duration(milliseconds: 140),
      curve: Curves.easeOut,
      left: left,
      bottom: bottom,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => widget.onToggle(card),
        onHorizontalDragStart: (_) {
          setState(() {
            _dragCard = card;
            _dragDx = 0;
          });
        },
        onHorizontalDragUpdate: (d) {
          if (_dragCard == null) return;
          final cur = widget.hand.indexOf(_dragCard!);
          if (cur < 0) {
            setState(() => _dragCard = null);
            return;
          }
          setState(() => _dragDx += d.delta.dx);
          // Each time the accumulated drag crosses a half-overlap step,
          // commit one swap in that direction and rebase _dragDx so the
          // card now sits centred on its new slot.
          final steps = (_dragDx / _overlap).round();
          if (steps != 0) {
            final target = (cur + steps).clamp(0, widget.hand.length - 1);
            if (target != cur) {
              widget.onMove(cur, target);
              setState(() => _dragDx -= (target - cur) * _overlap);
            }
          }
        },
        onHorizontalDragEnd: (_) {
          setState(() {
            _dragCard = null;
            _dragDx = 0;
          });
        },
        onHorizontalDragCancel: () {
          setState(() {
            _dragCard = null;
            _dragDx = 0;
          });
        },
        child: Material(
          color: Colors.transparent,
          elevation: isDragging ? 8 : 0,
          shadowColor: Colors.black54,
          child: _Card(label: card, selected: selected),
        ),
      ),
    );
  }
}

/// Player-hand card, sized + laid out like the `.hand .card` rule in
/// game_design_v1.html: 75×105 white card, rounded 5, 1px grey border, rank
/// top-left small, suit below larger, Georgia-leaning serif. Selected/raised
/// cards get the cream `#fff8d8` highlight with a golden glow.
class _Card extends StatelessWidget {
  const _Card({required this.label, required this.selected});
  final String label;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    if (label.length < 2) return const SizedBox(width: 75, height: 105);
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
      width: 75,
      height: 105,
      decoration: BoxDecoration(
        color: selected ? const Color(0xFFFFF8D8) : Colors.white,
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: const Color(0xFFCCCCCC)),
        boxShadow: [
          if (selected)
            const BoxShadow(
              color: Color(0x99FFDC64),
              blurRadius: 10,
              spreadRadius: 1,
            ),
          const BoxShadow(
            color: Colors.black45,
            blurRadius: 5,
            offset: Offset(0, 2),
          ),
        ],
      ),
      padding: const EdgeInsets.all(4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            rank,
            style: TextStyle(
              color: color,
              fontSize: 22,
              fontWeight: FontWeight.bold,
              fontFamily: 'Georgia',
              height: 1,
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              suitGlyph,
              style: TextStyle(
                color: color,
                fontSize: 30,
                height: 1,
                fontFamily: 'Georgia',
              ),
            ),
          ),
        ],
      ),
    );
  }
}
