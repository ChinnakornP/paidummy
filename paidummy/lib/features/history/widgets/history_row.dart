/// One row in the recent-matches list — bet, win/lose, coin delta, time.
library;

import 'package:flutter/material.dart';

import '../../../core/models/index.dart';

class HistoryRow extends StatelessWidget {
  const HistoryRow({super.key, required this.row});
  final CoinHistoryRow row;

  @override
  Widget build(BuildContext context) {
    final pos = row.coinDelta >= 0;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(10),
        border: Border(
          left: BorderSide(
            color: pos ? const Color(0xFF6DC94A) : const Color(0xFFC0392B),
            width: 4,
          ),
        ),
      ),
      child: Row(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'เดิมพัน ${row.bet}  •  ${row.isWinner ? "ชนะ" : "แพ้"}',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                _formatTime(row.createdAt),
                style: const TextStyle(color: Colors.white54, fontSize: 11),
              ),
            ],
          ),
          const Spacer(),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${pos ? '+' : ''}${row.coinDelta} 🪙',
                style: TextStyle(
                  color: pos
                      ? const Color(0xFF7FE08A)
                      : const Color(0xFFFF8A8A),
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                'ยอด ${row.balanceAfter}',
                style: const TextStyle(color: Colors.white60, fontSize: 11),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _formatTime(DateTime t) {
    final l = t.toLocal();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${l.year}-${two(l.month)}-${two(l.day)}  ${two(l.hour)}:${two(l.minute)}';
  }
}
