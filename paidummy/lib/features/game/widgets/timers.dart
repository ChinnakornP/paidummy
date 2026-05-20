/// Self-ticking countdown / shot-clock chips and the "waiting for other
/// players" banner. Re-renders stay local to these widgets instead of
/// rebuilding the whole game screen each tick.
library;

import 'dart:async';

import 'package:flutter/material.dart';

/// Live auto-start countdown. Self-ticks once per second from a fixed
/// server-provided deadline (unix ms), so re-renders stay local.
class CountdownChip extends StatefulWidget {
  const CountdownChip({super.key, required this.endMs});
  final int endMs;
  @override
  State<CountdownChip> createState() => _CountdownChipState();
}

class _CountdownChipState extends State<CountdownChip> {
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
class TurnTimerChip extends StatefulWidget {
  const TurnTimerChip({
    super.key,
    required this.endMs,
    required this.isMyTurn,
    required this.turnName,
  });
  final int endMs;
  final bool isMyTurn;
  final String turnName;
  @override
  State<TurnTimerChip> createState() => _TurnTimerChipState();
}

class _TurnTimerChipState extends State<TurnTimerChip> {
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

/// Subtle "waiting for other players" chip shown when it's not your turn.
class WaitingBanner extends StatelessWidget {
  const WaitingBanner({super.key});
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
