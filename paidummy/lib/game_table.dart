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
  static const _cardFace = Color(0xFFFFFFFF);
  static const _cardEdge = Color(0xFFCCCCCC);
  static const _red = Color(0xFFD63333);
  static const _black = Color(0xFF1A1A1A);
  static const _backRed = Color(0xFFA82020);
  static const _backRedDark = Color(0xFF8A1818);
  static const _gold = Color(0xFFFFD700);

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

  static const _cardW = 50.0;
  static const _cardH = 70.0;

  void _faceCard(Canvas c, Offset at, String code) {
    final rect = RRect.fromRectAndRadius(
      Rect.fromLTWH(at.dx, at.dy, _cardW, _cardH),
      const Radius.circular(5),
    );
    c.drawRRect(
      rect.shift(const Offset(0, 2)),
      Paint()..color = Colors.black.withValues(alpha: 0.3),
    );
    c.drawRRect(rect, Paint()..color = _cardFace);
    c.drawRRect(
      rect,
      Paint()
        ..color = _cardEdge
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
    if (code.isEmpty || code.length != 2) return;
    final rank = code[0];
    final suit = code[1];
    final isRed = suit == 'H' || suit == 'D';
    final color = isRed ? _red : _black;
    final suitGlyph = switch (suit) {
      'H' => '♥',
      'D' => '♦',
      'S' => '♠',
      _ => '♣',
    };
    final rankTp = TextPainter(
      text: TextSpan(
        text: rank == 'T' ? '10' : rank,
        style: TextStyle(
          color: color,
          fontSize: 16,
          fontWeight: FontWeight.bold,
          fontFamily: 'Georgia',
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    rankTp.paint(c, Offset(at.dx + 4, at.dy + 4));
    final suitTp = TextPainter(
      text: TextSpan(
        text: suitGlyph,
        style: TextStyle(color: color, fontSize: 22, fontFamily: 'Georgia'),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    suitTp.paint(c, Offset(at.dx + 4, at.dy + 22));
  }

  /// Red diagonal-stripe card back with optional centre number (deck count)
  /// and a small gold ⭐ in the bottom-left.
  void _backCard(Canvas c, Offset at, {String? centre}) {
    final rect = Rect.fromLTWH(at.dx, at.dy, _cardW, _cardH);
    final rr = RRect.fromRectAndRadius(rect, const Radius.circular(5));
    c.drawRRect(
      RRect.fromRectAndRadius(
        rect.shift(const Offset(0, 2)),
        const Radius.circular(5),
      ),
      Paint()..color = Colors.black.withValues(alpha: 0.3),
    );
    c.drawRRect(rr, Paint()..color = _backRed);
    c.save();
    c.clipRRect(rr);
    final stripe = Paint()..color = _backRedDark;
    for (double i = -_cardH; i < _cardW + _cardH; i += 8) {
      final p = Path()
        ..moveTo(at.dx + i, at.dy)
        ..lineTo(at.dx + i + 4, at.dy)
        ..lineTo(at.dx + i + 4 + _cardH, at.dy + _cardH)
        ..lineTo(at.dx + i + _cardH, at.dy + _cardH)
        ..close();
      c.drawPath(p, stripe);
    }
    c.restore();
    c.drawRRect(
      rr.deflate(1),
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
    if (centre != null) {
      final tp = TextPainter(
        text: TextSpan(
          text: centre,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(
        c,
        Offset(
          at.dx + (_cardW - tp.width) / 2,
          at.dy + (_cardH - tp.height) / 2,
        ),
      );
    }
    final star = TextPainter(
      text: const TextSpan(
        text: '⭐',
        style: TextStyle(color: _gold, fontSize: 10),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    star.paint(c, Offset(at.dx + 5, at.dy + _cardH - star.height - 4));
  }

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

    // Left chip: deck-back with remaining draw count, then the face-up head
    // card immediately next to it.
    final pileY = cy - _cardH / 2;
    var px = f.left + 32;
    _backCard(canvas, Offset(px, pileY), centre: '${view.drawCount}');
    px += _cardW - 28;
    if (view.headCard.isNotEmpty) {
      _faceCard(canvas, Offset(px, pileY), view.headCard);
    }

    // Discard pile (ทิ้ง): every discarded card lined up oldest→newest with
    // adaptive overlap so a long pile still fits the felt.
    final pile = view.discardPile;
    if (pile.isNotEmpty) {
      final discardStart = px + _cardW + 12;
      final availableW = f.right - discardStart - 14;
      const naturalStep = 22.0; // matches game_design_v1.html overlap (-28)
      final step = pile.length > 1
          ? (availableW - _cardW) / (pile.length - 1)
          : 0.0;
      final useStep = (step > 0 && step < naturalStep) ? step : naturalStep;
      for (var i = 0; i < pile.length; i++) {
        _faceCard(canvas, Offset(discardStart + i * useStep, pileY), pile[i]);
      }
    }
    // Note: table melds are rendered as a Flutter overlay (see _MeldsOverlay
    // in ui.dart) so each meld is tappable for layoff ("ฝาก") UX.
  }
}
