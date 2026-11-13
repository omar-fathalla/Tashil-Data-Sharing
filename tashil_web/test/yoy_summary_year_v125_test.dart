// v125: Trade Marketing "Year" dropdown must not clip its value.
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tashil_web/core/data/app_cache.dart';
import 'package:tashil_web/core/network/api_client.dart';
import 'package:tashil_web/core/theme/app_theme.dart';
import 'package:tashil_web/features/trade_marketing/presentation/screens/trade_marketing_roi_screen.dart';

import 'package:google_fonts/google_fonts.dart';

import 'support/real_fonts.dart';
import 'trade_marketing_roi_test.dart' show FakeTradeMarketingRepository;

void main() {
  GoogleFonts.config.allowRuntimeFetching = false;
  setUpAll(loadRealCairoFont);
  setUp(AppCache.clear);

  for (final width in [1600.0, 1280.0]) {
    testWidgets('Trade Marketing Year dropdown fits every option at ${width.toInt()}',
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

      final menu = find.byWidgetPredicate((w) =>
          w is DropdownMenu<int> && w.label is Text && (w.label! as Text).data == 'Year');
      expect(menu, findsOneWidget);
      final editable = find.descendant(of: menu, matching: find.byType(EditableText));
      final field = tester.renderObject<RenderBox>(editable);
      final style = tester.widget<EditableText>(editable).style;
      for (final label in ['2026', '2025', 'All Years']) {
        final tp = TextPainter(
          text: TextSpan(text: label, style: style),
          textDirection: TextDirection.ltr,
          textScaler: MediaQuery.textScalerOf(tester.element(editable)),
        )..layout();
        expect(tp.width, lessThanOrEqualTo(field.size.width),
            reason: '"$label" (${tp.width.toStringAsFixed(1)}dp) must fit the '
                'field (${field.size.width.toStringAsFixed(1)}dp)');
      }
    });
  }
}
