/// Bottom strip: the fanned overlapping hand plus ยกเลิก / ตกลง buttons and
/// contextual secondary actions (จั่วไพ่ / เก็บ / ฝากดัมมี่ / ลง / ทิ้ง / น็อค).
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/audio/sound_service.dart';
import '../../../core/models/index.dart';
import '../../../core/providers/index.dart';
import 'game_buttons.dart';
import 'hand_fan.dart';
import 'timers.dart';

// Haptic helpers — light tick on tap/draw/discard, medium thump on knock.
// Keep all platform-channel calls in this file so the controller stays
// service-free / testable.
void _tapHaptic() => HapticFeedback.selectionClick();
void _actionHaptic() => HapticFeedback.lightImpact();
void _knockHaptic() => HapticFeedback.mediumImpact();

class HandAndControls extends ConsumerWidget {
  const HandAndControls({super.key, required this.view, required this.ctrl});
  final GameView view;
  final GameController ctrl;

  /// Build the contextual action row for the current turn state. Only the
  /// buttons that actually make sense are shown — no ยกเลิก/ตกลง.
  ///
  /// The "ลง"/"ฝาก" button switches behaviour based on whether the player
  /// tapped a table meld first (selectedMeldProvider != null):
  ///   • no meld targeted → "ลง" — create a new meld from ≥3 hand cards.
  ///   • meld targeted    → "ฝาก" — extend that meld with ≥1 hand card.
  List<Widget> _actions(WidgetRef ref) {
    final sfx = ref.read(soundServiceProvider);
    if (!view.started) {
      return [
        GameButton(
          icon: Icons.check_circle_outline,
          label: 'พร้อม',
          colors: const [Color(0xFF6DC94A), Color(0xFF3E8A25)],
          onTap: () {
            _tapHaptic();
            sfx.play(Sfx.button);
            ctrl.ready();
          },
          highlight: true,
        ),
      ];
    }
    if (!view.isMyTurn) {
      return const [WaitingBanner()];
    }
    if (view.phase == 'draw') {
      // Primary action when your turn opens: draw a card.
      final pilePicked = ref.watch(selectedDiscardCardsProvider);
      // Compute target = the deepest selected pile card (smallest index in
      // view.discardPile). The remaining selected pile cards join the meld.
      String? target;
      var deepest = -1;
      for (final c in pilePicked) {
        final idx = view.discardPile.indexOf(c);
        if (idx != -1 && (deepest == -1 || idx < deepest)) {
          deepest = idx;
          target = c;
        }
      }
      final pileSupport = pilePicked.where((c) => c != target).toList();
      final supportingCards = [...pileSupport, ...view.selected];
      // เก็บ needs at least one pile card (target) + enough supporting cards
      // to form a 3-card meld with the target.
      final canPickup = target != null && supportingCards.length >= 2;
      // ฝากดัมมี่: pick a meld + (optionally) a deeper pile card to layoff
      // its target onto that meld. If no pile card is selected, the top of
      // the discard pile is the target by default.
      final drawMeld = ref.watch(selectedMeldProvider);
      final hasPile = view.discardPile.isNotEmpty;
      final canDummyLayoff = drawMeld != null && hasPile;
      return [
        GameButton(
          icon: Icons.style,
          label: 'จั่วไพ่',
          colors: const [Color(0xFFF49A3A), Color(0xFFC66A18)],
          onTap: () {
            _actionHaptic();
            sfx.play(Sfx.draw);
            ctrl.drawDeck();
          },
          highlight: !canDummyLayoff,
        ),
        GameButton(
          icon: Icons.south,
          // "เก็บ" picks one or more cards from the discard pile (deepest =
          // target) plus selected hand cards. Cards above the target that
          // weren't picked end up in the player's hand as extras.
          label: 'เก็บ',
          colors: const [Color(0xFF9A9A9A), Color(0xFF6A6A6A)],
          onTap: canPickup
              ? () {
                  _actionHaptic();
                  sfx.play(Sfx.draw);
                  ctrl.drawDiscard(supportingCards, targetCard: target);
                  ref.read(selectedDiscardCardsProvider.notifier).state =
                      const {};
                  ctrl.clearSelection();
                }
              : null,
        ),
        // ฝากดัมมี่ — appears the moment the player taps a table meld during
        // their draw phase. Picks up the chosen discard target (or top) and
        // lays it directly onto that meld; no new meld required.
        GameButton(
          icon: Icons.add_to_photos,
          label: 'ฝากดัมมี่',
          colors: const [Color(0xFF6DC94A), Color(0xFF3E8A25)],
          onTap: canDummyLayoff
              ? () {
                  _actionHaptic();
                  sfx.play(Sfx.layoff);
                  ctrl.drawDiscard(
                    const [],
                    targetCard: target,
                    meldId: drawMeld,
                  );
                  ref.read(selectedDiscardCardsProvider.notifier).state =
                      const {};
                  ref.read(selectedMeldProvider.notifier).state = null;
                  ctrl.clearSelection();
                }
              : null,
          highlight: canDummyLayoff,
        ),
      ];
    }
    // Meld phase: surface ลง/ฝาก / ทิ้ง / น็อค, each lit when valid.
    final selectedMeld = ref.watch(selectedMeldProvider);
    final selN = view.selected.length;
    final canDiscard = selN == 1;
    // Auto-knock: enabled the moment the server's solver finds any going-out
    // partition of the local hand. The classic manual knock (1 selected card
    // and hand-size 1) still works through the same button.
    final canManualKnock = selN == 1 && view.yourHand.length == 1;
    final canKnock = view.canAutoKnock || canManualKnock;
    final canNewMeld = selectedMeld == null && selN >= 3;
    final canLayoff = selectedMeld != null && selN >= 1;
    return [
      GameButton(
        icon: selectedMeld != null
            ? Icons.add_to_photos
            : Icons.dashboard_customize,
        label: selectedMeld != null ? 'ฝาก' : 'ลง',
        colors: const [Color(0xFF6DC94A), Color(0xFF3E8A25)],
        onTap: (canNewMeld || canLayoff)
            ? () {
                _actionHaptic();
                sfx.play(selectedMeld != null ? Sfx.layoff : Sfx.meld);
                if (selectedMeld != null) {
                  ctrl.layoffSelected(selectedMeld);
                } else {
                  ctrl.meldSelected();
                }
                ref.read(selectedMeldProvider.notifier).state = null;
              }
            : null,
        highlight: canNewMeld || canLayoff,
      ),
      GameButton(
        icon: Icons.delete_outline,
        label: 'ทิ้ง',
        colors: const [Color(0xFFF49A3A), Color(0xFFC66A18)],
        onTap: canDiscard
            ? () {
                _actionHaptic();
                sfx.play(Sfx.discard);
                ctrl.discardSelectedFirst();
              }
            : null,
        highlight: canDiscard && !canKnock,
      ),
      GameButton(
        icon: Icons.bolt,
        label: 'น็อค',
        colors: const [Color(0xFFE060A8), Color(0xFFA42B72)],
        onTap: canKnock
            ? () {
                _knockHaptic();
                sfx.play(Sfx.knock);
                // Prefer auto-knock when the server says a plan exists; only
                // fall through to manual knock if the player has narrowed the
                // hand to 1 card themselves.
                if (view.canAutoKnock) {
                  ctrl.autoKnock();
                } else {
                  ctrl.knock(view.selected.first);
                }
              }
            : null,
        highlight: canKnock,
      ),
    ];
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Local order (drag-reordered); reconciled from server in GameScreen.
    final hand = ref.watch(handOrderProvider);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Wrap(
            alignment: WrapAlignment.center,
            spacing: 12,
            runSpacing: 8,
            children: [
              // Always-available hand-sort toggle (rank/suit alternating).
              SortButton(
                onTap: ref.read(handOrderProvider.notifier).cycleSort,
              ),
              // "ช่วยคิด" hint — only useful on your own turn.
              if (view.isMyTurn)
                _HintButton(
                  onTap: () {
                    _tapHaptic();
                    ctrl.requestSuggestion();
                  },
                ),
              ..._actions(ref),
            ],
          ),
        ),
        HandFan(
          hand: hand,
          selected: view.selected,
          onToggle: (c) {
            _tapHaptic();
            ref.read(soundServiceProvider).play(Sfx.cardFlip);
            ctrl.toggleSelect(c);
          },
          onMove: ref.read(handOrderProvider.notifier).move,
        ),
      ],
    );
  }
}

/// "💡 ช่วยคิด" hint button — asks the server to suggest the next move.
class _HintButton extends StatelessWidget {
  const _HintButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFF8A6E2D),
      borderRadius: BorderRadius.circular(22),
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: onTap,
        child: const Padding(
          padding: EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('💡', style: TextStyle(fontSize: 16)),
              SizedBox(width: 6),
              Text(
                'ช่วยคิด',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Small "จัดไพ่" toggle — single press cycles the local hand between
/// group-by-rank (pairs/sets) and group-by-suit (runs). Decoupled visually
/// from the contextual action buttons so it's always reachable.
class SortButton extends StatelessWidget {
  const SortButton({super.key, required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFF2D6E9E),
      borderRadius: BorderRadius.circular(22),
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: onTap,
        child: const Padding(
          padding: EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.sort, color: Colors.white, size: 20),
              SizedBox(width: 6),
              Text(
                'จัดไพ่',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
