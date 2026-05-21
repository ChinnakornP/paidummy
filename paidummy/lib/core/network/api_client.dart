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

  Future<Guest> createGuest(String displayName, {String ref = ''}) async {
    final r = await _c.post(
      _u('/api/v1/guest'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'display_name': displayName, 'ref': ref}),
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

  /// Creates a fully-configurable custom room (password, target score, turn
  /// timer, etc.) and auto-seats the host. Returns the room id and the
  /// password the server echoed back (used to render a shareable chip).
  Future<({String id, String password})> createRoom(
    String token, {
    required String name,
    int maxPlayers = 4,
    int targetScore = 0,
    int bet = 0,
    int turnTimerSec = 0,
    String password = '',
  }) async {
    final r = await _c.post(
      _u('/api/v1/rooms'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'name': name,
        'max_players': maxPlayers,
        'target_score': targetScore,
        'bet': bet,
        'turn_timer_sec': turnTimerSec,
        'password': password,
      }),
    );
    final j = jsonDecode(r.body) as Map<String, dynamic>;
    if (r.statusCode >= 300) {
      throw Exception((j['error'] as String?) ?? 'create room failed');
    }
    return (
      id: j['id'] as String,
      password: (j['password'] as String?) ?? '',
    );
  }

  /// Seats the guest in [roomId], supplying [password] for locked rooms.
  /// Throws on 403 (bad password) / 404 / 409.
  Future<void> joinRoom(
    String token,
    String roomId, {
    String password = '',
  }) async {
    final r = await _c.post(
      _u('/api/v1/rooms/$roomId/join'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({'password': password}),
    );
    if (r.statusCode >= 300) {
      final j = jsonDecode(r.body) as Map<String, dynamic>;
      throw Exception((j['error'] as String?) ?? 'join failed');
    }
  }

  /// Reads a room's public metadata without joining it. Used by the
  /// "เข้าด้วยรหัส" flow to show name/locked/seat-count before submitting.
  Future<Map<String, dynamic>> roomInfo(String token, String roomId) async {
    final r = await _c.get(
      _u('/api/v1/rooms/$roomId'),
      headers: {'Authorization': 'Bearer $token'},
    );
    final j = jsonDecode(r.body) as Map<String, dynamic>;
    if (r.statusCode >= 300) {
      throw Exception((j['error'] as String?) ?? 'room not found');
    }
    return j;
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

  /// Returns whether the guest can claim today's daily bonus + which streak
  /// they would land on.
  Future<DailyBonus> dailyStatus(String token) async {
    final r = await _c.get(
      _u('/api/v1/me/daily'),
      headers: {'Authorization': 'Bearer $token'},
    );
    return DailyBonus.fromJson(jsonDecode(r.body) as Map<String, dynamic>);
  }

  /// Credits the daily bonus atomically. Returns the awarded streak, coins
  /// added, and the new balance.
  Future<({int streak, int coinsAdded, int newBalance})> claimDaily(
    String token,
  ) async {
    final r = await _c.post(
      _u('/api/v1/me/daily/claim'),
      headers: {'Authorization': 'Bearer $token'},
    );
    final j = jsonDecode(r.body) as Map<String, dynamic>;
    if (r.statusCode >= 300) {
      throw Exception((j['error'] as String?) ?? 'claim failed');
    }
    return (
      streak: (j['streak'] as num).toInt(),
      coinsAdded: (j['coins_added'] as num).toInt(),
      newBalance: (j['new_balance'] as num).toInt(),
    );
  }

  /// Sets the guest's avatar to one of the preset palette glyphs.
  Future<void> setAvatar(String token, String avatar) async {
    final r = await _c.patch(
      _u('/api/v1/me/avatar'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({'avatar': avatar}),
    );
    if (r.statusCode >= 300) {
      final j = jsonDecode(r.body) as Map<String, dynamic>;
      throw Exception((j['error'] as String?) ?? 'set avatar failed');
    }
  }

  /// Registers a push-notification device token. Skeleton: call this once a
  /// real FCM/APNs token is available (firebase_messaging not wired yet).
  Future<void> registerDeviceToken(
    String token,
    String deviceToken, {
    String platform = 'unknown',
  }) async {
    await _c.post(
      _u('/api/v1/me/device-token'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({'token': deviceToken, 'platform': platform}),
    );
  }

  /// Rewarded-ad status — whether a (mock) ad reward is claimable now and
  /// the next claim time.
  Future<({bool available, int reward, int? nextClaimMs})> adStatus(
    String token,
  ) async {
    final r = await _c.get(
      _u('/api/v1/me/ad'),
      headers: {'Authorization': 'Bearer $token'},
    );
    final j = jsonDecode(r.body) as Map<String, dynamic>;
    final next = j['next_claim'] as String?;
    return (
      available: j['available'] as bool? ?? false,
      reward: (j['reward'] as num?)?.toInt() ?? 0,
      nextClaimMs: next == null
          ? null
          : DateTime.tryParse(next)?.millisecondsSinceEpoch,
    );
  }

  /// Claims the mock rewarded-ad bonus. Throws on cooldown (429).
  Future<({int coinsAdded, int newBalance})> claimAd(String token) async {
    final r = await _c.post(
      _u('/api/v1/me/ad/claim'),
      headers: {'Authorization': 'Bearer $token'},
    );
    final j = jsonDecode(r.body) as Map<String, dynamic>;
    if (r.statusCode >= 300) {
      throw Exception((j['error'] as String?) ?? 'ad claim failed');
    }
    return (
      coinsAdded: (j['coins_added'] as num).toInt(),
      newBalance: (j['new_balance'] as num).toInt(),
    );
  }

  /// Reports another player. [reason] is free text (capped server-side).
  Future<void> reportPlayer(
    String token,
    String targetId,
    String reason,
  ) async {
    final r = await _c.post(
      _u('/api/v1/reports'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({'target_id': targetId, 'reason': reason}),
    );
    if (r.statusCode >= 300) {
      final j = jsonDecode(r.body) as Map<String, dynamic>;
      throw Exception((j['error'] as String?) ?? 'report failed');
    }
  }

  /// Accepted friends.
  Future<List<Friend>> friends(String token) async {
    final r = await _c.get(
      _u('/api/v1/me/friends'),
      headers: {'Authorization': 'Bearer $token'},
    );
    final j = jsonDecode(r.body) as Map<String, dynamic>;
    return ((j['friends'] as List?) ?? const [])
        .map((e) => Friend.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Incoming pending friend requests.
  Future<List<Friend>> friendRequests(String token) async {
    final r = await _c.get(
      _u('/api/v1/me/friends/requests'),
      headers: {'Authorization': 'Bearer $token'},
    );
    final j = jsonDecode(r.body) as Map<String, dynamic>;
    return ((j['requests'] as List?) ?? const [])
        .map((e) => Friend.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Sends (or auto-accepts) a friend request by the target's ref code.
  Future<bool> sendFriendRequest(String token, String refCode) async {
    final r = await _c.post(
      _u('/api/v1/me/friends/request'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({'ref_code': refCode}),
    );
    final j = jsonDecode(r.body) as Map<String, dynamic>;
    if (r.statusCode >= 300) {
      throw Exception((j['error'] as String?) ?? 'request failed');
    }
    return j['auto_accepted'] as bool? ?? false;
  }

  /// Accepts a pending request from [fromId].
  Future<void> acceptFriend(String token, String fromId) async {
    final r = await _c.post(
      _u('/api/v1/me/friends/accept'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({'from_id': fromId}),
    );
    if (r.statusCode >= 300) {
      final j = jsonDecode(r.body) as Map<String, dynamic>;
      throw Exception((j['error'] as String?) ?? 'accept failed');
    }
  }

  /// Today's daily missions with the caller's progress.
  Future<List<MissionStatus>> missions(String token) async {
    final r = await _c.get(
      _u('/api/v1/me/missions'),
      headers: {'Authorization': 'Bearer $token'},
    );
    final j = jsonDecode(r.body) as Map<String, dynamic>;
    return ((j['missions'] as List?) ?? const [])
        .map((e) => MissionStatus.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Claims a completed mission's reward. Returns reward + new balance.
  Future<({int reward, int newBalance})> claimMission(
    String token,
    String missionId,
  ) async {
    final r = await _c.post(
      _u('/api/v1/me/missions/$missionId/claim'),
      headers: {'Authorization': 'Bearer $token'},
    );
    final j = jsonDecode(r.body) as Map<String, dynamic>;
    if (r.statusCode >= 300) {
      throw Exception((j['error'] as String?) ?? 'claim failed');
    }
    return (
      reward: (j['reward'] as num).toInt(),
      newBalance: (j['new_balance'] as num).toInt(),
    );
  }

  /// Sets the cosmetic felt theme to one of the allowed ids.
  Future<void> setTheme(String token, String theme) async {
    final r = await _c.patch(
      _u('/api/v1/me/theme'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({'theme': theme}),
    );
    if (r.statusCode >= 300) {
      final j = jsonDecode(r.body) as Map<String, dynamic>;
      throw Exception((j['error'] as String?) ?? 'set theme failed');
    }
  }

  /// Spins up a solo training room (host + 3 bots) that doesn't settle
  /// coins. Returns the new room id.
  Future<String> startPractice(String token) async {
    final r = await _c.post(
      _u('/api/v1/practice'),
      headers: {'Authorization': 'Bearer $token'},
    );
    final j = jsonDecode(r.body) as Map<String, dynamic>;
    if (r.statusCode >= 300) {
      throw Exception((j['error'] as String?) ?? 'practice failed');
    }
    return j['room_id'] as String;
  }

  /// Top-N players ranked by coin profit. [period] is one of
  /// 'alltime' | 'weekly' | 'daily'; unrecognised values fall back to alltime
  /// server-side.
  Future<List<LeaderboardRow>> leaderboard(
    String token, {
    String period = 'alltime',
  }) async {
    final r = await _c.get(
      _u('/api/v1/leaderboard?period=$period'),
      headers: {'Authorization': 'Bearer $token'},
    );
    final j = jsonDecode(r.body) as Map<String, dynamic>;
    return ((j['rows'] as List?) ?? const [])
        .map((e) => LeaderboardRow.fromJson(e as Map<String, dynamic>))
        .toList();
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
