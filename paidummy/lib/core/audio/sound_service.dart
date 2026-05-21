/// Lightweight sound-effect service. Each effect maps to an asset under
/// `assets/sounds/`. The shipped asset files are empty 0-byte placeholders,
/// so every play() is wrapped in a try/catch and failures are swallowed —
/// the game runs silently until real audio is dropped in (same filenames).
///
/// Toggle all SFX with [SoundService.enabled]. A single shared AudioPlayer
/// would clip rapid repeats, so we round-robin a tiny pool fire-and-forget.
library;

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

enum Sfx {
  cardFlip('card_flip.mp3'),
  deal('deal.mp3'),
  draw('draw.mp3'),
  discard('discard.mp3'),
  meld('meld.mp3'),
  layoff('layoff.mp3'),
  knock('knock.mp3'),
  win('win.mp3'),
  lose('lose.mp3'),
  button('button.mp3'),
  coin('coin.mp3'),
  countdown('countdown.mp3');

  const Sfx(this.asset);
  final String asset;
}

class SoundService {
  SoundService();

  bool enabled = true;

  // A small ring of players so two quick effects don't cut each other off.
  final List<AudioPlayer> _pool = List.generate(4, (_) => AudioPlayer());
  int _next = 0;

  /// Fire-and-forget. Never throws — a missing/empty/corrupt asset just
  /// produces no sound.
  Future<void> play(Sfx sfx) async {
    if (!enabled) return;
    final player = _pool[_next];
    _next = (_next + 1) % _pool.length;
    try {
      await player.stop();
      await player.play(AssetSource('sounds/${sfx.asset}'));
    } catch (e) {
      // Empty placeholder assets fail to decode — that's expected today.
      if (kDebugMode) {
        debugPrint('SoundService: skipped ${sfx.asset} ($e)');
      }
    }
  }

  void dispose() {
    for (final p in _pool) {
      p.dispose();
    }
  }
}

/// App-wide SFX service. Not autoDispose so the player pool survives screen
/// changes.
final soundServiceProvider = Provider<SoundService>((ref) {
  final s = SoundService();
  ref.onDispose(s.dispose);
  return s;
});
