// Smoke test: the app boots into the guest sign-in screen.
//
// The counter scaffold this replaced no longer exists; this verifies the
// Riverpod-wrapped PaiDummyApp renders HomeScreen without a backend (no
// network call happens until "Play as guest" is pressed).

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:paidummy/ui.dart';

void main() {
  testWidgets('boots into guest home screen', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: PaiDummyApp()));
    await tester.pump();

    expect(find.text('Pai Dummy'), findsOneWidget);
    expect(find.text('Play as guest'), findsOneWidget);
    expect(find.byType(HomeScreen), findsOneWidget);
  });
}
