// v126: no Trade Marketing dropdown clips its value ("All Mont", "All Chain…").
// Every DropdownMenu on the page (toolbar + Add Expense + ROI Simulator
// dialogs) must fit its longest option, measured with the real Cairo font.
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:tashil_web/core/data/app_cache.dart';
import 'package:tashil_web/core/network/api_client.dart';
import 'package:tashil_web/core/theme/app_theme.dart';
import 'package:tashil_web/features/trade_marketing/presentation/screens/trade_marketing_roi_screen.dart';

import 'support/real_fonts.dart';
import 'trade_marketing_roi_test.dart' show FakeTradeMarketingRepository;

String _labelOf(DropdownMenu<dynamic> m) {
  final l = m.label;
  return l is Text ? (l.data ?? '?') : '?';
}

/// Fails with every dropdown whose text field is narrower than an option.
void _expectNoClipping(WidgetTester tester, String where) {
  final problems = <String>[];
  final menus = find.byWidgetPredicate((w) => w is DropdownMenu);
  expect(menus, findsWidgets, reason: where);
  for (final e in menus.evaluate()) {
    final menu = e.widget as DropdownMenu<dynamic>;
    final editable = find.descendant(
        of: find.byElementPredicate((x) => x == e),
        matching: find.byType(EditableText));
    final field = tester.renderObject<RenderBox>(editable.first);
    final style = tester.widget<EditableText>(editable.first).style;
    final scaler = MediaQuery.textScalerOf(e);
    for (final entry in menu.dropdownMenuEntries) {
      final tp = TextPainter(
        text: TextSpan(text: entry.label, style: style),
        textDirection: Directionality.of(e),
        textScaler: scaler,
        maxLines: 1,
      )..layout();
      if (tp.width > field.size.width + 0.5) {
        problems.add('${_labelOf(menu)}: "${entry.label}" '
            '${tp.width.toStringAsFixed(1)} > ${field.size.width.toStringAsFixed(1)}');
      }
    }
  }
  expect(problems, isEmpty, reason: '$where clipped: ${problems.join('; ')}');
}

void main() {
  GoogleFonts.config.allowRuntimeFetching = false;
  setUpAll(loadRealCairoFont);
  setUp(AppCache.clear);

  for (final width in [1280.0, 1600.0]) {
    testWidgets('Trade Marketing dropdowns never clip at ${width.toInt()}',
        (tester) async {
      tester.view.physicalSize = Size(width, 1100);
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
        home: TradeMarketingRoiScreen(
            apiClient: ApiClient(), repository: FakeTradeMarketingRepository()),
      ));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      // Toolbar: the four filters, all the same height (shared M3Dropdown).
      _expectNoClipping(tester, 'toolbar');
      final heights = {
        for (final l in ['Retail Chain', 'Month', 'Year', 'Activity Type'])
          tester
              .getSize(find.byWidgetPredicate((w) =>
                  w is DropdownMenu &&
                  w.label is Text &&
                  (w.label! as Text).data == l))
              .height
      };
      expect(heights.length, 1, reason: 'filters share one height: $heights');

      for (final button in ['Add Expense', 'ROI Simulator']) {
        final f = find.text(button);
        if (f.evaluate().isEmpty) continue;
        await tester.ensureVisible(f.first);
        await tester.tap(f.first);
        await tester.pumpAndSettle();
        _expectNoClipping(tester, button);
        await tester.tapAt(const Offset(4, 4));
        await tester.pumpAndSettle();
        if (find.byType(Dialog).evaluate().isNotEmpty ||
            find.byType(AlertDialog).evaluate().isNotEmpty) {
          Navigator.of(tester.element(find.byType(AlertDialog).first)).pop();
          await tester.pumpAndSettle();
        }
      }
    });
  }
}
