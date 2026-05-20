/// Top-bar pill that shows the player's referral code and copies it to the
/// clipboard on tap. Pairs with the home-screen "มีรหัสเชิญจากเพื่อน?"
/// field — when a referred guest finishes their first match the server
/// credits both wallets with +500 🪙.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/index.dart';

class RefCodeButton extends ConsumerWidget {
  const RefCodeButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final code = ref.watch(meProvider).value?.refCode ?? '';
    if (code.isEmpty) return const SizedBox.shrink();
    return Tooltip(
      message: 'แตะเพื่อคัดลอกรหัสเชิญ — ทั้งคู่ได้ +500 🪙 หลังเพื่อนเล่นจบนัดแรก',
      child: Material(
        color: Colors.black.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () async {
            await Clipboard.setData(ClipboardData(text: code));
            HapticFeedback.selectionClick();
            if (!context.mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                duration: const Duration(seconds: 2),
                content: Text('คัดลอกรหัสเชิญ $code แล้ว'),
              ),
            );
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('📎 ', style: TextStyle(fontSize: 14)),
                Text(
                  code,
                  style: const TextStyle(
                    color: Color(0xFFFFE7A6),
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                    letterSpacing: 0.6,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
