/// Cross-platform profile-sync scaffold. Today the game is guest-only; this
/// defines the seam for "Sign in with Google / Apple" so a returning player
/// can recover their wallet from any device.
///
/// The concrete Google/Apple providers are stubs (no SDK wired). When
/// credentials exist, implement [SocialAuth.signIn] to return a provider
/// token, exchange it server-side for a session bound to the guest id, and
/// the rest of the app (sessionProvider) is unchanged.
library;

/// Result of a successful social sign-in: a provider id token to exchange
/// with the server.
class SocialIdentity {
  const SocialIdentity({required this.provider, required this.idToken});
  final String provider; // 'google' | 'apple'
  final String idToken;
}

/// A social identity provider (Google / Apple).
abstract interface class SocialAuth {
  String get id;
  String get label;
  bool get available;
  Future<SocialIdentity> signIn();
}

/// Google Sign-In stub. Wire `google_sign_in` + a server token exchange.
class GoogleAuth implements SocialAuth {
  const GoogleAuth();
  @override
  String get id => 'google';
  @override
  String get label => 'เข้าสู่ระบบด้วย Google';
  @override
  bool get available => false; // flip true once google_sign_in is wired
  @override
  Future<SocialIdentity> signIn() async =>
      throw UnimplementedError('Google sign-in not configured');
}

/// Apple Sign-In stub. Wire `sign_in_with_apple` + a server token exchange.
class AppleAuth implements SocialAuth {
  const AppleAuth();
  @override
  String get id => 'apple';
  @override
  String get label => 'เข้าสู่ระบบด้วย Apple';
  @override
  bool get available => false; // flip true once sign_in_with_apple is wired
  @override
  Future<SocialIdentity> signIn() async =>
      throw UnimplementedError('Apple sign-in not configured');
}

/// Registry of social providers the sign-in screen can render. Each is shown
/// disabled until `available` flips true.
const socialAuthProviders = <SocialAuth>[GoogleAuth(), AppleAuth()];
