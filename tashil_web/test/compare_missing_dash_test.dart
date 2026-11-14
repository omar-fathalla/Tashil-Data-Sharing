// Compare missing-data honesty: never fake 100.0% / 0.00 / +0.0% when
// competitor prices or MoM series are absent — show «—» + Arabic note.
// Real Cairo font; made-up fixtures only.
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:tashil_web/core/data/app_cache.dart';
import 'package:tashil_web/core/network/api_client.dart';
import 'package:tashil_web/core/theme/app_theme.dart';
import 'package:tashil_web/features/competitor_comparison/presentation/screens/competitor_comparison_screen.dart';

import 'support/compare_fixture.dart';
import 'support/real_fonts.dart';

Future<void> _pump(WidgetTester tester, Widget page) async {
  tester.view.physicalSize = const Size(1280, 3200);
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
      textDirection: TextDirection.rtl,
      child: Scaffold(body: page),
    ),
  ));
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 200));
  }
}

Widget _compare(List<OwnSkuCompetitiveGroupModel> groups) =>
    CompetitorComparisonScreen(
      apiClient: ApiClient(tenantId: 'tenant-adeco', allowMockFallback: false),
      repository: CompareFakeRepo(groups),
    );

void main() {
  GoogleFonts.config.allowRuntimeFetching = false;
  setUpAll(loadRealCairoFont);
  setUp(AppCache.clear);

  testWidgets(
      'no competitor prices: price-index KPI is «—», not fake 100.0%',
      (tester) async {
    await _pump(tester, _compare(compareUnmappedShortSeriesGroups()));
    expect(find.textContaining('100.0%'), findsNothing);
    expect(find.textContaining('+0.0%'), findsNothing);
    expect(find.text('—'), findsWidgets);
    expect(find.text('لا توجد أسعار منافسين للمقارنة'), findsOneWidget);
  });

  testWidgets(
      'unmapped spotlight: avg competitor + period change use «—» notes',
      (tester) async {
    await _pump(tester, _compare(compareUnmappedShortSeriesGroups()));
    final avg = find.byKey(const ValueKey('compare_spotlight_avg_comp'));
    expect(avg, findsOneWidget);
    expect(find.descendant(of: avg, matching: find.text('—')), findsOneWidget);
    expect(find.descendant(of: avg, matching: find.text('لم يتم تحديد المنافسين بعد')),
        findsOneWidget);

    final change =
        find.byKey(const ValueKey('compare_spotlight_period_change'));
    expect(change, findsOneWidget);
    expect(
        find.descendant(of: change, matching: find.text('—')), findsOneWidget);
    expect(
        find.descendant(
            of: change,
            matching: find.text('لا توجد بيانات كافية لحساب التغير')),
        findsOneWidget);

    expect(find.text('غير مقارن'), findsWidgets);
    expect(find.textContaining('مساوي لمتوسط السوق'), findsNothing);
    expect(find.textContaining('0.00 ج.م'), findsNothing);
  });

  testWidgets('mapped fixture still shows a real competitive index',
      (tester) async {
    await _pump(tester, _compare(compareFixtureGroups()));
    expect(find.text('106.7%'), findsWidgets);
    expect(find.textContaining('لا توجد أسعار منافسين للمقارنة'), findsNothing);
  });
}
