/// Shared felt-table background used by Home, Lobby, and Game. Reads the
/// active cosmetic theme from feltThemeProvider so a skin change recolours
/// every screen at once.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/felt_theme.dart';

class FeltBackground extends ConsumerWidget {
  const FeltBackground({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = ref.watch(feltThemeProvider);
    return Container(
      decoration: BoxDecoration(
        gradient: RadialGradient(
          center: Alignment.center,
          radius: 1.1,
          colors: [p.centre, p.mid, p.outer],
          stops: const [0.0, 0.55, 1.0],
        ),
      ),
      child: CustomPaint(
        size: Size.infinite,
        painter: FeltSheenPainter(),
      ),
    );
  }
}

/// Subtle diagonal sheen on top of the felt to suggest a light source — keeps
/// the painted background from looking flat.
class FeltSheenPainter extends CustomPainter {
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
