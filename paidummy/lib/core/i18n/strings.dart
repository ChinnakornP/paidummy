/// Lightweight i18n scaffold. Holds a th/en string table + a localeProvider
/// the app shell binds to MaterialApp.locale. This is the seam a full
/// intl/arb (flutter gen-l10n) migration can replace later — call sites use
/// `ref.t('key')` so swapping the backend won't touch them.
///
/// Only a starter set of keys is translated; untranslated keys fall back to
/// the key itself so missing strings are obvious in QA.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Supported app locales. Thai is the default (Thai-first product).
const supportedLocales = [Locale('th'), Locale('en')];

/// Active UI locale. Defaults to Thai; toggled from the home screen.
final localeProvider = StateProvider<Locale>((ref) => const Locale('th'));

const _table = <String, Map<String, String>>{
  'th': {
    'app_tagline': 'เล่นเร็ว · เดิมพันได้ · ฟรีไม่ต้องสมัคร',
    'enter_game': 'เข้าสู่เกม',
    'how_to_play': 'วิธีเล่น',
    'lobby_pick_room': 'เลือกห้องเดิมพัน',
    'practice': 'ฝึกซ้อมกับบอท',
    'missions': 'ภารกิจ',
    'friends': 'เพื่อน',
    'leaderboard': 'อันดับ',
    'shop': 'ร้านค้า',
    'history': 'ประวัติ',
  },
  'en': {
    'app_tagline': 'Fast · Stakes · Free, no signup',
    'enter_game': 'Enter game',
    'how_to_play': 'How to play',
    'lobby_pick_room': 'Pick a table',
    'practice': 'Practice vs bots',
    'missions': 'Missions',
    'friends': 'Friends',
    'leaderboard': 'Leaderboard',
    'shop': 'Shop',
    'history': 'History',
  },
};

/// Resolves a key for [locale], falling back to Thai then the key itself.
String tr(Locale locale, String key) {
  return _table[locale.languageCode]?[key] ?? _table['th']?[key] ?? key;
}

extension AppStringsX on WidgetRef {
  /// Translate [key] under the active locale.
  String t(String key) => tr(read(localeProvider), key);
}
