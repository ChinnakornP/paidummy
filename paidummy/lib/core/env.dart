/// Endpoint configuration, overridable at build time via
/// `--dart-define=API_BASE=... --dart-define=WS_BASE=...`.
library;

class Env {
  static const apiBase = String.fromEnvironment(
    'API_BASE',
    defaultValue: 'http://localhost:8887',
  );
  static const wsBase = String.fromEnvironment(
    'WS_BASE',
    defaultValue: 'ws://localhost:8887',
  );
}
