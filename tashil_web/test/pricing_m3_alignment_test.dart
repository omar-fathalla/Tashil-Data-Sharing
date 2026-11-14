// Pricing & Promos: Sell-Out / Sell-In table, typography and card symmetry.
// Real Cairo font, 1280 and 1024 content widths. Made-up fixture names.
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tashil_web/core/data/app_cache.dart';
import 'package:tashil_web/core/network/api_client.dart';
import 'package:tashil_web/core/theme/app_theme.dart';
import 'package:tashil_web/core/widgets/m3_chip_surface.dart';
import 'package:tashil_web/core/widgets/m3_section_title.dart';
import 'package:tashil_web/core/widgets/m3_summary_kpi_card.dart';
import 'package:tashil_web/features/pricing_compliance/presentation/screens/pricing_compliance_screen.dart';
import 'package:tashil_web/features/sell_out_analytics/presentation/screens/sell_out_explorer_screen.dart';

import 'pricing_m3_support.dart';

List<String> _cutBeforeThreeLines(WidgetTester tester, Finder scope,
    {bool Function(Text t)? only}) {
  final out = <String>[];
  for (final e
      in find.descendant(of: scope, matching: find.byType(Text)).evaluate()) {
    final t = e.widget as Text;
    if (only != null && !only(t)) continue;
    final p = tester
        .renderObject<RenderParagraph>(find.byElementPredicate((x) => x == e));
    if (p.didExceedMaxLines && (t.maxLines ?? 99) < 3) {
      out.add('"${t.data}" cut at maxLines ${t.maxLines}');
    }
  }
  return out;
}

List<String> _clippedDropdowns(WidgetTester tester) {
  final out = <String>[];
  for (final e in find
      .byType(DropdownMenu<int>)
      .evaluate()
      .followedBy(find.byType(DropdownMenu<String>).evaluate())) {
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
      out.add('"$text" ${tp.width.toStringAsFixed(1)} > '
          '${box.size.width.toStringAsFixed(1)}');
    }
  }
  return out;
}

_CardMetrics _metrics(WidgetTester tester, Finder card) {
  expect(card, findsOneWidget);
  final container = tester.widget<Container>(
      find.descendant(of: card, matching: find.byType(Container)).first);
  final padding = container.padding! as EdgeInsets;
  final icon = tester.widget<Icon>(
      find.descendant(of: card, matching: find.byType(Icon)).first);
  final titleText = tester.widget<Text>(find.descendant(
      of: find.descendant(of: card, matching: find.byType(M3SectionTitle)),
      matching: find.byType(Text)));
  final values = find.descendant(
      of: card,
      matching: find.byWidgetPredicate((w) =>
          w is Text &&
          (w).key is ValueKey &&
          (w.key as ValueKey).value.toString().startsWith('kpi_value_')));
  // Fall back to the first headline-ish text after the title.
  Text? value;
  if (values.evaluate().isNotEmpty) {
    value = tester.widget<Text>(values.first);
  } else {
    final texts = tester
        .widgetList<Text>(
            find.descendant(of: card, matching: find.byType(Text)))
        .toList();
    value = texts.length > 1 ? texts[1] : texts.first;
  }
  return _CardMetrics(
    padding: padding,
    iconSize: icon.size ?? 0,
    titleStyle: titleText.style,
    valueStyle: value.style,
    size: tester.getSize(card),
  );
}

class _CardMetrics {
  _CardMetrics({
    required this.padding,
    required this.iconSize,
    required this.titleStyle,
    required this.valueStyle,
    required this.size,
  });
  final EdgeInsets padding;
  final double iconSize;
  final TextStyle? titleStyle;
  final TextStyle? valueStyle;
  final Size size;
}

void main() {
  ignoreGoogleFontLoadErrors();
  setUpAll(loadPricingFonts);
  setUp(AppCache.clear);

  testWidgets(
      'empty load: compliance + promo KPIs show «—» notes, not fake 100.0% / 0.0%',
      (tester) async {
    await pumpPricing(
      tester,
      PricingComplianceScreen(apiClient: PricingEmptyApiClient()),
      width: 1280,
    );
    expect(find.textContaining('100.0%'), findsNothing);
    expect(find.textContaining('+0.0%'), findsNothing);
    expect(find.textContaining('0.0%'), findsNothing);

    final compliance =
        tester.widget<Text>(find.byKey(const ValueKey('kpi_value_Compliance Rate')));
    expect(compliance.data, '—');
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('kpi_subtitle_Compliance Rate')))
          .data,
      'لا توجد أصناف لحساب الالتزام',
    );

    final promo =
        tester.widget<Text>(find.byKey(const ValueKey('kpi_value_Avg Promo Uplift')));
    expect(promo.data, '—');
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('kpi_subtitle_Avg Promo Uplift')))
          .data,
      'لا توجد أصناف لحساب الأثر الترويجي',
    );

    // Status chips use M3ChipSurface geometry (empty → no table chips, but
    // KPI dash honesty is the P0 empty-state contract).
    expect(find.byKey(const ValueKey('pricing_empty')), findsOneWidget);
  });

  testWidgets(
      'items without promos: avg uplift is «—» + Arabic note, not fake 0.0%',
      (tester) async {
    await pumpPricing(
      tester,
      PricingComplianceScreen(apiClient: PricingNoPromoApiClient()),
      width: 1280,
    );
    expect(find.textContaining('100.0%'), findsNothing);
    final promo =
        tester.widget<Text>(find.byKey(const ValueKey('kpi_value_Avg Promo Uplift')));
    expect(promo.data, '—');
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('kpi_subtitle_Avg Promo Uplift')))
          .data,
      'لا توجد عروض نشطة للمقارنة',
    );
    // Compliance still has a real rate from the fixture.
    final compliance =
        tester.widget<Text>(find.byKey(const ValueKey('kpi_value_Compliance Rate')));
    expect(compliance.data, isNot('—'));
    expect(compliance.data, isNot('100.0%'));
    expect(find.text('بدون عرض'), findsWidgets);
    expect(find.text('أثر ترويجي'), findsNothing);
  });

  testWidgets(
      'populated fixture keeps real compliance % and short status chips',
      (tester) async {
    await pumpPricing(
      tester,
      PricingComplianceScreen(apiClient: PricingShotApiClient()),
      width: 1280,
    );
    expect(find.text('33.3%'), findsOneWidget);
    expect(find.textContaining('لا توجد أصناف لحساب الالتزام'), findsNothing);
    expect(find.text('حرق سعر'), findsWidgets);
    expect(find.text('مطابق'), findsWidgets);
    expect(find.text('زيادة سعر'), findsWidgets);
    expect(find.text('أثر ترويجي'), findsWidgets);
    expect(find.text('بدون عرض'), findsWidgets);
    expect(find.byType(M3ChipSurface), findsWidgets);
  });

  for (final width in [1280.0, 1024.0]) {
    testWidgets(
        'Pricing table wraps to 3 lines and centres cells at ${width.toInt()}',
        (tester) async {
      await pumpPricing(
        tester,
        PricingComplianceScreen(apiClient: PricingShotApiClient()),
        width: width,
      );
      final table = find.byKey(const ValueKey('pricing_compliance_table'));
      expect(table, findsOneWidget);

      final names = find.byKey(const ValueKey('pricing_sku_name'));
      expect(names, findsWidgets);
      for (final t in tester.widgetList<Text>(names)) {
        expect(t.maxLines, 3);
        expect(t.textAlign, TextAlign.center);
      }
      final stores = find.byKey(const ValueKey('pricing_store_name'));
      expect(stores, findsWidgets);
      for (final t in tester.widgetList<Text>(stores)) {
        expect(t.maxLines, 3);
        expect(t.textAlign, TextAlign.center);
      }
      expect(_cutBeforeThreeLines(tester, table), isEmpty);

      final dt = tester.widget<DataTable>(table);
      for (final (i, c) in dt.columns.indexed) {
        expect(c.headingRowAlignment, MainAxisAlignment.center,
            reason: 'column $i');
      }

      expect(_clippedDropdowns(tester), isEmpty);

      // Long KPI titles and detail lines are not cut before 3 lines.
      final grid = find.byKey(const ValueKey('pricing_kpi_grid'));
      expect(grid, findsOneWidget);
      expect(_cutBeforeThreeLines(tester, grid), isEmpty);
    });
  }

  testWidgets(
      'Pricing KPI card padding, fonts and icon size match the Sell-Out reference',
      (tester) async {
    // 1. Sell-Out reference card at 1280 (4-up row).
    tester.view.physicalSize = const Size(1280, 2400);
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
        child: Scaffold(body: SellOutExplorerScreen(apiClient: ApiClient())),
      ),
    ));
    await tester.pumpAndSettle();

    final soCard = find.byKey(const ValueKey('kpi_card_Net Sales (EGP)'));
    expect(soCard, findsOneWidget);
    final so = _metrics(tester, soCard);
    expect(so.padding, M3SummaryKpiStyle.padding);
    expect(so.iconSize, M3SummaryKpiStyle.iconSize);

    // 2. Pricing card — same padding, icon size, title/value typography.
    await pumpPricing(
      tester,
      PricingComplianceScreen(apiClient: PricingShotApiClient()),
      width: 1280,
    );
    final prCard = find.byKey(const ValueKey('kpi_card_Compliance Rate'));
    expect(prCard, findsOneWidget);
    final pr = _metrics(tester, prCard);
    expect(pr.padding, so.padding);
    expect(pr.iconSize, so.iconSize);
    expect(pr.titleStyle?.fontSize, so.titleStyle?.fontSize);
    expect(pr.titleStyle?.fontWeight, so.titleStyle?.fontWeight);
    expect(pr.titleStyle?.fontFamily, so.titleStyle?.fontFamily);
    expect(pr.valueStyle?.fontSize, so.valueStyle?.fontSize);
    expect(pr.valueStyle?.fontWeight, so.valueStyle?.fontWeight);
    expect(pr.valueStyle?.fontFamily, so.valueStyle?.fontFamily);

    // 3. Same text + same width → same height as the Sell-Out card.
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light(),
      locale: const Locale('ar'),
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('ar'), Locale('en')],
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          body: SellOutExplorerScreen(apiClient: ApiClient()),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    final soAgain = find.byKey(const ValueKey('kpi_card_Net Sales (EGP)'));
    final soH = tester.getSize(soAgain).height;
    final soW = tester.getSize(soAgain).width;
    final soTitleText = tester
        .widget<M3SectionTitle>(
            find.descendant(of: soAgain, matching: find.byType(M3SectionTitle)))
        .text;
    final soValue = tester
        .widget<Text>(find.byKey(const ValueKey('kpi_value_Net Sales (EGP)')))
        .data!;
    // Subtitle is the last Text in the card.
    final soTexts = tester
        .widgetList<Text>(
            find.descendant(of: soAgain, matching: find.byType(Text)))
        .toList();
    final soSub = soTexts.last.data ?? '';
    final soIcon = tester
        .widget<Icon>(
            find.descendant(of: soAgain, matching: find.byType(Icon)).first)
        .icon!;
    final soColor = tester
        .widget<Icon>(
            find.descendant(of: soAgain, matching: find.byType(Icon)).first)
        .color!;

    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light(),
      locale: const Locale('ar'),
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          body: Align(
            alignment: Alignment.topCenter,
            child: SizedBox(
              width: soW,
              child: IntrinsicHeight(
                child: M3SummaryKpiCard(
                  key: const ValueKey('kpi_card_Net Sales (EGP)'),
                  title: soTitleText,
                  titleMaxLines: 1,
                  subtitleMaxLines: 1,
                  value: soValue,
                  subtitle: soSub,
                  icon: soIcon,
                  color: soColor,
                ),
              ),
            ),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    final clone = find.byKey(const ValueKey('kpi_card_Net Sales (EGP)'));
    expect(tester.getSize(clone).height, closeTo(soH, 1.0));
  });
}
