import 'dart:io';

import 'package:flutter/services.dart';

/// Registers the real Cairo font (google/fonts `Cairo[slnt,wght].ttf`, OFL,
/// see `test/fonts/OFL.txt`) for widget tests that measure Arabic text.
///
/// The default test font draws every glyph as a 1em square, which makes
/// Arabic labels far wider than in the app (a 112dp check can pass even when
/// the live segment is ~79dp). The app's theme uses `GoogleFonts.cairo…`, so
/// the font is registered under the family names google_fonts generates
/// (`Cairo_regular`, `Cairo_500`, …) as well as plain `Cairo`.
Future<void> loadRealCairoFont() async {
  final bytes = File('test/fonts/Cairo-Variable.ttf').readAsBytesSync();
  final data = ByteData.view(Uint8List.fromList(bytes).buffer);
  const families = [
    'Cairo',
    'Cairo_regular',
    'Cairo_200',
    'Cairo_300',
    'Cairo_500',
    'Cairo_600',
    'Cairo_700',
    'Cairo_800',
    'Cairo_900',
  ];
  for (final family in families) {
    await (FontLoader(family)..addFont(Future.value(data))).load();
  }
}
