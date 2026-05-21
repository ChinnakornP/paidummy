/// In-room game screen: Flame felt + Flutter seat/hand/control overlay.
/// All interaction is driven by `GameController` intents; this widget is just
/// a presentation layer over the reduced `GameView` state.
library;

import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/audio/sound_service.dart';
import '../../core/models/index.dart';
import '../../core/providers/index.dart';
import '../../shared/widgets/index.dart';
import 'game_table.dart';
import 'widgets/index.dart';

/// "🤖 ใช้บอทเล่นแทน" chip rendered in the top-left of the game screen.
/// Tap to toggle server-side auto-play for the local player.
class _BotTakeoverChip extends StatelessWidget {
  const _BotTakeoverChip({required this.enabled, required this.onTap});
  final bool enabled;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    return Material(
      color: enabled
          ? const Color(0xFF3C7A8C)
          : Colors.black.withValues(alpha: 0.35),
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('🤖 ', style: TextStyle(fontSize: 14)),
              Text(
                enabled ? 'บอทเล่นแทน' : 'รับช่วงด้วยบอท',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
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

class GameScreen extends ConsumerStatefulWidget {
  const GameScreen({super.key, required this.roomId});
  final String roomId;
  @override
  ConsumerState<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends ConsumerState<GameScreen> {
  final TableGame _game = TableGame();
  bool _connected = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final g = ref.read(sessionProvider);
      if (g != null && !_connected) {
        _connected = true;
        ref
            .read(gameControllerProvider.notifier)
            .connect(g.token, widget.roomId);
        ref.read(gameControllerProvider.notifier).ready();
      }
    });
  }

  /// Seat slots for opponents around the felt (alignment within the Stack).
  static const _slots = [
    Alignment(-0.92, -0.62),
    Alignment(0.92, -0.62),
    Alignment(0.95, 0.18),
    Alignment(-0.95, 0.18),
  ];

  @override
  Widget build(BuildContext context) {
    final view = ref.watch(gameControllerProvider);
    final ctrl = ref.read(gameControllerProvider.notifier);
    _game.setView(view);

    // Reconcile the local hand-order list whenever the server's authoritative
    // hand set changes (draw adds, discard/meld removes).
    ref.listen(gameControllerProvider.select((v) => v.yourHand), (prev, next) {
      ref.read(handOrderProvider.notifier).reconcile(next);
    });

    ref.listen(gameControllerProvider, (prev, next) {
      if (next.lastError != null && next.lastError != prev?.lastError) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(next.lastError!)));
        ctrl.clearError();
      }
      if (next.lastActionPoints != null &&
          next.lastActionPoints != prev?.lastActionPoints) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFF2A6E3A),
            duration: const Duration(seconds: 2),
            content: Text(
              '+${next.lastActionPoints} แต้ม',
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
          ),
        );
        ctrl.clearActionPoints();
      }
      if (next.lastPenalty != null && next.lastPenalty != prev?.lastPenalty) {
        final p = next.lastPenalty!;
        final label = p.reason == 'full' ? 'ทิ้งเต็ม' : 'ทิ้งดัมมี่';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFFA42B72),
            duration: const Duration(seconds: 3),
            content: Text(
              '-${p.points} แต้ม ($label)',
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
          ),
        );
        ctrl.clearPenalty();
      }
      final rr = next.matchResult ?? next.roundResult;
      if (rr != null &&
          (prev?.roundResult != next.roundResult ||
              prev?.matchResult != next.matchResult)) {
        final isMatch = next.matchResult != null;
        if (isMatch) {
          // Win/lose sting on match end — winner flag is per-row; play win
          // if the local seat won, else lose.
          final rows = (rr['rows'] as List?) ?? const [];
          var iWon = false;
          for (final row in rows) {
            final m = row as Map?;
            if (m != null &&
                m['seat'] == next.yourSeat &&
                m['winner'] == true) {
              iWon = true;
              break;
            }
          }
          ref.read(soundServiceProvider).play(iWon ? Sfx.win : Sfx.lose);
        }
        showDialog<void>(
          context: context,
          builder: (c) => AlertDialog(
            title: Text(isMatch ? 'จบเกม 🏆' : 'จบรอบ'),
            content: ResultBody(result: rr, isMatch: isMatch),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(c),
                child: const Text('ตกลง'),
              ),
              // Rematch CTA — only meaningful when the match (not a single
              // round) just ended. Clears the cached result envelopes and
              // re-sends `ready`, which the server treats as a fresh-match
              // request when the room is in the finished state.
              if (isMatch)
                FilledButton.icon(
                  onPressed: () {
                    ctrl.clearResults();
                    ctrl.ready();
                    Navigator.pop(c);
                  },
                  icon: const Icon(Icons.refresh),
                  label: const Text('อีกตา'),
                ),
            ],
          ),
        );
      }
    });

    final opponents = [
      for (final p in view.players)
        if (p.seat != view.yourSeat) p,
    ]..sort((a, b) => a.seat.compareTo(b.seat));
    PlayerPublic? selfPlayer;
    if (view.yourSeat >= 0) {
      for (final p in view.players) {
        if (p.seat == view.yourSeat) {
          selfPlayer = p;
          break;
        }
      }
    }

    return Scaffold(
      backgroundColor: const Color(0xFF12313B),
      body: SafeArea(
        child: Stack(
          children: [
            Positioned.fill(child: GameWidget(game: _game)),

            // Collapse / leave (top-left, like the original chevron).
            Positioned(
              left: 8,
              top: 8,
              child: RoundIconButton(
                icon: Icons.keyboard_arrow_down,
                onTap: () {
                  ctrl.leave();
                  ref.read(currentRoomProvider.notifier).state = null;
                },
              ),
            ),

            // Top-right "shop" button (gold circle + +120% badge), decorative
            // chrome from the design — wired to no backend yet.
            const Positioned(right: 16, top: 16, child: ShopButton()),

            // Self-elect bot takeover toggle. Sits in the upper-left next to
            // the leave chevron so it's easy to flip when stepping away.
            if (selfPlayer != null && view.started)
              Positioned(
                left: 56,
                top: 12,
                child: _BotTakeoverChip(
                  enabled: selfPlayer.botMode,
                  onTap: () => ctrl.setBotTakeover(!selfPlayer!.botMode),
                ),
              ),

            // Purple side-tab on the right edge (decorative menu handle).
            const Align(alignment: Alignment.centerRight, child: SideTab()),

            // Bottom-left chat button (decorative).
            const Positioned(left: 16, bottom: 16, child: ChatButton()),

            // Bottom-right column: swap, chest, timer (decorative).
            const Positioned(right: 16, bottom: 16, child: RightChrome()),

            // Auto-start countdown (10s with <4 players, 5s when full).
            if (!view.started && view.countdownEndMs > 0)
              Align(
                alignment: const Alignment(0, -0.78),
                child: CountdownChip(endMs: view.countdownEndMs),
              ),

            // Per-turn shot clock (60s). On expiry the server auto draws
            // and discards — never knocks.
            if (view.started && view.turnEndMs > 0)
              Align(
                alignment: const Alignment(0, -0.78),
                child: TurnTimerChip(
                  endMs: view.turnEndMs,
                  isMyTurn: view.isMyTurn,
                  turnName: (view.turn >= 0 && view.turn < view.players.length)
                      ? view.players[view.turn].name
                      : '',
                ),
              ),

            // Add-bot button (only meaningful before the round starts).
            if (!view.started)
              Align(
                alignment: const Alignment(0, -0.92),
                child: PillButton(
                  label: '＋ เพิ่มบอท',
                  color: const Color(0xFF3C7A8C),
                  onTap: () {
                    final g = ref.read(sessionProvider);
                    if (g != null) {
                      ref
                          .read(apiClientProvider)
                          .addBots(g.token, widget.roomId, 1);
                    }
                  },
                ),
              ),

            // Opponent seats around the felt. Each slot gets a different
            // panel colour, mirroring the four player-cards in the design.
            for (var i = 0; i < opponents.length && i < _slots.length; i++)
              Align(
                alignment: _slots[i],
                child: Seat(
                  player: opponents[i],
                  active: view.turn == opponents[i].seat,
                  palette: kSeatPalettes[i % kSeatPalettes.length],
                  onTap: () => showProfileDialog(
                    context,
                    player: opponents[i],
                    isSelf: false,
                  ),
                ),
              ),

            // Centre pile (deck back + head + tappable discard). Tapping a
            // discard card targets it for "เก็บ"; tapping again deselects.
            Align(
              alignment: const Alignment(0, -0.05),
              child: CenterPile(view: view),
            ),

            // Four per-player meld panels, one per quadrant of the felt:
            //   A = first opponent  (top-left)
            //   B = second opponent (top-right, grows from screen-centre)
            //   C = self            (bottom-left)
            //   D = third opponent  (bottom-right, grows from screen-centre)
            // Tapping any meld still switches the "ลง" button into "ฝาก".
            if (view.melds.isNotEmpty)
              Positioned.fill(
                child: QuadrantMeldsLayer(
                  view: view,
                  selectedId: ref.watch(selectedMeldProvider),
                  onTap: (id) {
                    final cur = ref.read(selectedMeldProvider);
                    ref.read(selectedMeldProvider.notifier).state = cur == id
                        ? null
                        : id;
                  },
                ),
              ),

            // Self seat — always pinned at the bottom-left, above the hand
            // fan so the local player has visible identity (name, coins,
            // hand count) matching the opponent cards. Uses a warm gold
            // palette to set self apart from the opponent colour pool.
            if (selfPlayer != null)
              Align(
                alignment: const Alignment(-0.92, 0.55),
                child: Seat(
                  player: selfPlayer,
                  active: view.isMyTurn,
                  palette: kSelfSeatPalette,
                  onTap: () => showProfileDialog(
                    context,
                    player: selfPlayer!,
                    isSelf: true,
                  ),
                ),
              ),

            // Bottom: fanned hand + action bar.
            Align(
              alignment: Alignment.bottomCenter,
              child: HandAndControls(view: view, ctrl: ctrl),
            ),
          ],
        ),
      ),
    );
  }
}
