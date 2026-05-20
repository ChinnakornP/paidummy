/// Flame rendering of the Thai Dummy felt, styled after game_design_v1.html:
/// dark navy background with two faint radial highlights, a wooden-bordered
/// green felt, decorative vines, a cross divider, the "เดิมพัน | bet" centre
/// label, a left-of-centre pile (deck-back chip + head + discard top), and
/// a dashed refresh circle on the right.
///
/// Seats and the player's hand are Flutter overlays (see ui.dart) — the
/// renderer stays purely server-driven.
library;

import 'package:flame/game.dart';
import 'package:flutter/material.dart';

import 'models.dart';

class TableGame extends FlameGame {
  GameView view = const GameView();

  void setView(GameView v) {
    view = v;
  }

  // game_design_v1.html palette
  static const _bg = Color(0xFF1A3548);
  static const _woodLight = Color(0xFFB8804A);
  static const _woodDark = Color(0xFF8A5A2F);
  static const _feltLight = Color(0xFF2D8053);
  static const _feltDark = Color(0xFF1F5F3D);

  @override
  Color backgroundColor() => _bg;

  Rect get _feltRect {
    final w = size.x * 0.78;
    final h = size.y * 0.62;
    return Rect.fromCenter(
      center: Offset(size.x / 2, size.y / 2 - 12),
      width: w,
      height: h,
    );
  }

  void _drawBackgroundHighlights(Canvas c) {
    void glow(Offset center, double radius) {
      final r = Rect.fromCircle(center: center, radius: radius);
      c.drawRect(
        r,
        Paint()
          ..shader = RadialGradient(
            colors: [
              Colors.white.withValues(alpha: 0.03),
              Colors.white.withValues(alpha: 0.0),
            ],
          ).createShader(r),
      );
    }

    glow(Offset(size.x * 0.2, size.y * 0.3), size.x * 0.4);
    glow(Offset(size.x * 0.8, size.y * 0.7), size.x * 0.4);
  }

  void _drawFelt(Canvas c) {
    final f = _feltRect;
    final outer = RRect.fromRectAndRadius(
      f.inflate(14),
      const Radius.circular(16),
    );
    final inner = RRect.fromRectAndRadius(f, const Radius.circular(8));

    // Drop shadow under the whole table.
    c.drawRRect(
      outer.shift(const Offset(0, 8)),
      Paint()
        ..color = Colors.black.withValues(alpha: 0.45)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 16),
    );
    // Wooden border with a subtle gradient.
    c.drawRRect(
      outer,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [_woodLight, _woodDark, _woodLight],
        ).createShader(outer.outerRect),
    );
    // Green felt with a soft radial gradient.
    c.drawRRect(
      inner,
      Paint()
        ..shader = RadialGradient(
          radius: 0.9,
          colors: const [_feltLight, _feltDark],
        ).createShader(f),
    );
    // Cross divider lines (subtle).
    final guide = Paint()
      ..color = Colors.black.withValues(alpha: 0.15)
      ..strokeWidth = 1;
    c.drawLine(
      Offset(f.center.dx, f.top + f.height * 0.05),
      Offset(f.center.dx, f.bottom - f.height * 0.05),
      guide,
    );
    c.drawLine(
      Offset(f.left + f.width * 0.05, f.center.dy),
      Offset(f.right - f.width * 0.05, f.center.dy),
      guide,
    );
    // Vines at top corners.
    _emoji(c, Offset(f.left + 16, f.top - 18), '🌿', 38, rotate: -0.26);
    _emoji(
      c,
      Offset(f.right - 50, f.top - 18),
      '🌿',
      38,
      rotate: 0.26,
      flipX: true,
    );
  }

  void _emoji(
    Canvas c,
    Offset at,
    String s,
    double size, {
    double rotate = 0,
    bool flipX = false,
  }) {
    final tp = TextPainter(
      text: TextSpan(
        text: s,
        style: TextStyle(fontSize: size),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    c.save();
    c.translate(at.dx + tp.width / 2, at.dy + tp.height / 2);
    if (rotate != 0) c.rotate(rotate);
    if (flipX) c.scale(-1, 1);
    tp.paint(c, Offset(-tp.width / 2, -tp.height / 2));
    c.restore();
  }

  // ---- cards ----
  // Card drawing moved to Flutter overlays (see ui.dart) so cards can be
  // tapped. The flame layer now only paints the felt + decorations.

  void _dashedCircle(Canvas c, Offset center, double radius) {
    final p = Paint()
      ..color = Colors.white.withValues(alpha: 0.3)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    const dashes = 18;
    const total = 360.0;
    final dashAngle = (total / dashes) * 0.55;
    final gapAngle = (total / dashes) - dashAngle;
    var ang = 0.0;
    for (var i = 0; i < dashes; i++) {
      c.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        ang * 3.14159 / 180,
        dashAngle * 3.14159 / 180,
        false,
        p,
      );
      ang += dashAngle + gapAngle;
    }
  }

  @override
  void render(Canvas canvas) {
    super.render(canvas);
    _drawBackgroundHighlights(canvas);
    _drawFelt(canvas);

    final f = _feltRect;
    final cx = f.center.dx, cy = f.center.dy;

    // Centre faint "เดิมพัน | bet" label.
    final betText = TextPainter(
      text: TextSpan(
        children: [
          TextSpan(
            text: 'เดิมพัน',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.5),
              fontSize: 16,
            ),
          ),
          TextSpan(
            text: '  |  ${view.bet}',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.7),
              fontSize: 16,
            ),
          ),
        ],
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    betText.paint(
      canvas,
      Offset(cx - betText.width / 2, cy - betText.height / 2),
    );

    // Decorative dashed refresh circle on the right edge.
    _dashedCircle(canvas, Offset(f.right - 36, cy), 18);

    // Centre pile (deck back + head card + discard pile) is rendered as a
    // Flutter overlay in ui.dart so every discard card can be tapped — flame
    // only paints the felt + decorations here. Table melds are likewise a
    // Flutter overlay (`_MeldsOverlay`).
  }
}
