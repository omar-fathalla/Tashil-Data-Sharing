// v183 visual consistency: centered name columns, KPI even fill, مسحوب
// chip no-wrap, Pricing short title, PM→Store Matrix nav, cleanliness
// contract (open warnings alone do not lower the gauge — backend critical-only).
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tashil_web/core/network/api_client.dart';
import 'package:tashil_web/core/theme/app_theme.dart';
import 'package:tashil_web/core/widgets/m3_chip_surface.dart';
import 'package:tashil_web/core/widgets/m3_equal_height_grid.dart';
import 'package:tashil_web/core/widgets/m3_table_text.dart';
import 'package:tashil_web/core/widgets/m3_wrap_text.dart';
import 'package:tashil_web/features/data_quality/data/data_quality_repository.dart';
import 'package:tashil_web/features/data_quality/presentation/screens/data_quality_screen.dart';
import 'package:tashil_web/features/navigation/presentation/app_shell.dart';
import 'package:tashil_web/features/pricing_compliance/presentation/screens/pricing_compliance_screen.dart';
import 'package:tashil_web/features/product_master/presentation/screens/product_master_screen.dart';
import 'package:tashil_web/features/store_benchmark/presentation/screens/store_matrix_screen.dart';

import 'errors_m3_support.dart' as errors_support;
import 'pricing_m3_support.dart' as pricing_support;
import 'support/product_master_m3_support.dart';
import 'support/real_fonts.dart';

void main() {
  ignoreGoogleFontLoadErrors();
  setUpAll(() async {
    await loadRealCairoFont();
    await loadProductMasterFonts();
    await pricing_support.loadPricingFonts();
    await errors_support.loadErrorsFonts();
  });

  group('M3KpiGridColumns.forWidthAndCount', () {
    test('3 cards fill one row at ≥960; 5 cards use 3+2 not 4+1', () {
      expect(M3KpiGridColumns.forWidthAndCount(1030, 3), 3);
      expect(M3KpiGridColumns.forWidthAndCount(1030, 4), 4);
      expect(M3KpiGridColumns.forWidthAndCount(1030, 5), 3);
      expect(M3KpiGridColumns.forWidthAndCount(700, 5), 2);
      expect(M3KpiGridColumns.forWidthAndCount(400, 5), 1);
    });
  });

  group('M3TableText / M3WrapText defaults', () {
    testWidgets('shared table text defaults to center + maxLines 3',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                M3TableText('اسم صنف طويل للتحقق'),
                M3WrapText('فرع طويل للتحقق'),
              ],
            ),
          ),
        ),
      );
      final table = tester.widget<M3TableText>(find.byType(M3TableText));
      expect(table.textAlign, TextAlign.center);
      expect(table.maxLines, 3);
      expect(M3TableText.headingAlignment, MainAxisAlignment.center);

      final wrap = tester.widget<M3WrapText>(find.byType(M3WrapText).last);
      expect(wrap.textAlign, TextAlign.center);
      expect(wrap.maxLines, 3);
    });
  });

  testWidgets('Pricing page title is short one-line «Pricing & Promos»',
      (tester) async {
    await pricing_support.pumpPricing(
      tester,
      PricingComplianceScreen(apiClient: pricing_support.PricingShotApiClient()),
      width: 1280,
    );
    expect(find.text('Pricing & Promos'), findsOneWidget);
    expect(find.textContaining('Pricing & Promo Compliance'), findsNothing);
  });

  testWidgets('Product Master «مسحوب» chip stays one line (no مسحو/ب clip)',
      (tester) async {
    final errors = await pumpProductMaster(
      tester,
      width: 1280,
      height: 2400,
      withSidebar: true,
    );
    expect(errors, isEmpty);

    final chips = find.byWidgetPredicate(
      (w) =>
          w is M3ChipSurface &&
          find
              .descendant(
                of: find.byWidget(w),
                matching: find.text('مسحوب'),
              )
              .evaluate()
              .isNotEmpty,
    );
    expect(chips, findsWidgets);
    for (final e in chips.evaluate()) {
      final text = tester.widget<Text>(
        find.descendant(of: find.byWidget(e.widget), matching: find.text('مسحوب')),
      );
      expect(text.maxLines, 1);
      expect(text.softWrap, isFalse);
      final para = tester.renderObject<RenderParagraph>(
        find.descendant(
          of: find.byWidget(e.widget),
          matching: find.text('مسحوب'),
        ),
      );
      expect(para.didExceedMaxLines, isFalse);
      expect(para.size.height, lessThan(28),
          reason: 'مسحوب must paint on a single chip line');
    }
  });

  testWidgets(
      'cleanliness stays 100% when open>0 but criticalRows=0 (warnings-only)',
      (tester) async {
    // Root cause (backend, out of scope for this PR): cleanliness =
    // (totalRows - criticalRows) / totalRows. Open *warning* issues do not
    // increment CriticalRows, so the gauge can read 100.0% beside «مفتوحة 80».
    await errors_support.pumpErrors(
      tester,
      DataQualityScreen(
        dataSource: errors_support.ErrorsShotSource(
          sum: const DataQualitySummary(
            types: [],
            totalRows: 1974,
            criticalRows: 0,
            cleanlinessPct: 100,
            open: 80,
            resolved: 0,
            ignored: 0,
          ),
          list: const [],
        ),
        pollInterval: const Duration(hours: 1),
      ),
      width: 1280,
    );
    expect(find.text('100.0%'), findsOneWidget);
    // Subtitle uses countRows → «1974 صفًا» (11–99 many form).
    expect(find.textContaining('1974 من'), findsOneWidget);
    expect(find.textContaining('صف'), findsWidgets);
    expect(
      tester.widget<Text>(find.byKey(const ValueKey('dq_value_open'))).data,
      '80',
    );
  });

  testWidgets(
      'AppShell: Product Master → Store Matrix sidebar tap switches page',
      (tester) async {
    tester.view.physicalSize = const Size(1440, 1024);
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
      home: AppShell(
        apiClient: ApiClient(),
        activeTenant: 'adeco',
        onTenantChanged: (_) {},
      ),
    ));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Product Master'));
    await tester.tap(find.text('Product Master'));
    await tester.pumpAndSettle();
    expect(find.byType(ProductMasterScreen), findsOneWidget);

    // Direct jump to Store Matrix (the failure path: previously needed
    // visiting another page first when PM overflow stole sidebar hits).
    await tester.ensureVisible(find.text('Store Matrix'));
    await tester.tap(find.text('Store Matrix'));
    await tester.pumpAndSettle();
    expect(find.byType(StoreMatrixScreen), findsOneWidget);
    expect(find.textContaining('Store Matrix Benchmarking'), findsOneWidget);
  });
}
