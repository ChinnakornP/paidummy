/// "ไพ่ดัมมี่" wordmark stack — gold-gradient Thai title above the english
/// kicker. Used only by the home screen.
library;

import 'package:flutter/material.dart';

class HomeLogo extends StatelessWidget {
  const HomeLogo({super.key});
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
