/// Decorative ♠♥♦♣ glyph drifting behind hero screens (Home + Lobby).
library;

import 'package:flutter/material.dart';

class FloatingSuit extends StatelessWidget {
  const FloatingSuit({
    super.key,
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
