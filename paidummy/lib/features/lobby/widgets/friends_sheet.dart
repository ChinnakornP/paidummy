/// Friends bottom sheet: add-by-code field, incoming requests, and the
/// accepted friend list. Friendship is keyed off the same 8-char ref code
/// used for referrals.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/index.dart';
import '../../../core/providers/index.dart';

Future<void> showFriendsSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: const Color(0xFF12313B),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => const FriendsSheet(),
  );
}

class FriendsSheet extends ConsumerStatefulWidget {
  const FriendsSheet({super.key});
  @override
  ConsumerState<FriendsSheet> createState() => _FriendsSheetState();
}

class _FriendsSheetState extends ConsumerState<FriendsSheet> {
  final _code = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _add() async {
    final g = ref.read(sessionProvider);
    if (g == null) return;
    final code = _code.text.trim();
    if (code.isEmpty) return;
    setState(() => _busy = true);
    try {
      final auto = await ref.read(apiClientProvider).sendFriendRequest(
            g.token,
            code,
          );
      _code.clear();
      ref.invalidate(friendsProvider);
      ref.invalidate(friendRequestsProvider);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(auto ? 'เป็นเพื่อนกันแล้ว!' : 'ส่งคำขอเป็นเพื่อนแล้ว'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('เพิ่มเพื่อนไม่ได้: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _accept(Friend f) async {
    final g = ref.read(sessionProvider);
    if (g == null) return;
    HapticFeedback.selectionClick();
    try {
      await ref.read(apiClientProvider).acceptFriend(g.token, f.id);
      ref.invalidate(friendsProvider);
      ref.invalidate(friendRequestsProvider);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('ตอบรับไม่ได้: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final friends = ref.watch(friendsProvider);
    final requests = ref.watch(friendRequestsProvider);
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SafeArea(
        child: SizedBox(
          height: 460,
          child: Column(
            children: [
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(top: 8, bottom: 8),
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '👥  เพื่อน',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _code,
                        style: const TextStyle(color: Colors.white),
                        decoration: InputDecoration(
                          hintText: 'ใส่รหัสเพื่อน (8 ตัว)',
                          hintStyle: const TextStyle(color: Colors.white38),
                          filled: true,
                          fillColor: Colors.black.withValues(alpha: 0.3),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 10,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: _busy ? null : _add,
                      child: const Text('เพิ่ม'),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.all(8),
                  children: [
                    ...requests.when(
                      loading: () => const [],
                      error: (_, _) => const [],
                      data: (list) => [
                        if (list.isNotEmpty)
                          const Padding(
                            padding: EdgeInsets.fromLTRB(6, 4, 6, 4),
                            child: Text(
                              'คำขอเป็นเพื่อน',
                              style: TextStyle(
                                color: Color(0xFFFFE7A6),
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        for (final f in list)
                          _FriendTile(
                            friend: f,
                            trailing: FilledButton(
                              onPressed: () => _accept(f),
                              child: const Text('ตอบรับ'),
                            ),
                          ),
                      ],
                    ),
                    const Padding(
                      padding: EdgeInsets.fromLTRB(6, 8, 6, 4),
                      child: Text(
                        'เพื่อนของฉัน',
                        style: TextStyle(
                          color: Color(0xFFFFE7A6),
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    ...friends.when(
                      loading: () => const [
                        Padding(
                          padding: EdgeInsets.all(16),
                          child: Center(child: CircularProgressIndicator()),
                        ),
                      ],
                      error: (e, _) => [
                        Padding(
                          padding: const EdgeInsets.all(12),
                          child: Text(
                            'โหลดรายชื่อไม่ได้: $e',
                            style: const TextStyle(color: Colors.white70),
                          ),
                        ),
                      ],
                      data: (list) => list.isEmpty
                          ? const [
                              Padding(
                                padding: EdgeInsets.all(16),
                                child: Text(
                                  'ยังไม่มีเพื่อน — แชร์รหัสเชิญของคุณสิ',
                                  style: TextStyle(color: Colors.white60),
                                ),
                              ),
                            ]
                          : [for (final f in list) _FriendTile(friend: f)],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FriendTile extends StatelessWidget {
  const _FriendTile({required this.friend, this.trailing});
  final Friend friend;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 3),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Text(friend.avatar, style: const TextStyle(fontSize: 24)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  friend.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  friend.refCode,
                  style: const TextStyle(color: Colors.white38, fontSize: 11),
                ),
              ],
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}
