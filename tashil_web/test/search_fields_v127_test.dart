// v127: search placeholders never clip ("Search campaign, b…").
// Trade Marketing's search fills the rest of its filter row; Sell-In and
// Sell-Out search boxes grow to their full placeholder. Real Cairo font.
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:tashil_web/core/data/app_cache.dart';
import 'package:tashil_web/core/network/api_client.dart';
import 'package:tashil_web/core/theme/app_theme.dart';
import 'package:tashil_web/core/widgets/m3_search_field.dart';
import 'package:tashil_web/features/sell_out_analytics/presentation/screens/sell_in_explorer_screen.dart';
import 'package:tashil_web/features/sell_out_analytics/presentation/screens/sell_out_explorer_screen.dart';
import 'package:tashil_web/features/trade_marketing/presentation/screens/trade_marketing_roi_screen.dart';

import 'support/real_fonts.dart';
import 'trade_marketing_roi_test.dart' show FakeTradeMarketingRepository;

/// Every visible, empty TextField with a hint must show the whole hint.
List<String> _clippedHints(WidgetTester tester) {
  final out = <String>[];
  for (final e in find.byType(TextField).evaluate()) {
    final tf = e.widget as TextField;
    final hint = tf.decoration?.hintText;
    if (hint == null || (tf.controller?.text.isNotEmpty ?? false)) continue;
    final hintText = find.descendant(
        of: find.byElementPredicate((x) => x == e), matching: find.text(hint));
    if (hintText.evaluate().isEmpty) continue;
    final style = tester.widget<Text>(hintText.first).style;
    final editable = find.descendant(
        of: find.byElementPredicate((x) => x == e),
        matching: find.byType(EditableText));
    final box = tester.renderObject<RenderBox>(editable.first);
    final tp = TextPainter(
      text: TextSpan(text: hint, style: style),
      textDirection: Directionality.of(e),
      textScaler: MediaQuery.textScalerOf(e),
      maxLines: 1,
    )..layout();
    if (tp.width > box.size.width + 0.5) {
      out.add('"$hint" ${tp.width.toStringAsFixed(1)} > '
          '${box.size.width.toStringAsFixed(1)}');
    }
  }
  return out;
}

Future<void> _pump(WidgetTester tester, Widget page, double width) async {
  tester.view.physicalSize = Size(width, 3000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(MaterialApp(
    theme: AppTheme.light(),
    locale: const Locale('ar'),
    supportedLocales: const [Locale('ar'), Locale('en')],
    localizationsDelegates: const [
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    home: Directionality(
        textDirection: TextDirection.rtl, child: Scaffold(body: page)),
  ));
  await tester.pumpAndSettle();
}

void main() {
  GoogleFonts.config.allowRuntimeFetching = false;
  setUpAll(loadRealCairoFont);
  setUp(AppCache.clear);

  for (final width in [1280.0, 1600.0]) {
    testWidgets(
        'Trade Marketing search shows its placeholder and fills the '
        'filter row at ${width.toInt()}', (tester) async {
      await _pump(
          tester,
          TradeMarketingRoiScreen(
              apiClient: ApiClient(),
              repository: FakeTradeMarketingRepository()),
          width);
      expect(tester.takeException(), isNull);
      expect(_clippedHints(tester), isEmpty);
      // Fills its row: the field ends where the widest filter row ends.
      final search = find.ancestor(
          of: find.text('Search campaign, brand...'),
          matching: find.byType(TextField));
      final s = tester.getRect(search.first);
      final rowEnd = [
        for (final l in ['Retail Chain', 'Month', 'Year', 'Activity Type'])
          tester
              .getRect(find.byWidgetPredicate((w) =>
                  w is DropdownMenu &&
                  w.label is Text &&
                  (w.label! as Text).data == l))
              .right
      ].reduce((a, b) => a > b ? a : b);
      expect(s.right, greaterThanOrEqualTo(rowEnd - 1),
          reason: 'search ${s.width.toStringAsFixed(0)}dp should fill its row');
    });

    testWidgets('Sell-In search placeholders fit at ${width.toInt()}',
        (tester) async {
      await _pump(
          tester,
          SellInExplorerScreen(apiClient: ApiClient(tenantId: 'tenant-adeco')),
          width);
      expect(find.text('ابحث بالصنف أو الكود أو الباركود'), findsWidgets);
      expect(_clippedHints(tester), isEmpty);
    });

    testWidgets('Sell-Out search placeholders fit at ${width.toInt()}',
        (tester) async {
      await _pump(tester, SellOutExplorerScreen(apiClient: ApiClient()), width);
      for (final tab in ['بيانات المبيعات', 'أداء الفروع']) {
        final f = find.textContaining(RegExp('^$tab'));
        if (tab != 'بيانات المبيعات') {
          await tester.tap(f.first);
          await tester.pumpAndSettle();
        }
        expect(_clippedHints(tester), isEmpty, reason: tab);
      }
      expect(find.text('ابحث بالفرع أو المنطقة أو الصنف'), findsWidgets);
      expect(_clippedHints(tester), isEmpty);
    });
  }

  // Targets panel and super-admin search boxes (same widths/decorations as
  // the screens) grow to their placeholder.
  for (final (hint, width) in const [
    ('ابحث باسم الفرع أو الكود أو المندوب...', 240.0),
    ('بحث عن شركة أو بريد أو كود...', 250.0),
    ('بحث في السجل (مستخدم، شركة، IP)...', 280.0),
  ]) {
    testWidgets('M3SearchFieldWidth fits "$hint"', (tester) async {
      await _pump(
          tester,
          Center(
            child: M3SearchFieldWidth(
              hintText: hint,
              width: width,
              child: TextField(
                decoration: InputDecoration(
                  hintText: hint,
                  prefixIcon: const Icon(Icons.search_rounded, size: 18.0),
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 10.0, vertical: 10.0),
                  filled: true,
                  border: const OutlineInputBorder(),
                ),
              ),
            ),
          ),
          1280);
      expect(_clippedHints(tester), isEmpty);
      expect(tester.getSize(find.byType(TextField)).width,
          greaterThanOrEqualTo(width));
    });
  }
}
