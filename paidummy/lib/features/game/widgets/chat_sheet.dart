/// Modal chat sheet — slides up from the bottom of the game screen. Bound
/// to the WS `chat` envelope so messages from other seats stream in live.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/index.dart';
import '../../../core/providers/index.dart';

Future<void> showChatSheet(BuildContext context, WidgetRef ref) {
  // Clear the unread badge as soon as the user opens the sheet so the dot
  // disappears even before they scroll through new messages.
  ref.read(gameControllerProvider.notifier).clearChatUnread();
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: const Color(0xFF12313B),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => const ChatSheet(),
  );
}

class ChatSheet extends ConsumerStatefulWidget {
  const ChatSheet({super.key});
  @override
  ConsumerState<ChatSheet> createState() => _ChatSheetState();
}

class _ChatSheetState extends ConsumerState<ChatSheet> {
  final _input = TextEditingController();
  final _scroll = ScrollController();

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _send() {
    final t = _input.text;
    if (t.trim().isEmpty) return;
    ref.read(gameControllerProvider.notifier).sendChat(t);
    _input.clear();
    // Defer scroll to after the new message bubble lands.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final view = ref.watch(gameControllerProvider);
    final mySeat = view.yourSeat;
    // Auto-scroll to the bottom when new messages arrive while the sheet
    // is open.
    ref.listen(
      gameControllerProvider.select((v) => v.chatMessages.length),
      (_, _) {
        ref.read(gameControllerProvider.notifier).clearChatUnread();
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!_scroll.hasClients) return;
          _scroll.animateTo(
            _scroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
          );
        });
      },
    );

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SafeArea(
        child: SizedBox(
          height: 360,
          child: Column(
            children: [
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(top: 8, bottom: 4),
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '💬  แชทในห้อง',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
              Expanded(
                child: view.chatMessages.isEmpty
                    ? const Center(
                        child: Text(
                          'ยังไม่มีข้อความ — ทักทายเพื่อนร่วมโต๊ะก่อนเลย',
                          style: TextStyle(color: Colors.white54),
                        ),
                      )
                    : ListView.builder(
                        controller: _scroll,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 4,
                        ),
                        itemCount: view.chatMessages.length,
                        itemBuilder: (_, i) {
                          final m = view.chatMessages[i];
                          final isMine = m.seat == mySeat;
                          return _ChatBubble(message: m, isMine: isMine);
                        },
                      ),
              ),
              Container(
                padding: const EdgeInsets.fromLTRB(10, 6, 10, 10),
                decoration: BoxDecoration(
                  border: Border(
                    top: BorderSide(
                      color: Colors.white.withValues(alpha: 0.08),
                    ),
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _input,
                        style: const TextStyle(color: Colors.white),
                        cursorColor: const Color(0xFFFFD24A),
                        maxLength: 200,
                        textInputAction: TextInputAction.send,
                        onSubmitted: (_) => _send(),
                        decoration: InputDecoration(
                          counterText: '',
                          hintText: 'พิมพ์ข้อความ…',
                          hintStyle: const TextStyle(color: Colors.white38),
                          filled: true,
                          fillColor: Colors.black.withValues(alpha: 0.3),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 10,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(22),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Material(
                      color: const Color(0xFFFFD24A),
                      shape: const CircleBorder(),
                      child: InkWell(
                        customBorder: const CircleBorder(),
                        onTap: _send,
                        child: const SizedBox(
                          width: 44,
                          height: 44,
                          child: Icon(
                            Icons.send,
                            color: Color(0xFF1A1A1A),
                          ),
                        ),
                      ),
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

class _ChatBubble extends StatelessWidget {
  const _ChatBubble({required this.message, required this.isMine});
  final ChatMessage message;
  final bool isMine;

  @override
  Widget build(BuildContext context) {
    final align = isMine ? Alignment.centerRight : Alignment.centerLeft;
    final bg = isMine
        ? const Color(0xFFC89A48)
        : Colors.white.withValues(alpha: 0.08);
    final fg = isMine ? const Color(0xFF1A1A1A) : Colors.white;
    return Align(
      alignment: align,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 3),
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        constraints: const BoxConstraints(maxWidth: 260),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment:
              isMine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            if (!isMine)
              Text(
                message.name,
                style: const TextStyle(
                  color: Color(0xFFFFE7A6),
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
            Text(
              message.text,
              style: TextStyle(color: fg, fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }
}
