/// WebSocket client for the Thai Dummy room channel. Decoded `{type, data}`
/// envelopes are surfaced on a broadcast stream; senders speak the same
/// envelope.
///
/// The client auto-reconnects with exponential backoff when the socket drops
/// unexpectedly (network blip, server restart). On a successful reopen the
/// server re-Attaches the seat and re-sends `room_state`, so play resumes
/// where it left off. A `socket_reconnecting` envelope is emitted before
/// each retry so the UI can show a "reconnecting…" overlay.
library;

import 'dart:async';
import 'dart:convert';

import 'package:web_socket_channel/web_socket_channel.dart';

import '../env.dart';

class WsClient {
  WebSocketChannel? _ch;
  StreamSubscription? _sub;
  final _controller = StreamController<Map<String, dynamic>>.broadcast();

  String? _token;
  String? _roomId;
  bool _spectate = false;
  bool _wantConnected = false;
  int _retry = 0;
  Timer? _reconnectTimer;

  static const _maxBackoff = Duration(seconds: 8);

  Stream<Map<String, dynamic>> get messages => _controller.stream;

  void connect(String token, String roomId, {bool spectate = false}) {
    _token = token;
    _roomId = roomId;
    _spectate = spectate;
    _wantConnected = true;
    _retry = 0;
    _open();
  }

  void _open() {
    _cleanupSocket();
    final token = _token, roomId = _roomId;
    if (token == null || roomId == null) return;
    final spec = _spectate ? '&spectate=1' : '';
    final uri = Uri.parse('${Env.wsBase}/ws?token=$token&room=$roomId$spec');
    final ch = WebSocketChannel.connect(uri);
    _ch = ch;
    _sub = ch.stream.listen(
      (raw) {
        // Any inbound frame proves the link is healthy → reset backoff.
        _retry = 0;
        try {
          final m = jsonDecode(raw as String) as Map<String, dynamic>;
          _controller.add(m);
        } catch (_) {
          /* ignore malformed frame */
        }
      },
      onError: (_) {
        _controller.add({'type': 'socket_error'});
        _scheduleReconnect();
      },
      onDone: () {
        _controller.add({'type': 'socket_closed'});
        _scheduleReconnect();
      },
    );
  }

  void _scheduleReconnect() {
    if (!_wantConnected) return;
    _reconnectTimer?.cancel();
    // 0.5s, 1s, 2s, 4s, 8s (capped). _retry advances each attempt and is
    // reset to 0 the moment a frame arrives after reconnecting.
    final ms = (500 * (1 << _retry)).clamp(500, _maxBackoff.inMilliseconds);
    if (_retry < 5) _retry++;
    _controller.add({'type': 'socket_reconnecting'});
    _reconnectTimer = Timer(Duration(milliseconds: ms), () {
      if (_wantConnected) _open();
    });
  }

  void send(String type, [Map<String, dynamic> data = const {}]) {
    final ch = _ch;
    if (ch == null) return;
    ch.sink.add(jsonEncode({'type': type, 'data': data}));
  }

  void _cleanupSocket() {
    _sub?.cancel();
    _sub = null;
    _ch?.sink.close();
    _ch = null;
  }

  void disconnect() {
    _wantConnected = false;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _cleanupSocket();
  }

  void dispose() {
    disconnect();
    _controller.close();
  }
}
