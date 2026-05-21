/// "เข้าด้วยรหัส" — manual join flow for private rooms. Two fields (room
/// id + password); on submit it calls Join and pushes the player into the
/// matched room.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/index.dart';

Future<void> showJoinByCodeDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (_) => const JoinByCodeDialog(),
  );
}

class JoinByCodeDialog extends ConsumerStatefulWidget {
  const JoinByCodeDialog({super.key});
  @override
  ConsumerState<JoinByCodeDialog> createState() => _JoinByCodeDialogState();
}

class _JoinByCodeDialogState extends ConsumerState<JoinByCodeDialog> {
  final _roomId = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  bool _spectate = false;

  @override
  void dispose() {
    _roomId.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final g = ref.read(sessionProvider);
    if (g == null) return;
    final id = _roomId.text.trim();
    if (id.isEmpty) return;
    setState(() => _busy = true);
    try {
      // Spectators attach over the WS only; no REST seat join.
      if (_spectate) {
        ref.read(spectatingProvider.notifier).state = true;
        ref.read(currentRoomProvider.notifier).state = id;
        if (!mounted) return;
        Navigator.of(context).pop();
        return;
      }
      await ref.read(apiClientProvider).joinRoom(
            g.token,
            id,
            password: _password.text,
          );
      ref.read(spectatingProvider.notifier).state = false;
      ref.read(currentRoomProvider.notifier).state = id;
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('เข้าห้องไม่ได้: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF0F2E22),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      title: const Text('🔑  เข้าด้วยรหัสห้อง'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _roomId,
              autofocus: true,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                labelText: 'รหัสห้อง',
                hintText: 'วาง room id ที่ได้รับ',
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _password,
              obscureText: true,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                labelText: 'รหัสผ่าน (ถ้ามี)',
              ),
            ),
            const SizedBox(height: 4),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              value: _spectate,
              onChanged: (v) => setState(() => _spectate = v),
              title: const Text(
                '👁 ดูอย่างเดียว (ไม่ลงเล่น)',
                style: TextStyle(color: Colors.white, fontSize: 13),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: const Text('ยกเลิก'),
        ),
        FilledButton(
          onPressed: _busy ? null : _submit,
          child: _busy
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Text('เข้าห้อง'),
        ),
      ],
    );
  }
}
