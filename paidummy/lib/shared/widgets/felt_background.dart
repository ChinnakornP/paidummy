/// Shared felt-table background used by Home, Lobby, and Game.
library;

import 'package:flutter/material.dart';

class FeltBackground extends StatelessWidget {
  const FeltBackground({super.key});
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
