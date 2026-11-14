// Every character we put on screen (signed percents, money, ▲▼, LRI/PDI
// isolates) must exist in the fonts shipped with the app. CanvasKit does
// not use the browser's system fallback, so a missing glyph paints tofu.
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:tashil_web/core/theme/app_theme.dart';
import 'package:tashil_web/core/theme/m3_typography.dart';
import 'package:tashil_web/core/utils/currency_formatter.dart';

Set<int> _cmapCodepoints(Uint8List bytes) {
  final bd = ByteData.sublistView(bytes);
  final numTables = bd.getUint16(4);
  var cmapOffset = -1;
  for (var i = 0; i < numTables; i++) {
    final rec = 12 + i * 16;
    final tag = String.fromCharCodes(bytes.sublist(rec, rec + 4));
    if (tag == 'cmap') {
      cmapOffset = bd.getUint32(rec + 8);
      break;
    }
  }
  if (cmapOffset < 0) {
    throw StateError('no cmap table');
  }
  final numSub = bd.getUint16(cmapOffset + 2);
  final cps = <int>{};
  for (var i = 0; i < numSub; i++) {
    final rec = cmapOffset + 4 + i * 8;
    final sub = cmapOffset + bd.getUint32(rec + 4);
    final format = bd.getUint16(sub);
    if (format == 4) {
      final segCount = bd.getUint16(sub + 6) ~/ 2;
      final endBase = sub + 14;
      final startBase = endBase + 2 * segCount + 2;
      final deltaBase = startBase + 2 * segCount;
      final rangeBase = deltaBase + 2 * segCount;
      for (var s = 0; s < segCount; s++) {
        final start = bd.getUint16(startBase + 2 * s);
        final end = bd.getUint16(endBase + 2 * s);
        final idDelta = bd.getInt16(deltaBase + 2 * s);
        final idRangeOffset = bd.getUint16(rangeBase + 2 * s);
        for (var cp = start; cp <= end; cp++) {
          int glyph;
          if (idRangeOffset == 0) {
            glyph = (cp + idDelta) & 0xFFFF;
          } else {
            final offset = rangeBase + 2 * s + idRangeOffset + 2 * (cp - start);
            final id = bd.getUint16(offset);
            glyph = id == 0 ? 0 : (id + idDelta) & 0xFFFF;
          }
          if (glyph != 0) cps.add(cp);
        }
      }
    } else if (format == 12) {
      final nGroups = bd.getUint32(sub + 12);
      var g = sub + 16;
      for (var i = 0; i < nGroups; i++) {
        final start = bd.getUint32(g);
        final end = bd.getUint32(g + 4);
        final startGlyph = bd.getUint32(g + 8);
        g += 12;
        for (var cp = start; cp <= end; cp++) {
          if (startGlyph + (cp - start) != 0) cps.add(cp);
        }
      }
    }
  }
  return cps;
}

void main() {
  GoogleFonts.config.allowRuntimeFetching = false;

  late Set<int> covered;

  setUpAll(() {
    final cairo = File('test/fonts/Cairo-Variable.ttf').readAsBytesSync();
    final symbolsPath = File('fonts/NotoSansSymbols2-Arrows.ttf').existsSync()
        ? 'fonts/NotoSansSymbols2-Arrows.ttf'
        : 'test/fonts/NotoSansSymbols2-Arrows.ttf';
    final symbols = File(symbolsPath).readAsBytesSync();
    covered = {
      ..._cmapCodepoints(Uint8List.fromList(cairo)),
      ..._cmapCodepoints(Uint8List.fromList(symbols)),
    };
  });

  test('bundled fonts cover every formatter / arrow / isolate character', () {
    const formatChars = {0x2066, 0x2067, 0x2068, 0x2069};
    final samples = <String>[
      CurrencyFormatter.formatSignedPct(-17.9),
      CurrencyFormatter.formatSignedPct(12),
      CurrencyFormatter.formatSignedPct(0),
      CurrencyFormatter.formatSignedPct(0, plusForZero: true),
      CurrencyFormatter.formatCompactEGP(-847),
      CurrencyFormatter.formatCompactEGP(-45080),
      CurrencyFormatter.formatUnits(-847),
      CurrencyFormatter.formatMarginSummary(-4600000, -60.3),
      '▲243 ▼46',
      '▲ زاد · ▼ نزل · يناير - أكتوبر',
      '98.0 ▲',
      '46.5 ▼',
      'نسبة\u00A0%',
      'هامش السلسلة: ${CurrencyFormatter.formatSignedPct(-5.0)}',
      '${CurrencyFormatter.formatSignedPct(0, plusForZero: true)} عن الشهر السابق',
    ];
    final missing = <String>[];
    for (final sample in samples) {
      for (final cp in sample.runes) {
        // Spaces / newlines are always fine; skip ASCII control except we
        // explicitly require the bidi isolates to have a (zero-width) glyph.
        if (cp < 0x20) continue;
        if (!covered.contains(cp)) {
          missing.add(
            'U+${cp.toRadixString(16).toUpperCase().padLeft(4, '0')} '
            '${String.fromCharCode(cp)} in "$sample"',
          );
        }
      }
    }
    expect(missing, isEmpty, reason: missing.join('; '));
    for (final cp in formatChars) {
      expect(covered.contains(cp), isTrue, reason: 'isolate U+${cp.toRadixString(16)}');
    }
    for (final cp in [0x25B2, 0x25BC, 0x2212]) {
      expect(covered.contains(cp), isTrue, reason: 'U+${cp.toRadixString(16)}');
    }
  });

  test('AppFontFallback is applied on every text role of a theme', () {
    const base = TextTheme(
      headlineSmall: TextStyle(fontFamily: 'Cairo'),
      titleLarge: TextStyle(fontFamily: 'Cairo'),
      titleMedium: TextStyle(fontFamily: 'Cairo'),
      bodySmall: TextStyle(fontFamily: 'Cairo'),
      bodyMedium: TextStyle(fontFamily: 'Cairo'),
      labelSmall: TextStyle(fontFamily: 'Cairo'),
      labelMedium: TextStyle(fontFamily: 'Cairo'),
    );
    final theme = AppFontFallback.apply(base);
    for (final style in [
      theme.headlineSmall,
      theme.titleLarge,
      theme.titleMedium,
      theme.bodySmall,
      theme.bodyMedium,
      theme.labelSmall,
      theme.labelMedium,
    ]) {
      expect(
        style?.fontFamilyFallback,
        contains(AppFontFallback.symbolFamily),
      );
    }
  });

  testWidgets('AppTheme.light registers the symbol fallback', (tester) async {
    late TextTheme theme;
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light(),
      home: Builder(builder: (context) {
        theme = Theme.of(context).textTheme;
        return const SizedBox();
      }),
    ));
    expect(
      theme.bodySmall?.fontFamilyFallback,
      contains(AppFontFallback.symbolFamily),
    );
    expect(
      theme.headlineSmall?.fontFamilyFallback,
      contains(AppFontFallback.symbolFamily),
    );
  });
}
