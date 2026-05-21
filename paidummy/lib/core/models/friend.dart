/// A friend or incoming friend-request summary.
library;

class Friend {
  const Friend({
    required this.id,
    required this.name,
    required this.refCode,
    required this.avatar,
  });
  final String id;
  final String name;
  final String refCode;
  final String avatar;

  factory Friend.fromJson(Map<String, dynamic> j) => Friend(
    id: j['id'] as String? ?? '',
    name: j['name'] as String? ?? '',
    refCode: j['ref_code'] as String? ?? '',
    avatar: j['avatar'] as String? ?? '🙂',
  );
}
