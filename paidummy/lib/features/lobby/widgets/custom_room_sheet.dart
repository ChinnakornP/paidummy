/// "สร้างห้องเอง" bottom sheet — exposes the few RuleSet knobs the spec
/// flagged as room-configurable (target score, turn timer, max seats) plus
/// an optional password. On submit it creates the room, seats the host,
/// and pushes the player into currentRoomProvider.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/index.dart';

Future<void> showCustomRoomSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: const Color(0xFF12313B),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => const CustomRoomSheet(),
  );
}

class CustomRoomSheet extends ConsumerStatefulWidget {
  const CustomRoomSheet({super.key});
  @override
  ConsumerState<CustomRoomSheet> createState() => _CustomRoomSheetState();
}

class _CustomRoomSheetState extends ConsumerState<CustomRoomSheet> {
  final _name = TextEditingController();
  final _password = TextEditingController();
  int _maxPlayers = 4;
  int _target = 100;
  int _bet = 100;
  int _turnSec = 60;
  int _minMeld = 3;
  String _botLevel = 'normal';
  bool _busy = false;

  static const _targetOptions = [50, 100, 200, 500];
  static const _turnOptions = [30, 60, 90];
  static const _betOptions = [0, 50, 100, 500, 1000];
  static const _meldOptions = [3, 4];

  @override
  void dispose() {
    _name.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final g = ref.read(sessionProvider);
    if (g == null) return;
    setState(() => _busy = true);
    try {
      final r = await ref.read(apiClientProvider).createRoom(
            g.token,
            name: _name.text.trim().isEmpty
                ? '${g.name} room'
                : _name.text.trim(),
            maxPlayers: _maxPlayers,
            targetScore: _target,
            bet: _bet,
            turnTimerSec: _turnSec,
            password: _password.text,
            minMeldLen: _minMeld,
            botLevel: _botLevel,
          );
      ref.read(currentRoomProvider.notifier).state = r.id;
      if (!mounted) return;
      if (r.password.isNotEmpty) {
        // Surface the room id + password as a copyable share string so the
        // host can paste it to friends before the round starts.
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            duration: const Duration(seconds: 6),
            backgroundColor: const Color(0xFF1B4350),
            content: Text(
              'ห้องส่วนตัวพร้อมแล้ว — ID ${r.id}  ·  รหัส ${r.password}',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        );
      }
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('สร้างห้องไม่ได้: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 8),
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '🛠  สร้างห้องเอง',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              _labelled(
                'ชื่อห้อง (ไม่บังคับ)',
                TextField(
                  controller: _name,
                  style: const TextStyle(color: Colors.white),
                  decoration: _input('My table'),
                ),
              ),
              _labelled(
                'รหัสห้อง (ใส่เพื่อทำเป็นห้องส่วนตัว)',
                TextField(
                  controller: _password,
                  style: const TextStyle(color: Colors.white),
                  decoration: _input('ปล่อยว่างถ้าให้ใครก็เข้าได้'),
                ),
              ),
              _labelled(
                'จำนวนผู้เล่นสูงสุด',
                _chipRow(
                  values: const [2, 3, 4],
                  selected: _maxPlayers,
                  onPick: (v) => setState(() => _maxPlayers = v),
                ),
              ),
              _labelled(
                'คะแนนจบเกม',
                _chipRow(
                  values: _targetOptions,
                  selected: _target,
                  onPick: (v) => setState(() => _target = v),
                ),
              ),
              _labelled(
                'เวลา/ตา (วินาที)',
                _chipRow(
                  values: _turnOptions,
                  selected: _turnSec,
                  onPick: (v) => setState(() => _turnSec = v),
                ),
              ),
              _labelled(
                'เดิมพัน (🪙)',
                _chipRow(
                  values: _betOptions,
                  selected: _bet,
                  labelFor: (v) => v == 0 ? 'ไม่เดิมพัน' : '$v',
                  onPick: (v) => setState(() => _bet = v),
                ),
              ),
              _labelled(
                'ขนาดชุดขั้นต่ำ (variant)',
                _chipRow(
                  values: _meldOptions,
                  selected: _minMeld,
                  labelFor: (v) => '$v ใบ',
                  onPick: (v) => setState(() => _minMeld = v),
                ),
              ),
              _labelled(
                'ระดับบอท',
                Wrap(
                  spacing: 6,
                  children: [
                    for (final (id, label) in const [
                      ('easy', 'ง่าย'),
                      ('normal', 'ปานกลาง'),
                      ('hard', 'ยาก'),
                    ])
                      ChoiceChip(
                        label: Text(label),
                        selected: _botLevel == id,
                        onSelected: (_) => setState(() => _botLevel = id),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _busy ? null : _submit,
                icon: _busy
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.check),
                label: const Text('สร้างห้อง'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _labelled(String label, Widget field) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFFFFE7A6),
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          field,
        ],
      ),
    );
  }

  Widget _chipRow({
    required List<int> values,
    required int selected,
    required void Function(int) onPick,
    String Function(int)? labelFor,
  }) {
    return Wrap(
      spacing: 6,
      runSpacing: 4,
      children: [
        for (final v in values)
          ChoiceChip(
            label: Text(labelFor?.call(v) ?? '$v'),
            selected: v == selected,
            onSelected: (_) => onPick(v),
            selectedColor: const Color(0xFFFFD24A),
            backgroundColor: Colors.black.withValues(alpha: 0.3),
            labelStyle: TextStyle(
              color: v == selected ? const Color(0xFF1A1A1A) : Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
      ],
    );
  }

  InputDecoration _input(String hint) => InputDecoration(
    hintText: hint,
    hintStyle: const TextStyle(color: Colors.white38),
    filled: true,
    fillColor: Colors.black.withValues(alpha: 0.3),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: BorderSide.none,
    ),
    contentPadding:
        const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
  );
}
