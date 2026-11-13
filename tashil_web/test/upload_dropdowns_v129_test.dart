// v129: the Files tab upload dropdowns («السنة (اختياري)», «الشهر (اختياري)»,
// «السلسلة») never clip their value, e.g. «من الملف تلقائيًا». Real Cairo font.
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:tashil_web/core/data/app_cache.dart';
import 'package:tashil_web/core/network/api_client.dart';
import 'package:tashil_web/core/theme/app_theme.dart';
import 'package:tashil_web/features/sell_out_analytics/presentation/screens/sell_in_explorer_screen.dart';
import 'package:tashil_web/features/sell_out_analytics/presentation/screens/sell_out_explorer_screen.dart';

import 'support/real_fonts.dart';

/// Every visible DropdownMenu field must show its whole value (or hint).
List<String> _clippedDropdowns(WidgetTester tester) {
  final out = <String>[];
  for (final e in find
      .byType(DropdownMenu<int>)
      .evaluate()
      .followedBy(find.byType(DropdownMenu<String>).evaluate())) {
    final dd = e.widget as DropdownMenu;
    final label = dd.label is Text ? (dd.label! as Text).data : '?';
    final editable = find.descendant(
        of: find.byElementPredicate((x) => x == e),
        matching: find.byType(EditableText));
    if (editable.evaluate().isEmpty) continue;
    final et = tester.widget<EditableText>(editable.first);
    final text = et.controller.text;
    if (text.isEmpty) continue;
    final box = tester.renderObject<RenderBox>(editable.first);
    final tp = TextPainter(
      text: TextSpan(text: text, style: et.style),
      textDirection: Directionality.of(e),
      textScaler: MediaQuery.textScalerOf(e),
      maxLines: 1,
    )..layout();
    if (tp.width > box.size.width + 0.5) {
      out.add('$label: "$text" ${tp.width.toStringAsFixed(1)} > '
          '${box.size.width.toStringAsFixed(1)}');
    }
  }
  return out;
}

Future<void> _openFiles(WidgetTester tester) async {
  await tester.tap(find.textContaining('الملفات المرفوعة').first);
  await tester.pumpAndSettle();
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

  for (final width in [1280.0, 1888.0]) {
    for (final (name, build) in [
      (
        'Sell-In',
        () =>
            SellInExplorerScreen(apiClient: ApiClient(tenantId: 'tenant-adeco'))
      ),
      (
        'Sell-Out',
        () => SellOutExplorerScreen(
            apiClient: ApiClient(tenantId: 'tenant-adeco'))
      ),
    ]) {
      testWidgets(
          '$name files tab: upload dropdowns show their full value '
          'at ${width.toInt()}', (tester) async {
        await _pump(tester, build(), width);
        await _openFiles(tester);
        expect(find.text('السنة (اختياري)'), findsWidgets);
        expect(find.text('الشهر (اختياري)'), findsWidgets);
        expect(_clippedDropdowns(tester), isEmpty);
      });
    }
  }
}
