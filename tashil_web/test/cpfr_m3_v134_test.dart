// v134+: apply Sell-Out / Sell-In table, dropdown, chip and KPI-card rules
// to the CPFR Replenishment page. Real Cairo font, 1280 and 1024dp.
// All names and numbers are made-up fixtures.
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:tashil_web/core/data/app_cache.dart';
import 'package:tashil_web/core/network/api_client.dart';
import 'package:tashil_web/core/theme/app_theme.dart';
import 'package:tashil_web/core/theme/m3_spacing.dart';
import 'package:tashil_web/core/widgets/m3_dropdown.dart';
import 'package:tashil_web/core/widgets/m3_section_title.dart';
import 'package:tashil_web/core/widgets/m3_summary_kpi_card.dart';
import 'package:tashil_web/core/widgets/table_scroll_container.dart';
import 'package:tashil_web/features/cpfr_replenishment/presentation/screens/cpfr_dashboard_screen.dart';
import 'package:tashil_web/features/sell_out_analytics/presentation/screens/sell_out_explorer_screen.dart';

import 'support/cpfr_fixtures.dart';
import 'support/real_fonts.dart';

Future<void> _pump(
  WidgetTester tester,
  Widget page, {
  double width = 1280,
  double height = 4000,
}) async {
  tester.view.physicalSize = Size(width, height);
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

List<String> _clippedDropdowns(WidgetTester tester) {
  final out = <String>[];
  for (final e in find
      .byType(DropdownMenu<int>)
      .evaluate()
      .followedBy(find.byType(DropdownMenu<String>).evaluate())
      .followedBy(find.byType(DropdownMenu<String?>).evaluate())) {
    final editable = find.descendant(
      of: find.byElementPredicate((x) => x == e),
      matching: find.byType(EditableText),
    );
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
      out.add(
        '"$text" ${tp.width.toStringAsFixed(1)} > '
        '${box.size.width.toStringAsFixed(1)}',
      );
    }
  }
  return out;
}

class _KpiMetrics {
  _KpiMetrics({
    required this.padding,
    required this.height,
    required this.iconSize,
    required this.titleSize,
    required this.titleWeight,
    required this.titleFamily,
    required this.valueSize,
    required this.valueWeight,
  });

  final EdgeInsetsGeometry? padding;
  final double height;
  final double? iconSize;
  final double? titleSize;
  final FontWeight? titleWeight;
  final String? titleFamily;
  final double? valueSize;
  final FontWeight? valueWeight;
}

_KpiMetrics _readKpi(WidgetTester tester, Key key, Key valueKey) {
  final card = find.byKey(key);
  expect(card, findsOneWidget, reason: '$key missing');
  final widget = tester.widget(card);
  EdgeInsetsGeometry? padding;
  if (widget is Container) padding = widget.padding;
  if (widget is M3SummaryKpiCard) padding = M3SummaryKpiStyle.padding;
  final icon = tester.widget<Icon>(
    find.descendant(of: card, matching: find.byType(Icon)).first,
  );
  final title = tester.widget<M3SectionTitle>(
    find.descendant(of: card, matching: find.byType(M3SectionTitle)).first,
  );
  final titleText = tester.widget<Text>(
    find
        .descendant(of: find.byWidget(title), matching: find.byType(Text))
        .first,
  );
  final value = tester.widget<Text>(find.byKey(valueKey));
  final ctx = tester.element(card);
  final titleStyle = titleText.style ?? M3SectionTitle.styleOf(ctx);
  return _KpiMetrics(
    padding: padding,
    height: tester.getRect(card).height,
    iconSize: icon.size,
    titleSize: titleStyle?.fontSize,
    titleWeight: titleStyle?.fontWeight,
    titleFamily: titleStyle?.fontFamily,
    valueSize: value.style?.fontSize,
    valueWeight: value.style?.fontWeight,
  );
}

void main() {
  GoogleFonts.config.allowRuntimeFetching = false;
  setUpAll(loadRealCairoFont);
  setUp(AppCache.clear);

  testWidgets(
    'KPI card height, padding, title/value fonts and icon match Sell-Out',
    (tester) async {
      await _pump(
        tester,
        SellOutExplorerScreen(apiClient: ApiClient(tenantId: 'tenant-adeco')),
        height: 3000,
      );
      const sellOutKey = ValueKey('kpi_card_Net Sales (EGP)');
      const sellOutValue = ValueKey('kpi_value_Net Sales (EGP)');
      final sellOut = _readKpi(tester, sellOutKey, sellOutValue);

      await _pump(tester, CPFRDashboardScreen(apiClient: RichCPFRApiClient()));
      const cpfrKey = ValueKey('kpi_card_Sell-In');
      const cpfrValue = ValueKey('kpi_value_Sell-In');
      final cpfr = _readKpi(tester, cpfrKey, cpfrValue);

      expect(sellOut.padding, const EdgeInsets.all(M3Spacing.sm));
      expect(cpfr.padding, sellOut.padding);
      expect(sellOut.iconSize, M3SummaryKpiStyle.iconSize);
      expect(cpfr.iconSize, sellOut.iconSize);
      expect(cpfr.titleSize, sellOut.titleSize);
      expect(cpfr.titleWeight, sellOut.titleWeight);
      expect(cpfr.titleFamily, sellOut.titleFamily);
      expect(cpfr.valueSize, sellOut.valueSize);
      expect(cpfr.valueWeight, FontWeight.w900);
      expect(sellOut.valueWeight, FontWeight.w900);

      // Height: same short one-line content, same width. CPFR allows titles and
      // details to wrap further, but a one-line title+detail must match Sell-Out.
      const title = 'صافي المبيعات';
      const value = '1.25M ج.م';
      const subtitle = 'تفاصيل سطر واحد';
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          locale: const Locale('ar'),
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: Scaffold(
              body: Builder(
                builder: (context) {
                  final color = Theme.of(context).colorScheme.primary;
                  return Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        Expanded(
                          child: M3SummaryKpiCard(
                            key: const ValueKey('ref_height'),
                            title: title,
                            value: value,
                            subtitle: subtitle,
                            icon: Icons.payments_rounded,
                            color: color,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: M3SummaryKpiCard(
                            key: const ValueKey('cpfr_height'),
                            title: title,
                            value: value,
                            subtitle: subtitle,
                            icon: Icons.payments_rounded,
                            color: color,
                            titleMaxLines: null,
                            subtitleMaxLines: 3,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      final refH =
          tester.getRect(find.byKey(const ValueKey('ref_height'))).height;
      final cpfrH =
          tester.getRect(find.byKey(const ValueKey('cpfr_height'))).height;
      expect(
        cpfrH,
        closeTo(refH, 0.5),
        reason: 'same-content height CPFR $cpfrH vs Sell-Out $refH',
      );
    },
  );

  testWidgets('CPFR dashboard KPI cards use the shared Sell-Out card metrics', (
    tester,
  ) async {
    await _pump(tester, CPFRDashboardScreen(apiClient: RichCPFRApiClient()));
    expect(tester.takeException(), isNull);
    final card = find.byKey(const ValueKey('kpi_card_Sell-In'));
    expect(card, findsOneWidget);
    expect(tester.widget(card), isA<M3SummaryKpiCard>());
    final pad = M3SummaryKpiStyle.padding;
    expect(pad, const EdgeInsets.all(16.0));
    final icon = tester.widget<Icon>(
      find.descendant(of: card, matching: find.byType(Icon)),
    );
    expect(icon.size, M3SummaryKpiStyle.iconSize);
    expect(icon.size, 20.0);
    final title = tester.widget<M3SectionTitle>(
      find.descendant(of: card, matching: find.byType(M3SectionTitle)),
    );
    expect(title.maxLines, 1);
    final value = tester.widget<Text>(
      find.byKey(const ValueKey('kpi_value_Sell-In')),
    );
    expect(value.style?.fontWeight, FontWeight.w900);
    final sub = tester.widget<Text>(
      find.byKey(const ValueKey('kpi_subtitle_Sell-In')),
    );
    expect(sub.maxLines, 1);
  });

  for (final width in [1280.0, 1024.0]) {
    testWidgets(
        'reconciliation table uses TableScrollContainer at '
        '${width.toInt()}, no 1450 min width', (tester) async {
      await _pump(
        tester,
        CPFRDashboardScreen(apiClient: RichCPFRApiClient()),
        width: width,
      );
      expect(tester.takeException(), isNull);
      final table = find.byKey(const ValueKey('cpfr_reconciliation_table'));
      expect(table, findsOneWidget);
      expect(table.evaluate().first.widget, isA<TableScrollContainer>());
      // The old forced minWidth: 1450 is gone — the container stretches
      // the DataTable to the available width (fit-before-scroll).
      final dt = tester.widget<DataTable>(
        find.descendant(of: table, matching: find.byType(DataTable)),
      );
      expect(dt.rows, isNotEmpty);
      final tableBox = tester.getRect(table);
      final dataBox = tester.getRect(
        find.descendant(of: table, matching: find.byType(DataTable)),
      );
      expect(
        dataBox.width,
        greaterThanOrEqualTo(tableBox.width - 2.0),
        reason: 'table should fill the container width at $width',
      );
      // All headings stay centred (item-name column does not exist here).
      for (final c in dt.columns) {
        expect(c.headingRowAlignment, MainAxisAlignment.center);
      }
    });
  }

  testWidgets('period status is a short chip with the description underneath', (
    tester,
  ) async {
    await _pump(tester, CPFRDashboardScreen(apiClient: RichCPFRApiClient()));
    expect(find.text('مغلق'), findsOneWidget);
    expect(find.text('Full Month'), findsOneWidget);
    expect(find.text('مفتوح'), findsOneWidget);
    // The long raw backend label is no longer the chip text.
    expect(find.text('مغلق (Full Month)'), findsNothing);
  });

  testWidgets('dropdowns never clip their value; fitOptions is on', (
    tester,
  ) async {
    await _pump(
      tester,
      CPFRDashboardScreen(apiClient: RichCPFRApiClient()),
      width: 1024,
    );
    expect(_clippedDropdowns(tester), isEmpty);
    // Every dropdown on the page opts into fitOptions.
    for (final d in tester.widgetList<M3Dropdown<String>>(
      find.byType(M3Dropdown<String>),
    )) {
      expect(d.fitOptions, isTrue);
    }
    for (final d in tester.widgetList<M3Dropdown<int>>(
      find.byType(M3Dropdown<int>),
    )) {
      expect(d.fitOptions, isTrue);
    }
  });

  testWidgets('Suggested PO, returns and reps names wrap up to 3 lines', (
    tester,
  ) async {
    await _pump(tester, CPFRDashboardScreen(apiClient: RichCPFRApiClient()));

    await tester.tap(find.text('Suggested PO & Replenishment').first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(tester.takeException(), isNull);
    final poName = find.byKey(const ValueKey('cpfr_po_sku_name'));
    expect(poName, findsWidgets);
    expect(tester.widget<Text>(poName.first).maxLines, 3);
    final poP = tester.renderObject<RenderParagraph>(poName.first);
    expect(poP.didExceedMaxLines, isFalse);
    expect(
      poP.size.height,
      greaterThan(1.5 * (poP.text.style?.fontSize ?? 14) * 1.2),
    );
    // Status chip is short, description sits under it.
    expect(find.text('نفاد عاجل'), findsOneWidget);
    expect(find.text('يحتاج توريد فوري'), findsOneWidget);

    await tester.tap(find.text('Demand Forecasting & Promos (EXP)').first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    final retName = find.byKey(const ValueKey('cpfr_returns_sku_name'));
    expect(retName, findsWidgets);
    expect(tester.widget<Text>(retName.first).maxLines, 3);
    expect(
      tester.renderObject<RenderParagraph>(retName.first).didExceedMaxLines,
      isFalse,
    );

    await tester.tap(find.text('أداء فريق المبيعات وهيكل الحسابات').first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    final rep = find.byKey(const ValueKey('cpfr_rep_name'));
    expect(rep, findsWidgets);
    expect(tester.widget<Text>(rep.first).maxLines, 3);
    expect(
      tester.renderObject<RenderParagraph>(rep.first).didExceedMaxLines,
      isFalse,
    );
  });
}
