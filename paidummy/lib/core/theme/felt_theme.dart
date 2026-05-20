/// Material 3 theme seeded from the felt-table green so every Material
/// component inherits the same palette as the painted background.
library;

import 'package:flutter/material.dart';

ThemeData buildFeltTheme() => ThemeData(
  colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF0B6B3A)),
  useMaterial3: true,
);
