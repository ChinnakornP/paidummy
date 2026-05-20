/// One shop package row — title + coin count + price + buy CTA.
library;

import 'package:flutter/material.dart';

import '../../../core/models/index.dart';

class PackageCard extends StatelessWidget {
  const PackageCard({
    super.key,
    required this.pkg,
    required this.busy,
    required this.onBuy,
  });
  final CoinPackage pkg;
  final bool busy;
  final void Function(CoinPackage) onBuy;

  List<Color> get _bg => switch (pkg.id) {
    'starter' => const [Color(0xFF2D8A6E), Color(0xFF1E6E54)],
    'player' => const [Color(0xFF2D6E9E), Color(0xFF1E4D70)],
    'vip' => const [Color(0xFFB8804A), Color(0xFF8A5A2F)],
    'whale' => const [Color(0xFFE060A8), Color(0xFFA42B72)],
    _ => const [Color(0xFF4A5560), Color(0xFF2A3540)],
  };

  String? get _badgeLabel => switch (pkg.badge) {
    'popular' => 'ฮิตที่สุด',
    'best_value' => 'คุ้มสุด',
    _ => null,
  };

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: busy ? null : () => onBuy(pkg),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: _bg,
            ),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.25),
              width: 1.5,
            ),
            boxShadow: const [
              BoxShadow(
                color: Colors.black54,
                blurRadius: 8,
                offset: Offset(0, 3),
              ),
            ],
          ),
          child: Row(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        pkg.title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (_badgeLabel != null) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 1,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFD24A),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            _badgeLabel!,
                            style: const TextStyle(
                              color: Color(0xFF1A1A1A),
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${pkg.coins} 🪙',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 26,
                      fontWeight: FontWeight.bold,
                      height: 1.1,
                    ),
                  ),
                ],
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Text(
                        '฿${pkg.priceTHB}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
