/// WebSocket client for the Thai Dummy room channel. Decoded `{type, data}`
/// envelopes are surfaced on a broadcast stream; senders speak the same
/// envelope.
library;

import 'dart:async';
import 'dart:convert';

import 'package:web_socket_channel/web_socket_channel.dart';

import '../env.dart';

/// WsClient wraps a single room connection. It exposes a broadcast stream of
/// decoded `{type, data}` envelopes and a typed send().
class WsClient {
  WebSocketChannel? _ch;
  StreamSubscription? _sub;
  final _controller = StreamController<Map<String, dynamic>>.broadcast();

  Stream<Map<String, dynamic>> get messages => _controller.stream;

  void connect(String token, String roomId) {
    disconnect();
    final uri = Uri.parse('${Env.wsBase}/ws?token=$token&room=$roomId');
    final ch = WebSocketChannel.connect(uri);
    _ch = ch;
    _sub = ch.stream.listen(
      (raw) {
        try {
          final m = jsonDecode(raw as String) as Map<String, dynamic>;
          _controller.add(m);
        } catch (_) {
          /* ignore malformed frame */
        }
      },
      onError: (_) => _controller.add({'type': 'socket_error'}),
      onDone: () => _controller.add({'type': 'socket_closed'}),
    );
  }

  void send(String type, [Map<String, dynamic> data = const {}]) {
    final ch = _ch;
    if (ch == null) return;
    ch.sink.add(jsonEncode({'type': type, 'data': data}));
  }

  void disconnect() {
    _sub?.cancel();
    _sub = null;
    _ch?.sink.close();
    _ch = null;
  }

  void dispose() {
    disconnect();
    _controller.close();
  }
}
