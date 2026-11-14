// OOS Monitor: Sell-Out table, typography and card symmetry.
// Real Cairo font, 1280 and 1024. Long live-like fixture values.
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tashil_web/core/data/app_cache.dart';
import 'package:tashil_web/core/network/api_client.dart';
import 'package:tashil_web/core/theme/app_theme.dart';
import 'package:tashil_web/core/widgets/m3_chip_surface.dart';
import 'package:tashil_web/core/widgets/m3_section_title.dart';
import 'package:tashil_web/core/widgets/m3_equal_height_grid.dart';
import 'package:tashil_web/core/widgets/m3_summary_kpi_card.dart';
import 'package:tashil_web/core/widgets/table_scroll_container.dart';
import 'package:tashil_web/features/oos_monitor/presentation/screens/oos_dashboard_screen.dart';
import 'package:tashil_web/features/sell_out_analytics/presentation/screens/sell_out_explorer_screen.dart';

import 'oos_m3_support.dart';

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

bool _valueIsOneLine(WidgetTester tester, Finder valueFinder) {
  expect(valueFinder, findsOneWidget);
  final el = valueFinder.evaluate().single;
  final text = el.widget as Text;
  final p = tester.renderObject<RenderParagraph>(
      find.byElementPredicate((x) => x == el));
  final tp = TextPainter(
    text: TextSpan(text: text.data, style: text.style ?? p.text.style),
    textDirection: Directionality.of(el),
    textScaler: MediaQuery.textScalerOf(el),
    maxLines: 1,
  )..layout(maxWidth: p.size.width);
  return (p.size.height - tp.height).abs() <= 1.5 && !p.didExceedMaxLines;
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
          w.key is ValueKey &&
          (w.key as ValueKey).value.toString().startsWith('kpi_value_')));
  Text value;
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

Future<void> _pumpSellOut(WidgetTester tester, {required double width}) async {
  tester.view.physicalSize = Size(width, 2400);
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
}

void main() {
  ignoreGoogleFontLoadErrors();
  setUpAll(loadOosFonts);
  setUp(AppCache.clear);

  for (final width in [1280.0, 1024.0]) {
    testWidgets(
        'OOS alerts wrap to 3 lines and dropdowns fit at ${width.toInt()}',
        (tester) async {
      await pumpOos(
        tester,
        OOSDashboardScreen(apiClient: OosShotApiClient()),
        width: width,
      );
      expect(find.byKey(const ValueKey('oos_kpi_grid')), findsOneWidget);
      if (width >= 960) {
        expect(
          tester
              .widget<M3EqualHeightGrid>(
                  find.byKey(const ValueKey('oos_kpi_grid')))
              .columns,
          4,
          reason: 'OOS must use Sell-Out 4-col breakpoints at ${width.toInt()}',
        );
      }
      expect(_cutBeforeThreeLines(tester, find.byKey(const ValueKey('oos_kpi_grid'))),
          isEmpty);
      expect(find.byKey(const ValueKey('oos_sku_name')), findsWidgets);
      for (final t in tester.widgetList<Text>(find.byKey(const ValueKey('oos_sku_name')))) {
        expect(t.maxLines, 3);
      }
      expect(find.byKey(const ValueKey('oos_store_name')), findsWidgets);
      for (final t in tester.widgetList<Text>(find.byKey(const ValueKey('oos_store_name')))) {
        expect(t.maxLines, 3);
      }
      // Search hints stay one line; M3SearchFieldWidth must show them in full.
      // Long content (KPI / SKU / store) must not be cut before 3 lines.
      expect(
        _cutBeforeThreeLines(
          tester,
          find.byType(OOSDashboardScreen),
          only: (text) =>
              text.data !=
              'بحث بالصنف أو الكرتونة أو الباركود أو اسم الفرع...',
        ),
        isEmpty,
      );
      expect(_clippedDropdowns(tester), isEmpty);

      for (final key in [
        'kpi_value_OSA',
        'kpi_value_Total OOS SKUs',
        'kpi_value_Impacted Branches',
        'kpi_value_Daily Lost Revenue',
        'kpi_value_Monthly Projected Loss',
      ]) {
        expect(_valueIsOneLine(tester, find.byKey(ValueKey(key))), isTrue,
            reason: '$key must stay on one line at ${width.toInt()}');
      }
    });

    testWidgets(
        'OOS matrix wraps to 3 lines and centres cells at ${width.toInt()}',
        (tester) async {
      await pumpOos(
        tester,
        OOSDashboardScreen(apiClient: OosShotApiClient()),
        width: width,
      );
      await tester.tap(find.text('مصفوفة الفروع والنواقص'));
      await tester.pumpAndSettle();

      expect(find.byType(DataTable), findsWidgets);
      for (final dt in tester.widgetList<DataTable>(find.byType(DataTable))) {
        for (final (i, c) in dt.columns.indexed) {
          if (i == 0) {
            expect(c.headingRowAlignment, isNot(MainAxisAlignment.center),
                reason: 'item-name column');
          } else {
            expect(c.headingRowAlignment, MainAxisAlignment.center,
                reason: 'column $i');
          }
        }
      }
      final names = find.byKey(const ValueKey('oos_sku_name'));
      expect(names, findsWidgets);
      for (final t in tester.widgetList<Text>(names)) {
        expect(t.maxLines, 3);
        expect(t.textAlign, TextAlign.start);
      }
      expect(_cutBeforeThreeLines(tester, find.byType(DataTable)), isEmpty);
      expect(find.byKey(const ValueKey('oos_branch_name')), findsWidgets);
      for (final t
          in tester.widgetList<Text>(find.byKey(const ValueKey('oos_branch_name')))) {
        expect(t.maxLines, 3);
      }
    });

    testWidgets(
        'OOS KPI card height, padding, fonts and icon match Sell-Out at ${width.toInt()}',
        (tester) async {
      await _pumpSellOut(tester, width: width);
      final soCard = find.byKey(const ValueKey('kpi_card_Net Sales (EGP)'));
      expect(soCard, findsOneWidget);
      final so = _metrics(tester, soCard);
      expect(so.padding, M3SummaryKpiStyle.padding);
      expect(so.iconSize, M3SummaryKpiStyle.iconSize);
      final soH = so.size.height;

      await pumpOos(
        tester,
        OOSDashboardScreen(apiClient: OosShotApiClient()),
        width: width,
      );
      final oosCard = find.byKey(const ValueKey('osa_summary_card'));
      expect(oosCard, findsOneWidget);
      final oos = _metrics(tester, oosCard);
      expect(oos.padding, so.padding);
      expect(oos.iconSize, so.iconSize);
      expect(oos.titleStyle?.fontSize, so.titleStyle?.fontSize);
      expect(oos.titleStyle?.fontWeight, so.titleStyle?.fontWeight);
      expect(oos.titleStyle?.fontFamily, so.titleStyle?.fontFamily);
      expect(oos.valueStyle?.fontSize, so.valueStyle?.fontSize);
      expect(oos.valueStyle?.fontWeight, so.valueStyle?.fontWeight);
      expect(oos.valueStyle?.fontFamily, so.valueStyle?.fontFamily);

      // Every OOS KPI card matches Sell-Out height, even with long live-like
      // compact values (Daily Lost is 601.2K, Monthly is 18.04M).
      for (final key in [
        'osa_summary_card',
        'kpi_card_Total OOS SKUs',
        'kpi_card_Impacted Branches',
        'kpi_card_Daily Lost Revenue',
        'kpi_card_Monthly Projected Loss',
      ]) {
        final card = find.byKey(ValueKey(key));
        expect(card, findsOneWidget, reason: key);
        expect(tester.getSize(card).height, closeTo(soH, 1.0),
            reason: '$key height at ${width.toInt()}');
      }
    });
  }


  testWidgets('OOS KPI grid is 4+1 at 1280+sidebar like Sell-Out', (tester) async {
    await pumpOos(
      tester,
      Row(
        children: [
          const SizedBox(width: 250, child: ColoredBox(color: Color(0xFF1A1C19))),
          Expanded(
            child: OOSDashboardScreen(apiClient: OosShotApiClient()),
          ),
        ],
      ),
      width: 1280,
    );

    final grid = tester.widget<M3EqualHeightGrid>(
        find.byKey(const ValueKey('oos_kpi_grid')));
    expect(grid.columns, 4);
    expect(grid.children, hasLength(5));
    final cardFinders = [
      'osa_summary_card',
      'kpi_card_Total OOS SKUs',
      'kpi_card_Impacted Branches',
      'kpi_card_Daily Lost Revenue',
      'kpi_card_Monthly Projected Loss',
    ];
    final ys = [
      for (final k in cardFinders)
        tester.getTopLeft(find.byKey(ValueKey(k))).dy
    ];
    expect(ys[0], closeTo(ys[1], 1.0));
    expect(ys[0], closeTo(ys[2], 1.0));
    expect(ys[0], closeTo(ys[3], 1.0));
    expect(ys[4], greaterThan(ys[0] + 100),
        reason: '5th OOS card should sit on the second row (4+1)');
    for (final k in cardFinders) {
      expect(tester.getSize(find.byKey(ValueKey(k))).height, closeTo(138.0, 1.0),
          reason: k);
    }
  });

  testWidgets(
      'unavailable OOS/executive data: KPIs show «—» notes, not fake 96.8%/0',
      (tester) async {
    await pumpOos(
      tester,
      OOSDashboardScreen(apiClient: OosUnavailableApiClient()),
      width: 1024,
    );

    expect(tester.widget<Text>(find.byKey(const ValueKey('kpi_value_OSA'))).data,
        '—');
    expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('kpi_subtitle_OSA')))
            .data,
        'لا توجد بيانات للتوافر');
    expect(
        tester
            .widget<Text>(
                find.byKey(const ValueKey('kpi_value_Daily Lost Revenue')))
            .data,
        '—');
    expect(
        tester
            .widget<Text>(find.byKey(
                const ValueKey('kpi_subtitle_Daily Lost Revenue')))
            .data,
        'لا توجد بيانات للفاقد');
    expect(
        tester
            .widget<Text>(find.byKey(
                const ValueKey('kpi_value_Monthly Projected Loss')))
            .data,
        '—');
    expect(find.textContaining('96.8%'), findsNothing);
    expect(find.textContaining('+0.0%'), findsNothing);
    expect(find.textContaining('0.0%'), findsNothing);
  });

  testWidgets(
      'empty successful monitor: real OSA, no invented +0.0%; short severity chips',
      (tester) async {
    await pumpOos(
      tester,
      OOSDashboardScreen(apiClient: OosEmptyApiClient()),
      width: 1024,
    );
    expect(tester.widget<Text>(find.byKey(const ValueKey('kpi_value_OSA'))).data,
        '100.0%');
    expect(find.textContaining('+0.0%'), findsNothing);
    expect(find.text('لا توجد نواقص مطابقة للفلاتر المحددة'), findsOneWidget);
  });

  testWidgets(
      'alert severity uses short M3ChipSurface word + description under',
      (tester) async {
    await pumpOos(
      tester,
      OOSDashboardScreen(apiClient: OosShotApiClient()),
      width: 1280,
    );

    expect(find.byType(M3ChipSurface), findsWidgets);
    final criticalChip =
        find.byKey(const ValueKey('oos_severity_oos_fix_001'));
    final highChip = find.byKey(const ValueKey('oos_severity_oos_fix_002'));
    expect(criticalChip, findsOneWidget);
    expect(highChip, findsOneWidget);
    expect(find.descendant(of: criticalChip, matching: find.text('حرج')),
        findsOneWidget);
    expect(find.descendant(of: highChip, matching: find.text('مرتفع')),
        findsOneWidget);
    expect(
        find.descendant(
            of: criticalChip,
            matching: find.text('انعدام ممتد يؤثر على المبيعات اليومية')),
        findsOneWidget);
    expect(
        find.descendant(
            of: highChip,
            matching: find.text('نواقص تحتاج إعادة توريد سريع')),
        findsOneWidget);
    // Full filter wording stays in the dropdown, not inside the status chip.
    expect(find.descendant(of: criticalChip, matching: find.text('حرج جداً')),
        findsNothing);
    expect(
        find.descendant(of: highChip, matching: find.text('أولوية مرتفعة')),
        findsNothing);
  });

  testWidgets(
      'branch matrix table is full-width with no horizontal scroll at 1024',
      (tester) async {
    await pumpOos(
      tester,
      OOSDashboardScreen(apiClient: OosShotApiClient()),
      width: 1024,
    );
    await tester.tap(find.text('مصفوفة الفروع والنواقص'));
    await tester.pumpAndSettle();

    expect(find.byType(TableScrollContainer), findsWidgets);
    final scrollables = find.descendant(
      of: find.byType(TableScrollContainer),
      matching: find.byWidgetPredicate(
          (w) => w is Scrollable && w.axisDirection != AxisDirection.down),
    );
    expect(scrollables, findsWidgets);
    for (final s in scrollables.evaluate()) {
      final extent =
          tester.state<ScrollableState>(find.byElementPredicate((e) => e == s))
              .position
              .maxScrollExtent;
      expect(extent, closeTo(0.0, 0.5),
          reason: 'matrix must fit without horizontal scroll');
    }
  });
}
