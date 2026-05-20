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
import 'network.dart';
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
      // Painted background carries the entire game look — no asset file
      // needed. Stack layers: felt → vignette → drifting suits → entry card.
      body: Stack(
        children: [
          const Positioned.fill(child: _FeltBackground()),
          // Decorative card-suit motifs scattered in the corners; they sit
          // behind the entry card and are intentionally low-contrast so they
          // never compete with the input controls.
          const Positioned(
            left: 20,
            top: 60,
            child: _FloatingSuit(glyph: '♠', color: Color(0x331A1A1A), size: 110),
          ),
          const Positioned(
            right: 24,
            top: 110,
            child: _FloatingSuit(glyph: '♥', color: Color(0x33D63333), size: 96),
          ),
          const Positioned(
            left: 36,
            bottom: 70,
            child: _FloatingSuit(glyph: '♦', color: Color(0x33D63333), size: 92),
          ),
          const Positioned(
            right: 40,
            bottom: 110,
            child: _FloatingSuit(glyph: '♣', color: Color(0x331A1A1A), size: 100),
          ),
          // Centre column: title block + entry card + footer credit.
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 380),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const _HomeLogo(),
                      const SizedBox(height: 28),
                      _EntryCard(
                        nameController: _name,
                        busy: _busy,
                        onSubmit: _enter,
                      ),
                      const SizedBox(height: 20),
                      Text(
                        'เล่นเร็ว · เดิมพันได้ · ฟรีไม่ต้องสมัคร',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.55),
                          fontSize: 12,
                          letterSpacing: 0.4,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Painted felt: radial green centre with a maroon vignette so the screen
/// reads as "card table from above". No asset image required.
class _FeltBackground extends StatelessWidget {
  const _FeltBackground();
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: RadialGradient(
          center: Alignment.center,
          radius: 1.1,
          colors: [
            Color(0xFF1B6A4A), // bright felt centre
            Color(0xFF0D4733), // deeper felt
            Color(0xFF2A1212), // outer maroon vignette
          ],
          stops: [0.0, 0.55, 1.0],
        ),
      ),
      child: CustomPaint(
        size: Size.infinite,
        painter: _FeltSheenPainter(),
      ),
    );
  }
}

/// Subtle diagonal sheen on top of the felt to suggest a light source — keeps
/// the painted background from looking flat.
class _FeltSheenPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Colors.white.withValues(alpha: 0.06),
          Colors.white.withValues(alpha: 0.0),
        ],
      ).createShader(Offset.zero & size);
    canvas.drawRect(Offset.zero & size, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}

class _FloatingSuit extends StatelessWidget {
  const _FloatingSuit({
    required this.glyph,
    required this.color,
    required this.size,
  });
  final String glyph;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Text(
        glyph,
        style: TextStyle(
          color: color,
          fontSize: size,
          height: 1,
          shadows: const [
            Shadow(color: Colors.black54, blurRadius: 12, offset: Offset(0, 4)),
          ],
        ),
      ),
    );
  }
}

class _HomeLogo extends StatelessWidget {
  const _HomeLogo();
  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // "ไพ่ดัมมี่" — the Thai title sits above the English wordmark with a
        // warm gold gradient that mirrors the in-game self-seat palette.
        ShaderMask(
          shaderCallback: (b) => const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFFFE7A6), Color(0xFFC89A48)],
          ).createShader(b),
          child: const Text(
            'ไพ่ดัมมี่',
            style: TextStyle(
              color: Colors.white,
              fontSize: 52,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.2,
              shadows: [
                Shadow(color: Colors.black87, blurRadius: 12, offset: Offset(0, 4)),
              ],
            ),
          ),
        ),
        const SizedBox(height: 4),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.35),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: const Color(0xFFC89A48).withValues(alpha: 0.5),
            ),
          ),
          child: const Text(
            'PAI DUMMY · THAI RUMMY',
            style: TextStyle(
              color: Color(0xFFFFE7A6),
              fontSize: 11,
              letterSpacing: 2.4,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}

class _EntryCard extends StatelessWidget {
  const _EntryCard({
    required this.nameController,
    required this.busy,
    required this.onSubmit,
  });
  final TextEditingController nameController;
  final bool busy;
  final Future<void> Function() onSubmit;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xCC0F2E22), Color(0xCC061A12)],
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: const Color(0xFFC89A48).withValues(alpha: 0.45),
          width: 1.5,
        ),
        boxShadow: const [
          BoxShadow(color: Colors.black54, blurRadius: 24, offset: Offset(0, 8)),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Padding(
            padding: EdgeInsets.only(left: 4, bottom: 8),
            child: Text(
              'ชื่อผู้เล่น',
              style: TextStyle(
                color: Color(0xFFFFE7A6),
                fontSize: 13,
                letterSpacing: 1.0,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          TextField(
            controller: nameController,
            style: const TextStyle(color: Colors.white, fontSize: 16),
            cursorColor: const Color(0xFFFFE7A6),
            decoration: InputDecoration(
              hintText: 'ตั้งชื่อให้เพื่อนรู้จัก',
              hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.35)),
              filled: true,
              fillColor: Colors.black.withValues(alpha: 0.35),
              prefixIcon: const Icon(Icons.person_outline,
                  color: Color(0xFFFFE7A6)),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(
                  color: Colors.white.withValues(alpha: 0.08),
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Color(0xFFFFD24A), width: 1.6),
              ),
            ),
          ),
          const SizedBox(height: 16),
          // Primary CTA: gold gradient, glowing when active.
          DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              boxShadow: busy
                  ? null
                  : const [
                      BoxShadow(color: Color(0x66FFD24A), blurRadius: 16),
                    ],
              gradient: const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xFFFFD24A), Color(0xFFC8932A)],
              ),
            ),
            child: Material(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(14),
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: busy ? null : () => onSubmit(),
                child: SizedBox(
                  height: 52,
                  child: Center(
                    child: busy
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.4,
                              valueColor: AlwaysStoppedAnimation(
                                Color(0xFF1A1A1A),
                              ),
                            ),
                          )
                        : const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.play_arrow_rounded,
                                  color: Color(0xFF1A1A1A), size: 26),
                              SizedBox(width: 4),
                              Text(
                                'เข้าสู่เกม',
                                style: TextStyle(
                                  color: Color(0xFF1A1A1A),
                                  fontSize: 17,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0.8,
                                ),
                              ),
                            ],
                          ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Center(
            child: Text(
              'เล่นแบบผู้เยือน · ไม่ต้องสมัคร',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.55),
                fontSize: 11,
                letterSpacing: 0.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Lobby is now server-managed: no manual create, no room list. The player
/// picks a bet tier; the server finds (or creates) the nearest open room.
/// Tiers locked when the wallet is short — coin guard enforced server-side
/// too, the UI just disables the card.
class LobbyScreen extends ConsumerWidget {
  const LobbyScreen({super.key});

  Future<void> _enterTier(BuildContext context, WidgetRef ref, int bet) async {
    final g = ref.read(sessionProvider)!;
    try {
      final roomID = await ref.read(apiClientProvider).quickplay(g.token, bet);
      ref.read(currentRoomProvider.notifier).state = roomID;
    } on QuickplayException catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            e.coins != null && e.need != null
                ? 'เงินไม่พอ — ต้องการ ${e.need} 🪙 มี ${e.coins} 🪙'
                : e.message,
          ),
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('ผิดพลาด: $e')));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final g = ref.watch(sessionProvider);
    final me = ref.watch(meProvider);
    final tiers = ref.watch(tiersProvider);
    final liveGuest = me.value;
    final coins = liveGuest?.coins ?? g?.coins ?? 0;
    final rank = liveGuest?.rank;

    return Scaffold(
      backgroundColor: const Color(0xFF1A3548),
      body: SafeArea(
        child: Column(
          children: [
            // (1) Top bar — guest name + rank + live wallet + actions.
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          g?.name ?? '',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (rank != null) _RankPill(rank: rank),
                      ],
                    ),
                  ),
                  _WalletPill(
                    coins: coins,
                    loading: me.isLoading,
                    onRefresh: () => ref.invalidate(meProvider),
                  ),
                  const SizedBox(width: 6),
                  // History sheet.
                  IconButton(
                    onPressed: () => _openHistory(context),
                    icon: const Text('📜', style: TextStyle(fontSize: 22)),
                    tooltip: 'ประวัติ',
                  ),
                  // Open the coin shop sheet.
                  IconButton(
                    onPressed: () => _openShop(context, ref),
                    icon: const Text('🛒', style: TextStyle(fontSize: 22)),
                    tooltip: 'ร้านค้า',
                  ),
                  IconButton(
                    onPressed: () =>
                        ref.read(sessionProvider.notifier).signOut(),
                    icon: const Icon(Icons.logout, color: Colors.white70),
                    tooltip: 'ออก',
                  ),
                ],
              ),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'เลือกห้องเดิมพัน',
                  style: TextStyle(color: Colors.white70, fontSize: 14),
                ),
              ),
            ),
            // (2)+(3) Bet-tier list. Tapping calls /quickplay; server picks or
            // creates a room of that tier.
            Expanded(
              child: tiers.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(
                  child: Text(
                    'โหลดรายการเดิมพันไม่ได้: $e',
                    style: const TextStyle(color: Colors.white70),
                  ),
                ),
                data: (list) => ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: list.length,
                  separatorBuilder: (_, i) => const SizedBox(height: 10),
                  itemBuilder: (_, i) => _TierCard(
                    bet: list[i],
                    coins: coins,
                    onEnter: () => _enterTier(context, ref, list[i]),
                  ),
                ),
              ),
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

            // Per-turn shot clock (60s). On expiry the server auto draws
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

            // Centre pile (deck back + head + tappable discard). Tapping a
            // discard card targets it for "เก็บ"; tapping again deselects.
            Align(
              alignment: const Alignment(0, -0.05),
              child: _CenterPile(view: view),
            ),

            // Tappable meld overlay above the felt. Selecting a meld switches
            // the "ลง" action button into "ฝาก" mode.
            if (view.melds.isNotEmpty)
              Align(
                alignment: const Alignment(0, -0.42),
                child: _MeldsOverlay(
                  melds: view.melds,
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
                child: _Seat(
                  player: selfPlayer,
                  active: view.isMyTurn,
                  palette: _kSelfSeatPalette,
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

// Self seat uses a warm gold palette so the local player can pick their own
// card out of the line-up at a glance, distinct from any opponent colour.
const _kSelfSeatPalette = _SeatPalette(
  [Color(0xFFC8923A), Color(0xFF8E6420)],
  [Color(0xFFFFE7A6), Color(0xFFC89A48)],
);

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
  ///
  /// The "ลง"/"ฝาก" button switches behaviour based on whether the player
  /// tapped a table meld first (selectedMeldProvider != null):
  ///   • no meld targeted → "ลง" — create a new meld from ≥3 hand cards.
  ///   • meld targeted    → "ฝาก" — extend that meld with ≥1 hand card.
  List<Widget> _actions(WidgetRef ref) {
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
          // "เก็บ" picks one or more cards from the discard pile (deepest =
          // target) plus selected hand cards. Cards above the target that
          // weren't picked end up in the player's hand as extras.
          label: 'เก็บ',
          colors: const [Color(0xFF9A9A9A), Color(0xFF6A6A6A)],
          onTap: canPickup
              ? () {
                  ctrl.drawDiscard(supportingCards, targetCard: target);
                  ref.read(selectedDiscardCardsProvider.notifier).state =
                      const {};
                  ctrl.clearSelection();
                }
              : null,
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
      _GameButton(
        icon: selectedMeld != null
            ? Icons.add_to_photos
            : Icons.dashboard_customize,
        label: selectedMeld != null ? 'ฝาก' : 'ลง',
        colors: const [Color(0xFF6DC94A), Color(0xFF3E8A25)],
        onTap: (canNewMeld || canLayoff)
            ? () {
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
        onTap: canKnock
            ? () {
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
              _SortButton(
                onTap: ref.read(handOrderProvider.notifier).cycleSort,
              ),
              ..._actions(ref),
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

/// Live per-turn shot-clock chip (60s by default). Self-ticking like the
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

/// Live wallet pill: 🪙 + current coin balance + tap to refresh.
class _WalletPill extends StatelessWidget {
  const _WalletPill({
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

/// Bet-tier card: a coloured panel showing the stake. Locked (greyed +
/// padlock) when the wallet can't afford it; otherwise tap to enter.
class _TierCard extends StatelessWidget {
  const _TierCard({
    required this.bet,
    required this.coins,
    required this.onEnter,
  });
  final int bet;
  final int coins;
  final VoidCallback onEnter;

  // Lock = wallet < stake (server also enforces; client just disables).
  bool get _canAfford => coins >= bet;

  /// Tier colour scaling roughly with the stake.
  List<Color> get _palette {
    if (bet <= 50) return const [Color(0xFF2D8A6E), Color(0xFF1E6E54)];
    if (bet <= 100) return const [Color(0xFF2D6E9E), Color(0xFF1E4D70)];
    if (bet <= 500) return const [Color(0xFFB8804A), Color(0xFF8A5A2F)];
    if (bet <= 1000) return const [Color(0xFFE060A8), Color(0xFFA42B72)];
    return const [Color(0xFFE8902E), Color(0xFFC0392B)];
  }

  String get _tierLabel {
    if (bet <= 50) return 'ห้องมือใหม่';
    if (bet <= 100) return 'ห้องเริ่มต้น';
    if (bet <= 500) return 'ห้องกลาง';
    if (bet <= 1000) return 'ห้องไฮโรลเลอร์';
    return 'ห้อง VIP';
  }

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: _canAfford ? 1 : 0.55,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: _canAfford ? onEnter : null,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: _palette,
              ),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.25),
                width: 1.5,
              ),
              boxShadow: const [
                BoxShadow(
                  color: Colors.black54,
                  blurRadius: 10,
                  offset: Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _tierLabel,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          '$bet',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 32,
                            fontWeight: FontWeight.bold,
                            height: 1,
                          ),
                        ),
                        const SizedBox(width: 6),
                        const Padding(
                          padding: EdgeInsets.only(bottom: 4),
                          child: Text(
                            '🪙 ต่อมือ',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(22),
                  ),
                  child: _canAfford
                      ? const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'เข้าเล่น',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            SizedBox(width: 4),
                            Icon(
                              Icons.arrow_forward,
                              color: Colors.white,
                              size: 18,
                            ),
                          ],
                        )
                      : const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.lock, color: Colors.white, size: 16),
                            SizedBox(width: 4),
                            Text(
                              'เงินไม่พอ',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Centre pile (face-down deck chip + face-up head card + tappable discard
/// pile) rendered as Flutter widgets so each discard card can be tapped to
/// target it for "เก็บ".
class _CenterPile extends ConsumerWidget {
  const _CenterPile({required this.view});
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
              left: i * step,
              top: selected.contains(pile[i]) ? -6 : 4,
              child: GestureDetector(
                onTap: () => onTap(pile[i]),
                child: _PileFaceCard(
                  label: pile[i],
                  highlight: selected.contains(pile[i]),
                  isTarget: pile[i] == target,
                  isHead: pile[i] == headCard,
                ),
              ),
            ),
        ],
      ),
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

/// Stack of every table meld, each tappable so the player can target it for
/// "ฝาก" (layoff). The selected meld glows gold; tapping it again deselects.
class _MeldsOverlay extends StatelessWidget {
  const _MeldsOverlay({
    required this.melds,
    required this.selectedId,
    required this.onTap,
  });
  final List<MeldView> melds;
  final String? selectedId;
  final void Function(String meldId) onTap;

  @override
  Widget build(BuildContext context) {
    // Group melds by owner so each player's exposed cards line up on one
    // horizontal row — e.g. owner 0's row reads "AAA 234 567" left-to-right,
    // owner 1's row sits below as "KKK AKQJ10". Rows stack by owner index.
    final byOwner = <int, List<MeldView>>{};
    for (final m in melds) {
      byOwner.putIfAbsent(m.owner, () => <MeldView>[]).add(m);
    }
    final owners = byOwner.keys.toList()..sort();
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 520),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final o in owners)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  for (final m in byOwner[o]!)
                    _MeldRow(
                      meld: m,
                      selected: m.id == selectedId,
                      onTap: () => onTap(m.id),
                    ),
                ],
              ),
            ),
        ],
      ),
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

/// Compact rank chip — gold gradient with ⭐ pips matching level + title.
class _RankPill extends StatelessWidget {
  const _RankPill({required this.rank});
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
              Text(
                '(${rank.nextWins! - rank.wins} ครั้งสู่ ${rank.nextTitle})',
                style: const TextStyle(color: Color(0xFF5A3A06), fontSize: 10),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Opens the history bottom sheet — my recent match outcomes.
Future<void> _openHistory(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: const Color(0xFF12313B),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => const _HistorySheet(),
  );
}

/// Modal sheet listing the player's recent match outcomes with coin deltas.
class _HistorySheet extends ConsumerWidget {
  const _HistorySheet();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final history = ref.watch(coinHistoryProvider);
    final stats = ref.watch(meProvider).value?.stats;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(8, 0, 8, 4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '📜  ประวัติของฉัน',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
            if (stats != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                child: Row(
                  children: [
                    _StatChip(label: 'เล่น', value: '${stats.matchesPlayed}'),
                    const SizedBox(width: 6),
                    _StatChip(label: 'ชนะ', value: '${stats.matchesWon}'),
                    const SizedBox(width: 6),
                    _StatChip(
                      label: 'กำไร',
                      value: '${stats.lifetimeProfit} 🪙',
                      positive: stats.lifetimeProfit >= 0,
                    ),
                  ],
                ),
              ),
            Flexible(
              child: history.when(
                loading: () => const Padding(
                  padding: EdgeInsets.all(24),
                  child: CircularProgressIndicator(),
                ),
                error: (e, _) => Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    'โหลดประวัติไม่ได้: $e',
                    style: const TextStyle(color: Colors.white70),
                  ),
                ),
                data: (list) {
                  if (list.isEmpty) {
                    return const Padding(
                      padding: EdgeInsets.all(24),
                      child: Text(
                        'ยังไม่มีประวัติ — ลองเล่นสักรอบก่อน',
                        style: TextStyle(color: Colors.white60),
                      ),
                    );
                  }
                  return ListView.separated(
                    shrinkWrap: true,
                    padding: const EdgeInsets.all(4),
                    itemCount: list.length,
                    separatorBuilder: (_, i) => const SizedBox(height: 6),
                    itemBuilder: (_, i) => _HistoryRow(row: list[i]),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  const _StatChip({
    required this.label,
    required this.value,
    this.positive = true,
  });
  final String label;
  final String value;
  final bool positive;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$label ',
            style: const TextStyle(color: Colors.white60, fontSize: 12),
          ),
          Text(
            value,
            style: TextStyle(
              color: positive
                  ? const Color(0xFFFFD24A)
                  : const Color(0xFFFF8A8A),
              fontSize: 13,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}

class _HistoryRow extends StatelessWidget {
  const _HistoryRow({required this.row});
  final CoinHistoryRow row;

  @override
  Widget build(BuildContext context) {
    final pos = row.coinDelta >= 0;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(10),
        border: Border(
          left: BorderSide(
            color: pos ? const Color(0xFF6DC94A) : const Color(0xFFC0392B),
            width: 4,
          ),
        ),
      ),
      child: Row(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'เดิมพัน ${row.bet}  •  ${row.isWinner ? "ชนะ" : "แพ้"}',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                _formatTime(row.createdAt),
                style: const TextStyle(color: Colors.white54, fontSize: 11),
              ),
            ],
          ),
          const Spacer(),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${pos ? '+' : ''}${row.coinDelta} 🪙',
                style: TextStyle(
                  color: pos
                      ? const Color(0xFF7FE08A)
                      : const Color(0xFFFF8A8A),
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                'ยอด ${row.balanceAfter}',
                style: const TextStyle(color: Colors.white60, fontSize: 11),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _formatTime(DateTime t) {
    final l = t.toLocal();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${l.year}-${two(l.month)}-${two(l.day)}  ${two(l.hour)}:${two(l.minute)}';
  }
}

/// Opens the coin-shop bottom sheet. Public-ish helper so both the lobby
/// 🛒 icon and the in-game `_ShopButton` can trigger the same flow.
Future<void> _openShop(BuildContext context, WidgetRef ref) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: const Color(0xFF12313B),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => const _ShopSheet(),
  );
}

/// Gold circular shop button with the +120% red badge. Tapping opens the
/// coin shop sheet.
class _ShopButton extends ConsumerWidget {
  const _ShopButton();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SizedBox(
      width: 64,
      height: 64,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          GestureDetector(
            onTap: () => _openShop(context, ref),
            child: Container(
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

/// Modal coin-shop sheet — lists every server-defined package as a tappable
/// card. Payment is currently mocked server-side (always succeeds); the sheet
/// invalidates the wallet provider on success so the pill updates instantly.
class _ShopSheet extends ConsumerStatefulWidget {
  const _ShopSheet();
  @override
  ConsumerState<_ShopSheet> createState() => _ShopSheetState();
}

class _ShopSheetState extends ConsumerState<_ShopSheet> {
  String? _busyPackageId;

  Future<void> _buy(CoinPackage pkg) async {
    final g = ref.read(sessionProvider);
    if (g == null) return;
    setState(() => _busyPackageId = pkg.id);
    try {
      final r = await ref.read(apiClientProvider).purchase(g.token, pkg.id);
      ref.invalidate(meProvider);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('+${r.coinsAdded} 🪙  (ยอดใหม่ ${r.newBalance})'),
          backgroundColor: const Color(0xFF3E8A25),
        ),
      );
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('ซื้อไม่สำเร็จ: $e')));
    } finally {
      if (mounted) setState(() => _busyPackageId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final packages = ref.watch(shopPackagesProvider);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(8, 0, 8, 4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '🛒  ร้านค้าเหรียญ',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(8, 0, 8, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'ตอนนี้ payment เป็น mock — กดซื้อแล้วเหรียญจะเข้าทันที',
                  style: TextStyle(color: Colors.white60, fontSize: 12),
                ),
              ),
            ),
            Flexible(
              child: packages.when(
                loading: () => const Padding(
                  padding: EdgeInsets.all(24),
                  child: CircularProgressIndicator(),
                ),
                error: (e, _) => Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    'โหลดร้านค้าไม่ได้: $e',
                    style: const TextStyle(color: Colors.white70),
                  ),
                ),
                data: (list) => ListView.separated(
                  shrinkWrap: true,
                  padding: const EdgeInsets.all(6),
                  itemCount: list.length,
                  separatorBuilder: (_, i) => const SizedBox(height: 8),
                  itemBuilder: (_, i) => _PackageCard(
                    pkg: list[i],
                    busy: _busyPackageId == list[i].id,
                    onBuy: _buy,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PackageCard extends StatelessWidget {
  const _PackageCard({
    required this.pkg,
    required this.busy,
    required this.onBuy,
  });
  final CoinPackage pkg;
  final bool busy;
  final void Function(CoinPackage) onBuy;

  List<Color> get _bg => switch (pkg.id) {
    'starter' => const [Color(0xFF2D8A6E), Color(0xFF1E6E54)],
    'player' => const [Color(0xFF2D6E9E), Color(0xFF1E4D70)],
    'vip' => const [Color(0xFFB8804A), Color(0xFF8A5A2F)],
    'whale' => const [Color(0xFFE060A8), Color(0xFFA42B72)],
    _ => const [Color(0xFF4A5560), Color(0xFF2A3540)],
  };

  String? get _badgeLabel => switch (pkg.badge) {
    'popular' => 'ฮิตที่สุด',
    'best_value' => 'คุ้มสุด',
    _ => null,
  };

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: busy ? null : () => onBuy(pkg),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: _bg,
            ),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.25),
              width: 1.5,
            ),
            boxShadow: const [
              BoxShadow(
                color: Colors.black54,
                blurRadius: 8,
                offset: Offset(0, 3),
              ),
            ],
          ),
          child: Row(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        pkg.title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (_badgeLabel != null) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 1,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFD24A),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            _badgeLabel!,
                            style: const TextStyle(
                              color: Color(0xFF1A1A1A),
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${pkg.coins} 🪙',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 26,
                      fontWeight: FontWeight.bold,
                      height: 1.1,
                    ),
                  ),
                ],
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Text(
                        '฿${pkg.priceTHB}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
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
