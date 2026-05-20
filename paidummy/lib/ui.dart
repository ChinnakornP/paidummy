/// Screens and the app shell: Home (guest sign-in) -> Lobby (rooms) ->
/// Game (Flame felt + Flutter seat/hand/control overlay), styled after the
/// classic Thai Dummy client.
library;

import 'dart:async';

import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'game_table.dart';
import 'models.dart';
import 'providers.dart';

class PaiDummyApp extends StatelessWidget {
  const PaiDummyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Pai Dummy',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF0B6B3A)),
        useMaterial3: true,
      ),
      home: const RootScreen(),
    );
  }
}

class RootScreen extends ConsumerWidget {
  const RootScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final guest = ref.watch(sessionProvider);
    if (guest == null) return const HomeScreen();
    final room = ref.watch(currentRoomProvider);
    if (room == null) return const LobbyScreen();
    return GameScreen(roomId: room);
  }
}

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});
  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  final _name = TextEditingController(text: 'Player');
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _enter() async {
    setState(() => _busy = true);
    try {
      await ref.read(sessionProvider.notifier).createGuest(_name.text);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF12313B),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Pai Dummy',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'ไพ่ดัมมี่ — Thai Dummy',
                style: TextStyle(color: Colors.white70),
              ),
              const SizedBox(height: 24),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: TextField(
                  controller: _name,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    labelText: 'Display name',
                    labelStyle: TextStyle(color: Colors.white70),
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _busy ? null : _enter,
                child: _busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Play as guest'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class LobbyScreen extends ConsumerWidget {
  const LobbyScreen({super.key});

  Future<void> _create(BuildContext context, WidgetRef ref) async {
    final ctrl = TextEditingController(text: 'Table');
    final name = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('New room'),
        content: TextField(controller: ctrl),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, ctrl.text),
            child: const Text('Create'),
          ),
        ],
      ),
    );
    if (name == null) return;
    final g = ref.read(sessionProvider)!;
    final id = await ref.read(apiClientProvider).createRoom(g.token, name, 4);
    ref.read(currentRoomProvider.notifier).state = id;
  }

  Future<void> _join(WidgetRef ref, String roomId) async {
    final g = ref.read(sessionProvider)!;
    await ref.read(apiClientProvider).joinRoom(g.token, roomId);
    ref.read(currentRoomProvider.notifier).state = roomId;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rooms = ref.watch(roomListProvider);
    final g = ref.watch(sessionProvider);
    return Scaffold(
      appBar: AppBar(
        title: Text('Lobby — ${g?.name ?? ''}'),
        actions: [
          IconButton(
            onPressed: () => ref.invalidate(roomListProvider),
            icon: const Icon(Icons.refresh),
          ),
          IconButton(
            onPressed: () => ref.read(sessionProvider.notifier).signOut(),
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _create(context, ref),
        label: const Text('New room'),
        icon: const Icon(Icons.add),
      ),
      body: rooms.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (list) => list.isEmpty
            ? const Center(child: Text('No open rooms. Create one!'))
            : ListView(
                children: [
                  for (final r in list)
                    ListTile(
                      title: Text(r.name),
                      subtitle: Text('${r.players}/${r.max} players'),
                      trailing: const Icon(Icons.login),
                      onTap: () => _join(ref, r.id),
                    ),
                ],
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
      final rr = next.matchResult ?? next.roundResult;
      if (rr != null &&
          (prev?.roundResult != next.roundResult ||
              prev?.matchResult != next.matchResult)) {
        final isMatch = next.matchResult != null;
        showDialog<void>(
          context: context,
          builder: (c) => AlertDialog(
            title: Text(isMatch ? 'จบเกม 🏆' : 'จบรอบ'),
            content: _ResultBody(result: rr, isMatch: isMatch),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(c),
                child: const Text('ตกลง'),
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
              child: _RoundIconButton(
                icon: Icons.keyboard_arrow_down,
                onTap: () {
                  ctrl.leave();
                  ref.read(currentRoomProvider.notifier).state = null;
                },
              ),
            ),

            // Top-right "shop" button (gold circle + +120% badge), decorative
            // chrome from the design — wired to no backend yet.
            const Positioned(right: 16, top: 16, child: _ShopButton()),

            // Purple side-tab on the right edge (decorative menu handle).
            const Align(alignment: Alignment.centerRight, child: _SideTab()),

            // Bottom-left chat button (decorative).
            const Positioned(left: 16, bottom: 16, child: _ChatButton()),

            // Bottom-right column: swap, chest, timer (decorative).
            const Positioned(right: 16, bottom: 16, child: _RightChrome()),

            // Auto-start countdown (10s with <4 players, 5s when full).
            if (!view.started && view.countdownEndMs > 0)
              Align(
                alignment: const Alignment(0, -0.78),
                child: _CountdownChip(endMs: view.countdownEndMs),
              ),

            // Per-turn shot clock (30s). On expiry the server auto draws
            // and discards — never knocks.
            if (view.started && view.turnEndMs > 0)
              Align(
                alignment: const Alignment(0, -0.78),
                child: _TurnTimerChip(
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
                child: _PillButton(
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
                child: _Seat(
                  player: opponents[i],
                  active: view.turn == opponents[i].seat,
                  palette: _kSeatPalettes[i % _kSeatPalettes.length],
                ),
              ),

            // Bottom: fanned hand + action bar.
            Align(
              alignment: Alignment.bottomCenter,
              child: _HandAndControls(view: view, ctrl: ctrl),
            ),
          ],
        ),
      ),
    );
  }
}

/// Circular avatar with hand-count badge, score pill and turn glow.
/// Player-card panel matching `.player-card` in game_design_v1.html: a 100px
/// rounded rectangle in one of four seat colours, an outlined avatar inside,
/// a white-on-red rectangular badge with the hand count, the player name,
/// and a black-translucent score / coin pill.
class _Seat extends StatelessWidget {
  const _Seat({
    required this.player,
    required this.active,
    required this.palette,
  });
  final PlayerPublic player;
  final bool active;
  final _SeatPalette palette;

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

/// Seat-card colour scheme (matches `.player-card` / `.avatar` variants in
/// game_design_v1.html). Slot index decides which palette is used.
class _SeatPalette {
  const _SeatPalette(this.bg, this.avatar);
  final List<Color> bg;
  final List<Color> avatar;
}

const _kSeatPalettes = [
  // p1: blue
  _SeatPalette(
    [Color(0xFF2D6E9E), Color(0xFF1E4D70)],
    [Color(0xFF7A8A9A), Color(0xFF4A5560)],
  ),
  // p2: green
  _SeatPalette(
    [Color(0xFF2D8A6E), Color(0xFF1E6E54)],
    [Color(0xFFD4A878), Color(0xFF8A6848)],
  ),
  // p3: yellow / olive
  _SeatPalette(
    [Color(0xFF8A8048), Color(0xFF6E6332)],
    [Color(0xFF2A2A2A), Color(0xFF1A1A1A)],
  ),
  // p4: dark / maroon
  _SeatPalette(
    [Color(0xFF5A4040), Color(0xFF3A2828)],
    [Color(0xFF6A8A4A), Color(0xFF2A4A1A)],
  ),
];

class _RoundIconButton extends StatelessWidget {
  const _RoundIconButton({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFF1B4350),
      shape: const CircleBorder(
        side: BorderSide(color: Colors.white24, width: 2),
      ),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Icon(icon, color: Colors.white, size: 26),
        ),
      ),
    );
  }
}

/// Bottom strip: the fanned overlapping hand plus ยกเลิก / ตกลง buttons and
/// contextual secondary actions.
class _HandAndControls extends ConsumerWidget {
  const _HandAndControls({required this.view, required this.ctrl});
  final GameView view;
  final GameController ctrl;

  /// Build the contextual action row for the current turn state. Only the
  /// buttons that actually make sense are shown — no ยกเลิก/ตกลง.
  List<Widget> _actions() {
    if (!view.started) {
      return [
        _GameButton(
          icon: Icons.check_circle_outline,
          label: 'พร้อม',
          colors: const [Color(0xFF6DC94A), Color(0xFF3E8A25)],
          onTap: ctrl.ready,
          highlight: true,
        ),
      ];
    }
    if (!view.isMyTurn) {
      return const [_WaitingBanner()];
    }
    if (view.phase == 'draw') {
      // Primary action when your turn opens: draw a card.
      return [
        _GameButton(
          icon: Icons.style,
          label: 'จั่วไพ่',
          colors: const [Color(0xFFF49A3A), Color(0xFFC66A18)],
          onTap: ctrl.drawDeck,
          highlight: true,
        ),
        _GameButton(
          icon: Icons.south,
          // เก็บ requires selecting ≥2 hand cards that, together with the
          // discard top, form a valid meld — the server will reject otherwise.
          label: 'เก็บ',
          colors: const [Color(0xFF9A9A9A), Color(0xFF6A6A6A)],
          onTap: (view.discardTop.isEmpty || view.selected.length < 2)
              ? null
              : () => ctrl.drawDiscard(view.selected.toList()),
        ),
      ];
    }
    // Meld phase: surface only ลง / ทิ้ง / น็อค, each lit when valid.
    final selN = view.selected.length;
    final canMeld = selN >= 3;
    final canDiscard = selN == 1;
    final canKnock = selN == 1 && view.yourHand.length == 1;
    return [
      _GameButton(
        icon: Icons.dashboard_customize,
        label: 'ลง',
        colors: const [Color(0xFF6DC94A), Color(0xFF3E8A25)],
        onTap: canMeld ? ctrl.meldSelected : null,
        highlight: canMeld,
      ),
      _GameButton(
        icon: Icons.delete_outline,
        label: 'ทิ้ง',
        colors: const [Color(0xFFF49A3A), Color(0xFFC66A18)],
        onTap: canDiscard ? ctrl.discardSelectedFirst : null,
        highlight: canDiscard && !canKnock,
      ),
      _GameButton(
        icon: Icons.bolt,
        label: 'น็อค',
        colors: const [Color(0xFFE060A8), Color(0xFFA42B72)],
        onTap: canKnock ? () => ctrl.knock(view.selected.first) : null,
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
              _SortButton(
                onTap: ref.read(handOrderProvider.notifier).cycleSort,
              ),
              ..._actions(),
            ],
          ),
        ),
        _HandFan(
          hand: hand,
          selected: view.selected,
          onToggle: ctrl.toggleSelect,
          onMove: ref.read(handOrderProvider.notifier).move,
        ),
      ],
    );
  }
}

/// Overlapping fan of the player's own hand with drag-to-reorder.
///
/// Each card is wrapped in a GestureDetector keyed by the card code so its
/// element survives reorder rebuilds. A short tap toggles selection (existing
/// behaviour); a horizontal drag past the gesture-arena threshold is treated
/// as a reorder — the card follows the pointer and swaps with neighbours in
/// real time as the accumulated offset crosses card-overlap boundaries.
class _HandFan extends StatefulWidget {
  const _HandFan({
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
  State<_HandFan> createState() => _HandFanState();
}

class _HandFanState extends State<_HandFan> {
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

/// Readable round/match summary: per-player score, and (on match end) the
/// coin settlement — winner takes the pot, losers pay the bet.
class _ResultBody extends StatelessWidget {
  const _ResultBody({required this.result, required this.isMatch});
  final Map<String, dynamic> result;
  final bool isMatch;

  @override
  Widget build(BuildContext context) {
    final rows = (result['rows'] ?? result['scores']) as List? ?? const [];
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (isMatch && result['winner'] != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              'ผู้ชนะ: ${result['winner']}  (เดิมพัน ${result['bet'] ?? 0})',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        if (!isMatch && result['reason'] != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              result['reason'] == 'knock' ? 'จบด้วยการน็อค' : 'ไพ่กองหมด',
            ),
          ),
        for (final r in rows.cast<Map<String, dynamic>>())
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (r['winner'] == true) const Text('🏆 '),
                Expanded(child: Text('${r['name']}')),
                Text('คะแนน ${r['score'] ?? r['total'] ?? 0}'),
                if (r['coin_delta'] != null) ...[
                  const SizedBox(width: 10),
                  Text(
                    '${(r['coin_delta'] as num) >= 0 ? '+' : ''}'
                    '${r['coin_delta']} 🪙',
                    style: TextStyle(
                      color: (r['coin_delta'] as num) >= 0
                          ? const Color(0xFF1B7F3B)
                          : const Color(0xFFC0392B),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ],
            ),
          ),
      ],
    );
  }
}

/// Game-styled action button: gradient pill, icon + Thai label, soft outer
/// glow when [highlight] is true (the suggested next move).
class _GameButton extends StatelessWidget {
  const _GameButton({
    required this.icon,
    required this.label,
    required this.colors,
    required this.onTap,
    this.highlight = false,
  });

  final IconData icon;
  final String label;
  final List<Color> colors; // top, bottom — vertical gloss gradient
  final VoidCallback? onTap;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    final body = Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: colors,
        ),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.45),
          width: 1.5,
        ),
        boxShadow: [
          const BoxShadow(
            color: Colors.black54,
            blurRadius: 6,
            offset: Offset(0, 3),
          ),
          if (enabled && highlight)
            BoxShadow(
              color: colors.last.withValues(alpha: 0.75),
              blurRadius: 22,
              spreadRadius: 1,
            ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(28),
        child: InkWell(
          borderRadius: BorderRadius.circular(28),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 11),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, color: Colors.white, size: 22),
                const SizedBox(width: 8),
                Text(
                  label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.4,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 180),
      opacity: enabled ? 1 : 0.45,
      child: body,
    );
  }
}

/// Live auto-start countdown. Self-ticks once per second from a fixed
/// server-provided deadline (unix ms), so re-renders stay local to this widget
/// instead of rebuilding the whole game screen each tick.
class _CountdownChip extends StatefulWidget {
  const _CountdownChip({required this.endMs});
  final int endMs;
  @override
  State<_CountdownChip> createState() => _CountdownChipState();
}

class _CountdownChipState extends State<_CountdownChip> {
  Timer? _t;

  @override
  void initState() {
    super.initState();
    _t = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final remaining = widget.endMs - DateTime.now().millisecondsSinceEpoch;
    final secs = (remaining / 1000).ceil();
    if (secs <= 0) return const SizedBox.shrink();
    // Tight = ≤5s (table likely full): switch to a hot red palette.
    final tight = secs <= 5;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: tight
              ? const [Color(0xFFFF7B7B), Color(0xFFB02828)]
              : const [Color(0xFFFFE38A), Color(0xFFE8902E)],
        ),
        borderRadius: BorderRadius.circular(22),
        boxShadow: const [
          BoxShadow(color: Colors.black54, blurRadius: 6, offset: Offset(0, 3)),
        ],
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.5),
          width: 1.5,
        ),
      ),
      child: Text(
        'เริ่มใน  $secs  วินาที',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 15,
          fontWeight: FontWeight.bold,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

/// Live per-turn shot-clock chip (30s by default). Self-ticking like the
/// pre-start countdown; goes red in the last 10s for urgency. Visible to
/// everyone so opponents see how long the active player has left.
class _TurnTimerChip extends StatefulWidget {
  const _TurnTimerChip({
    required this.endMs,
    required this.isMyTurn,
    required this.turnName,
  });
  final int endMs;
  final bool isMyTurn;
  final String turnName;
  @override
  State<_TurnTimerChip> createState() => _TurnTimerChipState();
}

class _TurnTimerChipState extends State<_TurnTimerChip> {
  Timer? _t;

  @override
  void initState() {
    super.initState();
    _t = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final remaining = widget.endMs - DateTime.now().millisecondsSinceEpoch;
    final secs = (remaining / 1000).ceil();
    if (secs <= 0) return const SizedBox.shrink();
    final urgent = secs <= 10;
    final colors = urgent
        ? const [Color(0xFFFF7B7B), Color(0xFFB02828)]
        : const [Color(0xFF6FB6E0), Color(0xFF2F7BB0)];
    final label = widget.isMyTurn
        ? 'ตาคุณ  ⏱ $secs'
        : 'ตา ${widget.turnName}  ⏱ $secs';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: colors,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.45),
          width: 1.2,
        ),
        boxShadow: const [
          BoxShadow(color: Colors.black54, blurRadius: 5, offset: Offset(0, 2)),
        ],
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 14,
          fontWeight: FontWeight.bold,
          letterSpacing: 0.4,
        ),
      ),
    );
  }
}

/// Small "จัดไพ่" toggle — single press cycles the local hand between
/// group-by-rank (pairs/sets) and group-by-suit (runs). Decoupled visually
/// from the contextual action buttons so it's always reachable.
class _SortButton extends StatelessWidget {
  const _SortButton({required this.onTap});
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

/// Subtle "waiting for other players" chip shown when it's not your turn.
class _WaitingBanner extends StatelessWidget {
  const _WaitingBanner();
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white24),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: Colors.white70,
            ),
          ),
          SizedBox(width: 10),
          Text(
            'รอตาผู้อื่น...',
            style: TextStyle(color: Colors.white70, fontSize: 14),
          ),
        ],
      ),
    );
  }
}

class _PillButton extends StatelessWidget {
  const _PillButton({
    required this.label,
    required this.color,
    required this.onTap,
  });
  final String label;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return Opacity(
      opacity: enabled ? 1 : 0.4,
      child: Material(
        color: color,
        borderRadius: BorderRadius.circular(22),
        child: InkWell(
          borderRadius: BorderRadius.circular(22),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 11),
            child: Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ---- Decorative chrome (matches game_design_v1.html, no backend yet) ----

/// Gold circular shop button with the +120% red badge.
class _ShopButton extends StatelessWidget {
  const _ShopButton();
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 64,
      height: 64,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: 60,
            height: 60,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFFFFE9A3), Color(0xFFC89D3A)],
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black54,
                  blurRadius: 12,
                  offset: Offset(0, 4),
                ),
              ],
            ),
            child: const Center(
              child: Text('🛒', style: TextStyle(fontSize: 26)),
            ),
          ),
          Positioned(
            top: -6,
            right: -10,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              decoration: BoxDecoration(
                color: const Color(0xFFD63333),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.white, width: 2),
              ),
              child: const Text(
                '+120%',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Purple side-tab on the right edge, like the menu handle in the mock.
class _SideTab extends StatelessWidget {
  const _SideTab();
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 30,
      height: 60,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF5D4A8A), Color(0xFF3D2A6A)],
        ),
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(8),
          bottomLeft: Radius.circular(8),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black54,
            blurRadius: 6,
            offset: Offset(-2, 2),
          ),
        ],
      ),
      alignment: Alignment.center,
      child: const Text(
        '≡',
        style: TextStyle(color: Colors.white, fontSize: 18),
      ),
    );
  }
}

/// Light circular chat button (decorative).
class _ChatButton extends StatelessWidget {
  const _ChatButton();
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFE8EEF2), Color(0xFFC5CDD2)],
        ),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.4),
          width: 2,
        ),
        boxShadow: const [
          BoxShadow(
            color: Colors.black54,
            blurRadius: 10,
            offset: Offset(0, 4),
          ),
        ],
      ),
      alignment: Alignment.center,
      child: const Text('💬', style: TextStyle(fontSize: 26)),
    );
  }
}

/// Bottom-right column: swap button + chest + timer (decorative).
class _RightChrome extends StatelessWidget {
  const _RightChrome();
  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFFF49A3A), Color(0xFFC66A18)],
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black54,
                blurRadius: 8,
                offset: Offset(0, 3),
              ),
            ],
          ),
          alignment: Alignment.center,
          child: const Text(
            '⇄',
            style: TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        const SizedBox(height: 6),
        const Text('🎁', style: TextStyle(fontSize: 40)),
        const SizedBox(height: 2),
        const Text(
          '00:58:59',
          style: TextStyle(
            color: Colors.white,
            fontSize: 12,
            fontWeight: FontWeight.bold,
            shadows: [
              Shadow(
                color: Colors.black87,
                offset: Offset(1, 1),
                blurRadius: 2,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
