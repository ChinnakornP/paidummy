/// Material 3 theme seeded from the felt-table green so every Material
/// component inherits the same palette as the painted background.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/index.dart';

ThemeData buildFeltTheme() => ThemeData(
  colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF0B6B3A)),
  useMaterial3: true,
);

/// The three radial-gradient stops the felt background paints, per cosmetic
/// theme. Centre → mid → outer vignette.
class FeltPalette {
  const FeltPalette(this.centre, this.mid, this.outer);
  final Color centre;
  final Color mid;
  final Color outer;
}

/// Theme-id → felt palette. Keys mirror db.AllowedThemes; 'classic' is the
/// original green felt.
const feltPalettes = <String, FeltPalette>{
  'classic': FeltPalette(Color(0xFF1B6A4A), Color(0xFF0D4733), Color(0xFF2A1212)),
  'midnight': FeltPalette(Color(0xFF274060), Color(0xFF142536), Color(0xFF0A0F1A)),
  'emerald': FeltPalette(Color(0xFF1FA06A), Color(0xFF0E5E3E), Color(0xFF09241A)),
  'ruby': FeltPalette(Color(0xFF8E2A3A), Color(0xFF5A1320), Color(0xFF1E0A0E)),
  'sand': FeltPalette(Color(0xFFB58A4A), Color(0xFF7A5A2E), Color(0xFF2A1E12)),
};

/// The active felt palette derived from the signed-in guest's theme. Falls
/// back to classic before /me resolves or for unknown ids.
final feltThemeProvider = Provider<FeltPalette>((ref) {
  final id = ref.watch(meProvider).value?.theme ?? 'classic';
  return feltPalettes[id] ?? feltPalettes['classic']!;
});
