/// Guest sign-in screen — the first thing a player sees. Painted felt + four
/// drifting suit glyphs + a centre column with logo / entry card / footer.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/analytics/analytics_service.dart';
import '../../core/i18n/strings.dart';
import '../../core/providers/index.dart';
import '../../shared/widgets/index.dart';
import '../tutorial/tutorial_sheet.dart';
import 'widgets/index.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});
  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  final _name = TextEditingController(text: 'Player');
  final _ref = TextEditingController();
  bool _busy = false;
  bool _showRefField = false;

  @override
  void dispose() {
    _name.dispose();
    _ref.dispose();
    super.dispose();
  }

  Future<void> _enter() async {
    setState(() => _busy = true);
    try {
      await ref
          .read(sessionProvider.notifier)
          .createGuest(_name.text, ref: _ref.text);
      ref.read(analyticsProvider).event('guest_sign_in', {
        'referred': _ref.text.trim().isNotEmpty,
      });
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
          const Positioned.fill(child: FeltBackground()),
          // Decorative card-suit motifs scattered in the corners; they sit
          // behind the entry card and are intentionally low-contrast so they
          // never compete with the input controls.
          const Positioned(
            left: 20,
            top: 60,
            child: FloatingSuit(glyph: '♠', color: Color(0x331A1A1A), size: 110),
          ),
          const Positioned(
            right: 24,
            top: 110,
            child: FloatingSuit(glyph: '♥', color: Color(0x33D63333), size: 96),
          ),
          const Positioned(
            left: 36,
            bottom: 70,
            child: FloatingSuit(glyph: '♦', color: Color(0x33D63333), size: 92),
          ),
          const Positioned(
            right: 40,
            bottom: 110,
            child: FloatingSuit(glyph: '♣', color: Color(0x331A1A1A), size: 100),
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
                      const HomeLogo(),
                      const SizedBox(height: 28),
                      EntryCard(
                        nameController: _name,
                        busy: _busy,
                        onSubmit: _enter,
                        refController: _ref,
                        showRef: _showRefField,
                        onToggleRef: () => setState(
                          () => _showRefField = !_showRefField,
                        ),
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
                      const SizedBox(height: 6),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          TextButton.icon(
                            onPressed: () => showTutorial(context),
                            icon: const Icon(Icons.help_outline,
                                color: Color(0xFFFFE7A6), size: 18),
                            label: Text(
                              ref.t('how_to_play'),
                              style: const TextStyle(color: Color(0xFFFFE7A6)),
                            ),
                          ),
                          // Language toggle (th ⇄ en).
                          TextButton(
                            onPressed: () {
                              final cur = ref.read(localeProvider);
                              ref.read(localeProvider.notifier).state =
                                  cur.languageCode == 'th'
                                      ? const Locale('en')
                                      : const Locale('th');
                            },
                            child: Text(
                              ref.watch(localeProvider).languageCode == 'th'
                                  ? '🇹🇭 ไทย'
                                  : '🇬🇧 EN',
                              style: const TextStyle(color: Color(0xFFFFE7A6)),
                            ),
                          ),
                        ],
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
