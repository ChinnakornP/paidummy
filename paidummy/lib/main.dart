import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';

Future<void> main() async {
  // The whole game is designed for landscape — the felt, the player seats,
  // and the horizontal tier scroller all assume a wide aspect ratio. Lock
  // before runApp so the first frame is already oriented correctly.
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);
  runApp(const ProviderScope(child: PaiDummyApp()));
}
