/// Coin-shop modal bottom sheet. Lists every server-defined package as a
/// tappable card. Payment is currently mocked server-side (always succeeds);
/// the sheet invalidates the wallet provider on success so the pill updates
/// instantly.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/index.dart';
import '../../core/providers/index.dart';
import 'widgets/package_card.dart';

/// "ดูโฆษณารับเหรียญ" rewarded-ad button (mock — no real ad SDK). Disabled
/// while on cooldown.
class _WatchAdButton extends ConsumerWidget {
  const _WatchAdButton();

  Future<void> _watch(BuildContext context, WidgetRef ref) async {
    final g = ref.read(sessionProvider);
    if (g == null) return;
    try {
      final r = await ref.read(apiClientProvider).claimAd(g.token);
      ref.invalidate(meProvider);
      ref.invalidate(adStatusProvider);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: const Color(0xFF3E8A25),
          content: Text('ดูโฆษณาจบ — รับ +${r.coinsAdded} 🪙'),
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('ยังรับไม่ได้: $e')));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final st = ref.watch(adStatusProvider).value;
    final available = st?.available ?? false;
    final reward = st?.reward ?? 0;
    return SizedBox(
      width: double.infinity,
      child: FilledButton.icon(
        onPressed: available ? () => _watch(context, ref) : null,
        style: FilledButton.styleFrom(
          backgroundColor: const Color(0xFF3C7A8C),
        ),
        icon: const Icon(Icons.ondemand_video),
        label: Text(
          available ? 'ดูโฆษณารับ +$reward 🪙' : 'รับโฆษณาแล้ว — รออีกครู่',
        ),
      ),
    );
  }
}

/// Opens the coin-shop bottom sheet. Used by the lobby 🛒 icon and the in-game
/// shop button.
Future<void> showShopSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: const Color(0xFF12313B),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => const ShopSheet(),
  );
}

class ShopSheet extends ConsumerStatefulWidget {
  const ShopSheet({super.key});
  @override
  ConsumerState<ShopSheet> createState() => _ShopSheetState();
}

class _ShopSheetState extends ConsumerState<ShopSheet> {
  String? _busyPackageId;

  Future<void> _buy(CoinPackage pkg) async {
    final g = ref.read(sessionProvider);
    if (g == null) return;
    setState(() => _busyPackageId = pkg.id);
    try {
      final r = await ref.read(apiClientProvider).purchase(g.token, pkg.id);
      ref.invalidate(meProvider);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('+${r.coinsAdded} 🪙  (ยอดใหม่ ${r.newBalance})'),
          backgroundColor: const Color(0xFF3E8A25),
        ),
      );
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('ซื้อไม่สำเร็จ: $e')));
    } finally {
      if (mounted) setState(() => _busyPackageId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final packages = ref.watch(shopPackagesProvider);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(8, 0, 8, 4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '🛒  ร้านค้าเหรียญ',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(8, 0, 8, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'ตอนนี้ payment เป็น mock — กดซื้อแล้วเหรียญจะเข้าทันที',
                  style: TextStyle(color: Colors.white60, fontSize: 12),
                ),
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(8, 4, 8, 4),
              child: _WatchAdButton(),
            ),
            Flexible(
              child: packages.when(
                loading: () => const Padding(
                  padding: EdgeInsets.all(24),
                  child: CircularProgressIndicator(),
                ),
                error: (e, _) => Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    'โหลดร้านค้าไม่ได้: $e',
                    style: const TextStyle(color: Colors.white70),
                  ),
                ),
                data: (list) => ListView.separated(
                  shrinkWrap: true,
                  padding: const EdgeInsets.all(6),
                  itemCount: list.length,
                  separatorBuilder: (_, i) => const SizedBox(height: 8),
                  itemBuilder: (_, i) => PackageCard(
                    pkg: list[i],
                    busy: _busyPackageId == list[i].id,
                    onBuy: _buy,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
