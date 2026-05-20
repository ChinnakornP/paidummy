/// REST client for the Thai Dummy server. No game logic lives here; the
/// server is authoritative.
library;

import 'dart:convert';

import 'package:http/http.dart' as http;

import '../env.dart';
import '../models/index.dart';

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

  /// The server-defined ladder of bet tiers shown in the lobby. Each entry
  /// carries a live snapshot of how many players + rooms are at that stake.
  ///
  /// The parser is deliberately tolerant of the legacy `[int, int, ...]`
  /// shape too — an older server binary returns a list of raw stake ints,
  /// and we'd rather render the menu with zeroed-out counts than crash with
  /// a type-cast error.
  Future<List<TierInfo>> tiers(String token) async {
    final r = await _c.get(
      _u('/api/v1/tiers'),
      headers: {'Authorization': 'Bearer $token'},
    );
    final j = jsonDecode(r.body) as Map<String, dynamic>;
    return ((j['tiers'] as List?) ?? const []).map((e) {
      if (e is Map) {
        return TierInfo.fromJson(e.cast<String, dynamic>());
      }
      if (e is num) {
        return TierInfo(bet: e.toInt(), players: 0, rooms: 0);
      }
      return const TierInfo(bet: 0, players: 0, rooms: 0);
    }).toList();
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

  /// My recent match outcomes — coin delta, balance, win/lose.
  Future<List<CoinHistoryRow>> coinHistory(String token) async {
    final r = await _c.get(
      _u('/api/v1/me/history'),
      headers: {'Authorization': 'Bearer $token'},
    );
    final j = jsonDecode(r.body) as Map<String, dynamic>;
    return ((j['history'] as List?) ?? const [])
        .map((e) => CoinHistoryRow.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Recent finished matches inside one room.
  Future<List<RoomHistoryMatch>> roomHistory(
    String token,
    String roomId,
  ) async {
    final r = await _c.get(
      _u('/api/v1/rooms/$roomId/history'),
      headers: {'Authorization': 'Bearer $token'},
    );
    final j = jsonDecode(r.body) as Map<String, dynamic>;
    return ((j['matches'] as List?) ?? const [])
        .map((e) => RoomHistoryMatch.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// The server-defined coin shop menu.
  Future<List<CoinPackage>> shopPackages(String token) async {
    final r = await _c.get(
      _u('/api/v1/shop/packages'),
      headers: {'Authorization': 'Bearer $token'},
    );
    final j = jsonDecode(r.body) as Map<String, dynamic>;
    return ((j['packages'] as List?) ?? const [])
        .map((e) => CoinPackage.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Mock-payment purchase. Always succeeds today; returns the new wallet
  /// balance and how many coins were credited.
  Future<({int coinsAdded, int newBalance})> purchase(
    String token,
    String packageId,
  ) async {
    final r = await _c.post(
      _u('/api/v1/shop/purchase'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({'package_id': packageId}),
    );
    final j = jsonDecode(r.body) as Map<String, dynamic>;
    if (r.statusCode >= 300) {
      throw Exception((j['error'] as String?) ?? 'purchase failed');
    }
    return (
      coinsAdded: (j['coins_added'] as num).toInt(),
      newBalance: (j['new_balance'] as num).toInt(),
    );
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
