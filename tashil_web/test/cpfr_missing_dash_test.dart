// CPFR missing-data honesty: never fake +0.0% / 0.00 when matched YoY,
// chain margin, W1+W2, EXP, promo or returns baselines are absent —
// show «—» + Arabic note (Sell-Out / TM gold). Made-up fixtures only.
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:tashil_web/core/data/app_cache.dart';
import 'package:tashil_web/core/theme/app_theme.dart';
import 'package:tashil_web/features/cpfr_replenishment/presentation/screens/cpfr_dashboard_screen.dart';

import 'support/cpfr_fixtures.dart';
import 'support/real_fonts.dart';

Future<void> _pump(WidgetTester tester, Widget page) async {
  tester.view.physicalSize = const Size(1280, 4000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(),
      locale: const Locale('ar'),
      supportedLocales: const [Locale('ar'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(body: page),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  GoogleFonts.config.allowRuntimeFetching = false;
  setUpAll(loadRealCairoFont);
  setUp(AppCache.clear);

  testWidgets(
    'no last-year / matched sell-out: YoY + margin are «—», not fake +0.0%',
    (tester) async {
      await _pump(
        tester,
        CPFRDashboardScreen(apiClient: MissingDashCPFRApiClient()),
      );
      expect(tester.takeException(), isNull);

      final yoy = tester.widget<Text>(
        find.byKey(const ValueKey('kpi_value_Sell-Out Growth YoY')),
      );
      expect(yoy.data, '—');
      expect(
        tester
            .widget<Text>(
              find.byKey(const ValueKey('kpi_subtitle_Sell-Out Growth YoY')),
            )
            .data,
        'لا توجد بيانات للعام السابق',
      );

      final margin = tester.widget<Text>(
        find.byKey(const ValueKey('kpi_value_Chain Margin')),
      );
      expect(margin.data, '—');
      expect(find.textContaining('+0.0%'), findsNothing);
      expect(find.text('0.0%'), findsNothing);
    },
  );

  testWidgets(
    'empty forecast period: W1+W2 / EXP / promo / returns use «—» notes',
    (tester) async {
      await _pump(
        tester,
        CPFRDashboardScreen(apiClient: MissingDashCPFRApiClient()),
      );
      await tester.tap(find.text('Demand Forecasting & Promos (EXP)').first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(tester.takeException(), isNull);

      expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('kpi_value_W1+W2 actual')))
            .data,
        '—',
      );
      expect(
        tester
            .widget<Text>(
              find.byKey(const ValueKey('kpi_subtitle_W1+W2 actual')),
            )
            .data,
        'لا توجد بيانات للفترة',
      );
      expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('kpi_value_Projected EXP')))
            .data,
        '—',
      );
      expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('kpi_value_Promotions')))
            .data,
        '—',
      );
      expect(
        tester
            .widget<Text>(
              find.byKey(const ValueKey('kpi_subtitle_Promotions')),
            )
            .data,
        'لا توجد عروض في الفترة',
      );
      expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('kpi_value_Returns Rate')))
            .data,
        '—',
      );
      expect(
        tester
            .widget<Text>(
              find.byKey(const ValueKey('kpi_subtitle_Returns Rate')),
            )
            .data,
        'لا توجد مرتجعات في الفترة',
      );
      expect(find.textContaining('0.00%'), findsNothing);
      expect(find.textContaining('+0.0%'), findsNothing);
    },
  );

  testWidgets('rich fixture still shows real YoY / forecast values', (
    tester,
  ) async {
    await _pump(tester, CPFRDashboardScreen(apiClient: RichCPFRApiClient()));
    final yoy = tester.widget<Text>(
      find.byKey(const ValueKey('kpi_value_Sell-Out Growth YoY')),
    );
    expect(yoy.data, isNot('—'));
    expect(yoy.data, contains('%'));
    expect(find.text('لا توجد بيانات للعام السابق'), findsNothing);

    await tester.tap(find.text('Demand Forecasting & Promos (EXP)').first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('kpi_value_W1+W2 actual')))
          .data,
      isNot('—'),
    );
    expect(find.text('لا توجد بيانات للفترة'), findsNothing);
  });
}
