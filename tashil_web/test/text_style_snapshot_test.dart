// Resolved-TextStyle snapshot for the Sell-In / Sell-Out / Targets screens.
//
// Records (text, fontSize, fontWeight, color, letterSpacing, height) for
// every rendered paragraph and text span so typography refactors can be
// proven visually identical without font-flaky image goldens.
// Re-record: flutter test test/text_style_snapshot_test.dart --dart-define=UPDATE_TEXT_SNAPSHOTS=true
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:tashil_web/core/network/api_client.dart';
import 'package:tashil_web/core/theme/app_theme.dart';
import 'package:tashil_web/features/sell_out_analytics/presentation/screens/sell_in_explorer_screen.dart';
import 'package:tashil_web/features/sell_out_analytics/presentation/screens/sell_out_explorer_screen.dart';

const _update = bool.fromEnvironment('UPDATE_TEXT_SNAPSHOTS');

String _c(Color? c) => c == null ? '-' : c.toARGB32().toRadixString(16);

List<String> _collect(WidgetTester tester) {
  final out = <String>[];
  for (final ro in tester.allRenderObjects) {
    if (ro is! RenderParagraph) continue;
    void visit(InlineSpan span, TextStyle? parent) {
      final s = (parent ?? const TextStyle()).merge(span.style);
      if (span is TextSpan && (span.text ?? '').trim().isNotEmpty) {
        out.add('${span.text!.trim()} | ${s.fontSize} | ${s.fontWeight} | '
            '${_c(s.color)} | ${s.letterSpacing} | ${s.height}');
      }
      if (span is TextSpan) {
        for (final ch in span.children ?? const <InlineSpan>[]) {
          visit(ch, s);
        }
      }
    }
    visit(ro.text, null);
  }
  out.sort();
  return out;
}

Future<void> _check(WidgetTester tester, String name) async {
  final lines = _collect(tester);
  final f = File('test/snapshots/$name.txt');
  if (_update || !f.existsSync()) {
    f.writeAsStringSync('${lines.join('\n')}\n');
    return;
  }
  final expected = const LineSplitter().convert(f.readAsStringSync());
  expect(lines, expected, reason: 'Resolved text styles changed for $name');
}

Future<void> _pump(WidgetTester tester, Widget screen) async {
  tester.view.physicalSize = const Size(1440, 1400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(MaterialApp(
    theme: AppTheme.light(),
    home: Scaffold(body: screen),
  ));
  await tester.pumpAndSettle();
}

Future<void> _tab(WidgetTester tester, Pattern label) async {
  final f = find.textContaining(label);
  expect(f, findsWidgets, reason: 'tab "$label" not found');
  await tester.ensureVisible(f.first);
  await tester.pumpAndSettle();
  await tester.tap(f.first);
  await tester.pumpAndSettle();
}

void main() {
  GoogleFonts.config.allowRuntimeFetching = false;

  testWidgets('Sell-Out explorer text styles are unchanged', (tester) async {
    await _pump(tester, SellOutExplorerScreen(apiClient: ApiClient()));
    await _check(tester, 'sell_out_tab0');
    await _tab(tester, 'Performance & Branch Analytics');
    await _check(tester, 'sell_out_tab1');
    await _tab(tester, 'Target Management (Sell-Out)');
    await _check(tester, 'sell_out_targets');
    await _tab(tester, 'Uploaded Sheets');
    await _check(tester, 'sell_out_sheets');
  });

  testWidgets('Sell-In explorer text styles are unchanged', (tester) async {
    await _pump(tester, SellInExplorerScreen(apiClient: ApiClient()));
    await _check(tester, 'sell_in_tab0');
    await _tab(tester, 'Remaining Stock & Reports');
    await _check(tester, 'sell_in_stock');
    await _tab(tester, 'Target Management (Sell-In)');
    await _check(tester, 'sell_in_targets');
    await _tab(tester, 'Uploaded Sheets');
    await _check(tester, 'sell_in_sheets');
  });
}
