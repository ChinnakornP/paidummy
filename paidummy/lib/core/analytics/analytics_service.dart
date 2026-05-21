/// Analytics + crash-reporting abstraction. The shipped implementation is a
/// debug-log mock so the funnel is instrumented today without a vendor SDK;
/// swap [LogAnalytics] for a Sentry/Firebase-backed impl behind the same
/// interface when credentials exist.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// One analytics event: a name plus optional string/num/bool properties.
abstract interface class AnalyticsService {
  void event(String name, [Map<String, Object?> props]);
  void screen(String name);
  void error(Object error, StackTrace? stack, {String? context});
}

/// Default mock — prints structured lines in debug, no-ops in release.
class LogAnalytics implements AnalyticsService {
  const LogAnalytics();

  @override
  void event(String name, [Map<String, Object?> props = const {}]) {
    if (kDebugMode) debugPrint('[analytics] $name ${props.isEmpty ? '' : props}');
  }

  @override
  void screen(String name) {
    if (kDebugMode) debugPrint('[analytics] screen:$name');
  }

  @override
  void error(Object error, StackTrace? stack, {String? context}) {
    if (kDebugMode) {
      debugPrint('[analytics] error${context == null ? '' : '($context)'}: $error');
    }
  }
}

/// App-wide analytics. Provider so a real backend can be injected in main()
/// via an override without touching call sites.
final analyticsProvider = Provider<AnalyticsService>((ref) {
  return const LogAnalytics();
});
