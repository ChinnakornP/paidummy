/// Lobby is now server-managed: no manual create, no room list. The player
/// picks a bet tier; the server finds (or creates) the nearest open room.
/// Tiers locked when the wallet is short — coin guard enforced server-side
/// too, the UI just disables the card.
library;

import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/index.dart';
import '../../core/providers/index.dart';
import '../../shared/widgets/index.dart';
import '../history/history_sheet.dart';
import '../shop/shop_sheet.dart';
import 'widgets/index.dart';

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
      // Felt + vignette background matches the home screen so home → lobby
      // feels like one continuous game world.
      body: Stack(
        children: [
          const Positioned.fill(child: FeltBackground()),
          // Decorative suit motifs anchor the screen visually without
          // competing with the tier list.
          const Positioned(
            right: -10,
            top: 100,
            child: FloatingSuit(glyph: '♦', color: Color(0x22D63333), size: 140),
          ),
          const Positioned(
            left: -16,
            bottom: 40,
            child: FloatingSuit(glyph: '♣', color: Color(0x221A1A1A), size: 160),
          ),
          SafeArea(
            child: Column(
              children: [
                LobbyTopBar(
                  name: g?.name ?? '',
                  rank: rank,
                  coins: coins,
                  walletLoading: me.isLoading,
                  onWalletTap: () => ref.invalidate(meProvider),
                  onHistory: () => showHistorySheet(context),
                  onShop: () => showShopSheet(context),
                  onSignOut: () =>
                      ref.read(sessionProvider.notifier).signOut(),
                ),
                const LobbySectionHeader(),
                Expanded(
                  child: tiers.when(
                    loading: () => const Center(
                      child: CircularProgressIndicator(
                        valueColor:
                            AlwaysStoppedAnimation(Color(0xFFFFD24A)),
                      ),
                    ),
                    error: (e, _) => Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          'โหลดรายการเดิมพันไม่ได้\n$e',
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.white70),
                        ),
                      ),
                    ),
                    data: (list) => ScrollConfiguration(
                      // BouncingScrollPhysics gives a proper momentum fling
                      // on every platform; the multi-device behavior lets
                      // the user drag with a mouse / trackpad on web and
                      // desktop too (default would be touch-only).
                      behavior: const _LobbyScrollBehavior(),
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        physics: const BouncingScrollPhysics(
                          parent: AlwaysScrollableScrollPhysics(),
                        ),
                        padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                        itemCount: list.length,
                        separatorBuilder: (_, i) => const SizedBox(width: 14),
                        itemBuilder: (_, i) => TierCard(
                          tier: list[i],
                          coins: coins,
                          onEnter: () =>
                              _enterTier(context, ref, list[i].bet),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Enables mouse + trackpad drag-to-scroll in addition to touch + stylus so
/// the horizontal tier list flings smoothly on web and desktop too. The
/// default `MaterialScrollBehavior` only treats touch as a drag device,
/// which is why a mouse-down/up on the lobby would "stick" without inertia.
class _LobbyScrollBehavior extends MaterialScrollBehavior {
  const _LobbyScrollBehavior();
  @override
  Set<PointerDeviceKind> get dragDevices => const {
    PointerDeviceKind.touch,
    PointerDeviceKind.mouse,
    PointerDeviceKind.trackpad,
    PointerDeviceKind.stylus,
    PointerDeviceKind.invertedStylus,
  };
}
