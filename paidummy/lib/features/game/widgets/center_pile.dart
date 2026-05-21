/// Centre pile (face-down deck chip + face-up head card + tappable discard
/// pile) rendered as Flutter widgets so each discard card can be tapped to
/// target it for "เก็บ".
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/index.dart';
import '../../../core/providers/index.dart';

class CenterPile extends ConsumerWidget {
  const CenterPile({super.key, required this.view});
  final GameView view;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pile = view.discardPile;
    final selected = ref.watch(selectedDiscardCardsProvider);
    // Identify the target (deepest selected pile card) so it can be rendered
    // with a stronger "เป้าหมาย" highlight.
    String? target;
    var deepest = -1;
    for (final c in selected) {
      final idx = pile.indexOf(c);
      if (idx != -1 && (deepest == -1 || idx < deepest)) {
        deepest = idx;
        target = c;
      }
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Deck back with remaining count.
          _DeckBackCard(count: view.drawCount),
          // The head card now sits at the bottom of the discard pile (it's
          // pickable like any other) — rendered inside _DiscardRow with a
          // 👑 marker. We no longer render it separately.
          if (pile.isNotEmpty) ...[
            const SizedBox(width: 10),
            _DiscardRow(
              pile: pile,
              headCard: view.headCard,
              selected: selected,
              target: target,
              onTap: (card) {
                HapticFeedback.selectionClick();
                final cur = ref.read(selectedDiscardCardsProvider);
                final next = Set<String>.from(cur);
                if (!next.add(card)) next.remove(card);
                ref.read(selectedDiscardCardsProvider.notifier).state = next;
              },
            ),
          ],
        ],
      ),
    );
  }
}

/// Horizontal discard pile (oldest→newest). Adaptive overlap keeps any
/// length fitting a reasonable width; selected card lifts.
class _DiscardRow extends StatelessWidget {
  const _DiscardRow({
    required this.pile,
    required this.headCard,
    required this.selected,
    required this.target,
    required this.onTap,
  });
  final List<String> pile;
  final String headCard; // marked with 👑 if present in the pile
  final Set<String> selected;
  final String? target; // deepest selected pile card — pile truncates here
  final void Function(String card) onTap;

  static const _cardW = 50.0;
  static const _maxRowWidth = 260.0;

  @override
  Widget build(BuildContext context) {
    final n = pile.length;
    const naturalStep = 22.0;
    final fitStep = n > 1 ? (_maxRowWidth - _cardW) / (n - 1) : 0.0;
    final step = (fitStep > 0 && fitStep < naturalStep) ? fitStep : naturalStep;
    final width = n == 0 ? 0.0 : _cardW + (n - 1) * step;
    return SizedBox(
      width: width,
      height: 78,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          for (var i = 0; i < n; i++)
            Positioned(
              // Key by card so a newly discarded card gets a fresh element
              // and plays its entrance tween, while existing cards don't.
              key: ValueKey(pile[i]),
              left: i * step,
              top: selected.contains(pile[i]) ? -6 : 4,
              child: GestureDetector(
                onTap: () => onTap(pile[i]),
                child: _CardEntrance(
                  child: _PileFaceCard(
                    label: pile[i],
                    highlight: selected.contains(pile[i]),
                    isTarget: pile[i] == target,
                    isHead: pile[i] == headCard,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// One-shot scale+fade entrance for a freshly-dealt/discarded card. Honors
/// the platform "reduce motion" setting by collapsing the duration to zero.
class _CardEntrance extends StatelessWidget {
  const _CardEntrance({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: reduce ? Duration.zero : const Duration(milliseconds: 220),
      curve: Curves.easeOutBack,
      builder: (_, t, c) => Opacity(
        opacity: t.clamp(0.0, 1.0),
        child: Transform.scale(scale: 0.7 + 0.3 * t, child: c),
      ),
      child: child,
    );
  }
}

/// Small face-up card used by the centre pile. When [isHead] is true, a
/// crown badge is overlaid in the top-right so players know that card
/// carries the +50 head bonus when melded.
class _PileFaceCard extends StatelessWidget {
  const _PileFaceCard({
    required this.label,
    this.highlight = false,
    this.isTarget = false,
    this.isHead = false,
  });
  final String label;
  final bool highlight;
  final bool isTarget;
  final bool isHead;

  @override
  Widget build(BuildContext context) {
    if (label.length < 2) return const SizedBox(width: 50, height: 70);
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
    // The target card (deepest selected) gets a stronger orange treatment so
    // the player can tell at a glance which card the pickup truncates at —
    // separate from the lighter "also-included" highlight for other picks.
    final fill = isTarget
        ? const Color(0xFFFFE0B5)
        : highlight
        ? const Color(0xFFFFF8D8)
        : Colors.white;
    final borderColor = isTarget
        ? const Color(0xFFFF8A30)
        : highlight
        ? const Color(0xFFFFD24A)
        : const Color(0xFFCCCCCC);
    final borderWidth = isTarget ? 3.0 : (highlight ? 2.5 : 1.0);
    final card = Container(
      width: 50,
      height: 70,
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: borderColor, width: borderWidth),
        boxShadow: [
          if (isTarget)
            const BoxShadow(color: Color(0xCCFF8A30), blurRadius: 14)
          else if (highlight)
            const BoxShadow(color: Color(0xAAFFD24A), blurRadius: 12),
          const BoxShadow(
            color: Colors.black45,
            blurRadius: 3,
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
              fontSize: 16,
              fontWeight: FontWeight.bold,
              fontFamily: 'Georgia',
              height: 1,
            ),
          ),
          Text(
            suitGlyph,
            style: TextStyle(
              color: color,
              fontSize: 22,
              fontFamily: 'Georgia',
              height: 1,
            ),
          ),
        ],
      ),
    );
    if (!isHead) return card;
    // Head card carries the +50 เกิดหัว bonus — overlay a crown badge.
    return SizedBox(
      width: 50,
      height: 70,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          card,
          const Positioned(
            top: -6,
            right: -4,
            child: Text('👑', style: TextStyle(fontSize: 16)),
          ),
        ],
      ),
    );
  }
}

/// Deck-back chip showing remaining draw-pile count.
class _DeckBackCard extends StatelessWidget {
  const _DeckBackCard({required this.count});
  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 50,
      height: 70,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFA82020), Color(0xFF8A1818)],
        ),
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: Colors.white, width: 2),
        boxShadow: const [
          BoxShadow(color: Colors.black45, blurRadius: 3, offset: Offset(0, 2)),
        ],
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Text(
            '$count',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const Positioned(
            left: 5,
            bottom: 4,
            child: Text(
              '⭐',
              style: TextStyle(color: Color(0xFFFFD700), fontSize: 10),
            ),
          ),
        ],
      ),
    );
  }
}
