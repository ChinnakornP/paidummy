/// Round / match end dialog body: per-player score, melds laid, remaining
/// hand cards, full score breakdown and the coin settlement.
library;

import 'package:flutter/material.dart';

/// Readable round/match summary: per-player score, and (on match end) the
/// coin settlement — winner takes the pot, losers pay the bet.
class ResultBody extends StatelessWidget {
  const ResultBody({super.key, required this.result, required this.isMatch});
  final Map<String, dynamic> result;
  final bool isMatch;

  @override
  Widget build(BuildContext context) {
    final rows = ((result['rows'] ?? result['scores']) as List? ?? const [])
        .cast<Map<String, dynamic>>();
    final reason = result['reason'] as String? ?? '';
    final knocker = (result['knocker'] as num?)?.toInt() ?? -1;
    String? subtitle;
    if (isMatch && result['winner'] != null) {
      subtitle = 'ผู้ชนะแมตช์: ${result['winner']}  '
          '(เดิมพัน ${result['bet'] ?? 0})';
    } else {
      if (reason == 'knock') {
        final name =
            (knocker >= 0 && knocker < rows.length)
                ? rows[knocker]['name']
                : null;
        subtitle = name != null ? 'น็อคโดย $name' : 'จบด้วยการน็อค';
      } else if (reason == 'deck_exhaust') {
        subtitle = 'ไพ่กองหมด';
      }
    }

    // Landscape phones get four columns side-by-side; if it overflows we
    // fall back to a vertical scroll. ConstrainedBox keeps the dialog from
    // hugging the screen edge to edge.
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 720, maxHeight: 460),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (subtitle != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Text(
                  subtitle,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                ),
              ),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final r in rows) _PlayerSummary(row: r),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Per-player end-of-round panel: melds laid, remaining hand cards, full
/// score breakdown line items, and the coin/score delta in green / red.
class _PlayerSummary extends StatelessWidget {
  const _PlayerSummary({required this.row});
  final Map<String, dynamic> row;

  @override
  Widget build(BuildContext context) {
    final name = row['name'] as String? ?? '';
    final total = (row['total'] as num?)?.toInt() ?? 0;
    final coinDelta = (row['coin_delta'] as num?)?.toInt();
    final isWinner = row['winner'] == true;
    final melds = ((row['melds'] as List?) ?? const [])
        .cast<Map<String, dynamic>>();
    final hand = ((row['hand'] as List?) ?? const [])
        .map((e) => e as String)
        .toList();

    final breakdown = <_LineItem>[
      _LineItem('แต้มไพ่ที่ลง', (row['meld_points'] as num?)?.toInt() ?? 0),
      if (((row['head_bonus'] as num?)?.toInt() ?? 0) != 0)
        _LineItem('โบนัสหัว', (row['head_bonus'] as num?)!.toInt()),
      if (((row['knock_bonus'] as num?)?.toInt() ?? 0) != 0)
        _LineItem('โบนัสน็อค', (row['knock_bonus'] as num?)!.toInt()),
      if (((row['knock_card_bonus'] as num?)?.toInt() ?? 0) != 0)
        _LineItem('ไพ่น็อค', (row['knock_card_bonus'] as num?)!.toInt()),
      if (((row['hand_penalty'] as num?)?.toInt() ?? 0) != 0)
        _LineItem('ค่าไพ่ในมือ', (row['hand_penalty'] as num?)!.toInt()),
      if (((row['dump_penalty'] as num?)?.toInt() ?? 0) != 0)
        _LineItem(
          'ทิ้งเต็ม / ดัมมี่',
          (row['dump_penalty'] as num?)!.toInt(),
        ),
    ];

    return Container(
      width: 220,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: const Color(0xFF0F2E22).withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isWinner
              ? const Color(0xFFFFD24A)
              : Colors.white.withValues(alpha: 0.12),
          width: isWinner ? 1.6 : 1,
        ),
        boxShadow: isWinner
            ? const [BoxShadow(color: Color(0x66FFD24A), blurRadius: 14)]
            : null,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (isWinner)
                const Padding(
                  padding: EdgeInsets.only(right: 4),
                  child: Text('🏆', style: TextStyle(fontSize: 16)),
                ),
              Expanded(
                child: Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                  ),
                ),
              ),
              Text(
                '$total',
                style: TextStyle(
                  color: total >= 0
                      ? const Color(0xFF7FE08A)
                      : const Color(0xFFFF8A8A),
                  fontWeight: FontWeight.w900,
                  fontSize: 18,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const _SummaryLabel('ไพ่ที่ลง'),
          if (melds.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 2, bottom: 6),
              child: Text(
                '—',
                style: TextStyle(color: Colors.white38, fontSize: 12),
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.only(top: 4, bottom: 6),
              child: Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  for (final m in melds)
                    _SummaryMeld(
                      cards:
                          ((m['cards'] as List?) ?? const [])
                              .map((e) => e as String)
                              .toList(),
                    ),
                ],
              ),
            ),
          const _SummaryLabel('ไพ่ที่เหลือในมือ'),
          if (hand.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 2, bottom: 6),
              child: Text(
                '—',
                style: TextStyle(color: Colors.white38, fontSize: 12),
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.only(top: 4, bottom: 6),
              child: Wrap(
                spacing: 3,
                runSpacing: 3,
                children: [for (final c in hand) _SummaryCard(label: c)],
              ),
            ),
          const _SummaryLabel('สรุปคะแนน'),
          const SizedBox(height: 2),
          for (final item in breakdown)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 1),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      item.label,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  Text(
                    '${item.value >= 0 ? '+' : ''}${item.value}',
                    style: TextStyle(
                      color: item.value >= 0
                          ? const Color(0xFFB6E8B6)
                          : const Color(0xFFFFB4B4),
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          if (coinDelta != null) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'เหรียญ',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Text(
                  '${coinDelta >= 0 ? '+' : ''}$coinDelta 🪙',
                  style: TextStyle(
                    color: coinDelta >= 0
                        ? const Color(0xFFFFD24A)
                        : const Color(0xFFFF8A8A),
                    fontWeight: FontWeight.w900,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _LineItem {
  const _LineItem(this.label, this.value);
  final String label;
  final int value;
}

class _SummaryLabel extends StatelessWidget {
  const _SummaryLabel(this.label);
  final String label;
  @override
  Widget build(BuildContext context) => Text(
    label,
    style: const TextStyle(
      color: Color(0xFFFFE7A6),
      fontSize: 11,
      fontWeight: FontWeight.w700,
      letterSpacing: 0.4,
    ),
  );
}

/// Small face-up card used inside the result dialog (hand + melds).
class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.label});
  final String label;
  @override
  Widget build(BuildContext context) {
    if (label.length < 2) return const SizedBox(width: 22, height: 30);
    final rank = label[0] == 'T' ? '10' : label[0];
    final suit = label[1];
    final isRed = suit == 'H' || suit == 'D';
    final color = isRed ? const Color(0xFFD63333) : const Color(0xFF1A1A1A);
    final glyph = switch (suit) {
      'H' => '♥',
      'D' => '♦',
      'S' => '♠',
      _ => '♣',
    };
    return Container(
      width: 22,
      height: 30,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(3),
        border: Border.all(color: const Color(0xFFCCCCCC)),
      ),
      alignment: Alignment.center,
      child: FittedBox(
        child: Text(
          '$rank$glyph',
          style: TextStyle(
            color: color,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

/// Compact horizontal stack of mini cards representing one laid meld.
class _SummaryMeld extends StatelessWidget {
  const _SummaryMeld({required this.cards});
  final List<String> cards;
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final c in cards)
            Padding(
              padding: const EdgeInsets.only(right: 2),
              child: _SummaryCard(label: c),
            ),
        ],
      ),
    );
  }
}
