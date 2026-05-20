/// REST + WebSocket clients for the Thai Dummy server. No game logic lives
/// here; the server is authoritative.
library;

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';

import 'env.dart';
import 'models.dart';

class ApiClient {
  ApiClient({http.Client? client}) : _c = client ?? http.Client();
  final http.Client _c;

  Uri _u(String path) => Uri.parse('${Env.apiBase}$path');

  Future<Guest> createGuest(String displayName) async {
    final r = await _c.post(
      _u('/api/v1/guest'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'display_name': displayName}),
    );
    return Guest.fromJson(jsonDecode(r.body) as Map<String, dynamic>);
  }

  Future<List<RoomInfo>> listRooms(String token) async {
    final r = await _c.get(
      _u('/api/v1/rooms'),
      headers: {'Authorization': 'Bearer $token'},
    );
    final j = jsonDecode(r.body) as Map<String, dynamic>;
    return ((j['rooms'] as List?) ?? const [])
        .map((e) => RoomInfo.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<String> createRoom(String token, String name, int maxPlayers) async {
    final r = await _c.post(
      _u('/api/v1/rooms'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({'name': name, 'max_players': maxPlayers}),
    );
    return (jsonDecode(r.body) as Map<String, dynamic>)['id'] as String;
  }

  Future<void> joinRoom(String token, String roomId) async {
    await _c.post(
      _u('/api/v1/rooms/$roomId/join'),
      headers: {'Authorization': 'Bearer $token'},
    );
  }

  /// Refreshes the authenticated guest (used to surface the live coin balance
  /// in the lobby after a settled match).
  Future<Guest> me(String token) async {
    final r = await _c.get(
      _u('/api/v1/me'),
      headers: {'Authorization': 'Bearer $token'},
    );
    return Guest.fromJson(jsonDecode(r.body) as Map<String, dynamic>);
  }

  /// The server-defined ladder of bet tiers shown in the lobby.
  Future<List<int>> tiers(String token) async {
    final r = await _c.get(
      _u('/api/v1/tiers'),
      headers: {'Authorization': 'Bearer $token'},
    );
    final j = jsonDecode(r.body) as Map<String, dynamic>;
    return ((j['tiers'] as List?) ?? const [])
        .map((e) => (e as num).toInt())
        .toList();
  }

  /// Quickplay: server finds the nearest open room at [bet] or creates one.
  /// Throws [QuickplayException] if the wallet lacks coins or the tier is
  /// invalid.
  Future<String> quickplay(String token, int bet) async {
    final r = await _c.post(
      _u('/api/v1/quickplay'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({'bet': bet}),
    );
    final j = jsonDecode(r.body) as Map<String, dynamic>;
    if (r.statusCode >= 300) {
      throw QuickplayException(
        r.statusCode,
        (j['error'] as String?) ?? 'quickplay failed',
        coins: (j['coins'] as num?)?.toInt(),
        need: (j['need'] as num?)?.toInt(),
      );
    }
    return j['room_id'] as String;
  }

  Future<void> addBots(String token, String roomId, int count) async {
    await _c.post(
      _u('/api/v1/rooms/$roomId/bots'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({'count': count}),
    );
  }
}

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

/// Quickplay failure with structured detail so the UI can show e.g.
/// "ต้องการ 500 🪙 มี 320 🪙".
class QuickplayException implements Exception {
  QuickplayException(this.statusCode, this.message, {this.coins, this.need});
  final int statusCode;
  final String message;
  final int? coins;
  final int? need;
  @override
  String toString() => message;
}
