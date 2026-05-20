/// Coin shop wire models.
library;

/// A purchasable bundle of in-game coins, defined by the server.
class CoinPackage {
  const CoinPackage({
    required this.id,
    required this.title,
    required this.coins,
    required this.priceTHB,
    this.badge,
  });
  final String id;
  final String title;
  final int coins;
  final int priceTHB;
  final String? badge; // "popular" / "best_value" / null

  factory CoinPackage.fromJson(Map<String, dynamic> j) => CoinPackage(
    id: j['id'] as String? ?? '',
    title: j['title'] as String? ?? '',
    coins: (j['coins'] as num?)?.toInt() ?? 0,
    priceTHB: (j['price_thb'] as num?)?.toInt() ?? 0,
    badge: j['badge'] as String?,
  );
}
