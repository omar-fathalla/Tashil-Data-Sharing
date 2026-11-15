// Sell-Out page M3 consistency across all four tabs: one icon scale
// (18/20/24, ≥40 only for empty-state illustrations), one type scale, 40dp
// 8dp-corner buttons, 32dp 8dp-corner chips, Arabic content labels.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tashil_web/core/data/result.dart';
import 'package:tashil_web/core/network/api_client.dart';
import 'package:tashil_web/core/theme/app_theme.dart';
import 'package:tashil_web/core/utils/currency_formatter.dart';
import 'package:tashil_web/core/widgets/m3_equal_height_grid.dart';
import 'package:tashil_web/core/widgets/m3_section_title.dart';
import 'package:tashil_web/core/widgets/atomic_numeric_text.dart';
import 'package:tashil_web/core/widgets/m3_chip_surface.dart';
import 'package:tashil_web/core/widgets/m3_status_tag.dart';
import 'package:tashil_web/features/sell_out_analytics/data/sell_out_explorer_repository.dart';
import 'package:tashil_web/features/sell_out_analytics/presentation/screens/sell_out_explorer_screen.dart';

import 'support/real_fonts.dart';

final _typeScale = <double>{
  11.0,
  12.0,
  14.0,
  16.0,
  22.0,
  24.0,
  28.0,
  32.0,
  36.0
};
final _iconScale = <double>{18.0, 20.0, 24.0};
const _tabs = [
  'بيانات المبيعات',
  'أداء الفروع',
  'المستهدفات',
  'الملفات المرفوعة'
];

Future<void> _pump(WidgetTester tester, {double width = 1440}) async {
  tester.view.physicalSize = Size(width, 4000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(MaterialApp(
    theme: AppTheme.light(),
    home: Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(body: SellOutExplorerScreen(apiClient: ApiClient())),
    ),
  ));
  await tester.pumpAndSettle();
}

Future<void> _openTab(WidgetTester tester, int i) async {
  if (i == 0) return;
  // Anchored: the page subtitle also contains 'أداء الفروع'.
  final f = find.textContaining(RegExp('^${_tabs[i]}'));
  expect(f, findsWidgets, reason: 'tab ${_tabs[i]}');
  await tester.tap(f.first);
  await tester.pumpAndSettle();
}

List<String> _violations(WidgetTester tester) {
  final out = <String>[];
  // Icons.
  for (final e in find.byType(Icon).evaluate()) {
    final icon = e.widget as Icon;
    final size = icon.size ?? IconTheme.of(e).size ?? 24.0;
    if (!_iconScale.contains(size) && size < 40.0) {
      out.add('icon ${icon.icon?.codePoint.toRadixString(16)} size $size');
    }
  }
  // Text sizes.
  for (final ro in tester.allRenderObjects.whereType<RenderParagraph>()) {
    void visit(InlineSpan span, TextStyle? parent) {
      final s = (parent ?? const TextStyle()).merge(span.style);
      if (span is TextSpan &&
          (span.text ?? '').trim().isNotEmpty &&
          !(s.fontFamily ?? '').contains('MaterialIcons')) {
        final fs = s.fontSize;
        if (fs != null && !_typeScale.contains(fs)) {
          out.add('font $fs "${span.text!.trim()}"');
        }
      }
      if (span is TextSpan) {
        for (final c in span.children ?? const <InlineSpan>[]) {
          visit(c, s);
        }
      }
    }

    visit(ro.text, null);
  }
  // Buttons (not icon buttons): 40dp tall, full-round (F1).
  for (final e in find
      .byWidgetPredicate((w) =>
          w is FilledButton || w is OutlinedButton || w is ElevatedButton)
      .evaluate()) {
    final ro = e.renderObject as RenderBox?;
    if (ro == null || !ro.hasSize) continue;
    // Visual height (the button's Material), not the 48dp tap target.
    final matEl = find
        .descendant(
            of: find.byWidget(e.widget), matching: find.byType(Material))
        .evaluate()
        .first;
    final material = matEl.widget as Material;
    final h = (matEl.renderObject! as RenderBox).size.height;
    final shape = material.shape;
    // F1: 40dp buttons are full-round (chips keep 8dp).
    final ok8 = shape is StadiumBorder;
    final label = find
        .descendant(of: find.byWidget(e.widget), matching: find.byType(Text))
        .evaluate()
        .map((t) => (t.widget as Text).data)
        .join(' ');
    if ((h - 40.0).abs() > 0.5) {
      out.add('button "$label" height $h');
    }
    if (!ok8) out.add('button "$label" shape $shape');
  }
  // Chips.
  for (final e in [
    ...find.byType(M3StatusTag).evaluate(),
    ...find.byType(M3ChipSurface).evaluate(),
  ]) {
    final h = (e.renderObject! as RenderBox).size.height;
    if ((h - 32.0).abs() > 0.5) out.add('tag height $h');
  }
  // Content labels that must be Arabic.
  for (final s in const [
    'Sales Data',
    'Store Performance',
    'Store Ranking by Sales',
    'Chain',
    'Store / Branch',
    'GTIN / Barcode',
    'Net Sales (EGP)',
    'Total Units Sold',
    'Active SKUs',
    'Active Stores',
  ]) {
    if (find.text(s).evaluate().isNotEmpty) out.add('english "$s"');
  }
  if (find.textContaining(RegExp(r'^Page \d+ of')).evaluate().isNotEmpty) {
    out.add('english "Page x of y"');
  }
  return out;
}

void main() {
  setUpAll(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    await loadRealCairoFont();
  });

  for (var i = 0; i < _tabs.length; i++) {
    testWidgets('Sell-Out tab ${_tabs[i]}: one icon/type/button/chip scale',
        (tester) async {
      await _pump(tester);
      await _openTab(tester, i);
      final v = _violations(tester).toSet().toList()..sort();
      expect(v, isEmpty, reason: v.join('\n'));
    });
  }

  // Larger type / 40dp controls must not overflow at narrower desktops.
  for (final w in const [390.0, 1024.0, 1280.0]) {
    for (var i = 0; i < _tabs.length; i++) {
      testWidgets('no overflow at ${w.toInt()}dp on ${_tabs[i]}',
          (tester) async {
        await _pump(tester, width: w);
        await _openTab(tester, i);
        expect(tester.takeException(), isNull);
      });
    }
  }

  group('Sell-Out v1 items', () {
    test('5. signed % uses isolates and a real minus (no trailing "-")', () {
      expect(
          CurrencyFormatter.formatSignedPct(-3.46), '\u2066\u22123.5%\u2069');
      expect(CurrencyFormatter.formatSignedPct(12), '\u2066+12.0%\u2069');
      expect(CurrencyFormatter.formatSignedPct(-0.04), '\u20660.0%\u2069');
      expect(CurrencyFormatter.formatSignedPct(0, plusForZero: true),
          '\u2066+0.0%\u2069');
      expect(CurrencyFormatter.formatSignedPct(-0.04, plusForZero: true),
          '\u2066+0.0%\u2069');
      expect(CurrencyFormatter.formatSignedPct(-7.4, decimals: 0),
          '\u2066\u22127%\u2069');
    });

    testWidgets(
        '1+6. Export / Print / Upload and the toolbar: 40dp, full-round (F1)',
        (tester) async {
      await _pump(tester);
      for (final k in const [
        'export_excel_button',
        'export_pdf_button',
        'upload_sellout_button',
        'branch_chart_sort_toggle',
      ]) {
        final btn = find.byKey(ValueKey(k));
        expect(btn, findsOneWidget, reason: k);
        final mat =
            find.descendant(of: btn, matching: find.byType(Material)).first;
        final shape = tester.widget<Material>(mat).shape;
        expect(shape, isA<StadiumBorder>(), reason: k);
        expect(tester.getSize(mat).height, 40.0, reason: k);
      }
      expect(
          tester
              .getSize(find.byKey(const ValueKey('sellout_date_range_chip')))
              .height,
          40.0);
      for (final k in const [
        'sellout_chain_dropdown',
        'sellout_store_dropdown',
        'sellout_category_dropdown',
        'branch_chart_chain_dropdown',
      ]) {
        final f = find.descendant(
            of: find.byKey(ValueKey(k)), matching: find.byType(TextField));
        expect(tester.getSize(f.first).height, 40.0, reason: k);
      }
      final search = find.byWidgetPredicate((w) =>
          w is TextField &&
          w.decoration?.hintText == 'ابحث بالصنف أو الباركود');
      expect(search, findsOneWidget);
      expect(
          tester
              .getSize(find
                  .ancestor(of: search, matching: find.byType(Container))
                  .first)
              .height,
          40.0);
    });

    testWidgets('6. Store Performance filters are 40dp too', (tester) async {
      await _pump(tester);
      await _openTab(tester, 1);
      for (final k in const ['perf_year_dropdown', 'perf_month_dropdown']) {
        final f = find.descendant(
            of: find.byKey(ValueKey(k)), matching: find.byType(TextField));
        expect(tester.getSize(f.first).height, 40.0, reason: k);
      }
      expect(
          tester
              .getSize(find.byKey(const ValueKey('perf_search_field')))
              .height,
          40.0);
    });

    testWidgets('6. one year selector, labelled with its scope',
        (tester) async {
      await _pump(tester);
      expect(find.byKey(const ValueKey('sellout_year_selector_pill')),
          findsNothing);
      expect(find.byKey(const ValueKey('branch_chart_year_dropdown')),
          findsOneWidget);
      expect(find.textContaining('سنة البيانات: '), findsOneWidget);
    });

    testWidgets('2. Fathalla chip uses the neutral chip role', (tester) async {
      await _pump(tester);
      final cs = Theme.of(tester.element(find.byType(SellOutExplorerScreen)))
          .colorScheme;
      final chips = find.byKey(const ValueKey('sku_table_chain_chip'));
      expect(chips, findsWidgets);
      for (final e in chips.evaluate()) {
        expect((e.widget as M3ChipSurface).color, cs.surfaceContainerHigh);
        expect((e.renderObject! as RenderBox).size.height, 32.0);
      }
    });

    testWidgets(
        '4. SKU table names wrap to 3 lines with the full name in a tooltip',
        (tester) async {
      await _pump(tester);
      final names = find.byKey(const ValueKey('sku_table_sku_name'));
      expect(names, findsWidgets);
      for (final e in names.evaluate()) {
        final t = e.widget as Text;
        expect(t.maxLines, 3);
        expect(t.style?.fontSize, 14.0);
        final tip =
            find.ancestor(of: find.byWidget(t), matching: find.byType(Tooltip));
        expect(tester.widget<Tooltip>(tip.first).message, contains(t.data!));
      }
    });

    testWidgets(
        '3+spacing. KPI cards: Arabic titles, equal height, 16dp gutters',
        (tester) async {
      await _pump(tester);
      final grid = find.byKey(const ValueKey('kpi_cards_row'));
      expect(tester.widget(grid), isA<M3EqualHeightGrid>());
      final rects = [
        for (final t in const [
          'Net Sales (EGP)',
          'Total Units Sold',
          'Active SKUs',
          'Active Stores'
        ])
          tester.getRect(find.byKey(ValueKey('kpi_card_$t'))),
      ]..sort((a, b) => a.left.compareTo(b.left));
      for (final r in rects) {
        expect(r.height, rects.first.height);
      }
      for (var i = 1; i < rects.length; i++) {
        expect(rects[i].left - rects[i - 1].right, closeTo(16.0, 0.5));
      }
      for (final t in const [
        'صافي المبيعات',
        'إجمالي الكمية المباعة',
        'الأصناف النشطة',
        'الفروع النشطة'
      ]) {
        expect(find.widgetWithText(M3SectionTitle, t), findsOneWidget,
            reason: t);
      }
    });

    testWidgets('section titles share M3SectionTitle on every tab',
        (tester) async {
      await _pump(tester);
      expect(find.widgetWithText(M3SectionTitle, 'ترتيب الفروع حسب المبيعات'),
          findsOneWidget);
      await _openTab(tester, 1);
      expect(
          find.widgetWithText(M3SectionTitle, 'أداء الفروع'), findsOneWidget);
      expect(
          find.byWidgetPredicate(
              (w) => w is M3SectionTitle && w.text.startsWith('نمو الفروع')),
          findsOneWidget);
      // Targets tab (empty in demo data): its section headers are
      // M3SectionTitle in source, with no per-title weight overrides.
      final panel = File(
              'lib/features/sell_out_analytics/presentation/widgets/target_management_panel.dart')
          .readAsStringSync();
      for (final t in const [
        "'المستهدف مقابل المحقق'",
        "M3SectionTitle('أصناف السلسلة",
        "M3SectionTitle('المستهدف حسب الفرع",
        "M3SectionTitle('التوزيع الشهري",
      ]) {
        expect(panel, contains(t), reason: t);
      }
      expect(
          RegExp(r"'[^'\n]*',\n\s*style: theme\.textTheme\.titleMedium\?\.copyWith\(\n\s*fontWeight: FontWeight\.w900")
              .hasMatch(panel),
          isFalse);
      await _openTab(tester, 3);
      expect(find.widgetWithText(M3SectionTitle, 'ملفات Sell-Out المرفوعة'),
          findsOneWidget);
    });
  });

  test('chips are M3ChipSurface (8dp), not capsule pills, in Sell-Out sources',
      () {
    for (final f in const [
      'lib/features/sell_out_analytics/presentation/screens/sell_out_explorer_screen.dart',
      'lib/features/sell_out_analytics/presentation/widgets/target_management_panel.dart',
      'lib/features/sell_out_analytics/presentation/widgets/virtualized_sku_table.dart',
      'lib/features/sell_out_analytics/presentation/widgets/cascading_filter_toolbar.dart',
    ]) {
      final src = File(f).readAsStringSync();
      expect(
          RegExp(r'BoxDecoration\([^;]{0,200}?borderRadius:\s*M3Shape\.radiusFull')
              .hasMatch(src),
          isFalse,
          reason: f);
      expect(src.contains('StadiumBorder'), isFalse, reason: f);
    }
  });

  group('Sell-Out price matrix (scripted data)', () {
    const longName =
        'منظف أطباق رحاب برائحة الليمون الأخضر عبوة اقتصادية كبيرة ٢ لتر × ٦ قطع';
    SellOutExplorerData data() => const SellOutExplorerData(
          records: [],
          summary: SellOutRecordsSummaryModel(
            totalCount: 2,
            totalNetRevenue: 1000,
            totalUnitsSold: 100,
            totalCartonsSold: 10,
            matchedSkusCount: 2,
            skuSummaries: [
              SellOutSkuSummaryModel(
                itemCode: 'RH-1',
                skuName: longName,
                officialConsumerRsp: 50,
                avgSellingPrice: 48.27,
                priceDeltaPct: -3.46,
                totalUnitsSold: 60,
              ),
              SellOutSkuSummaryModel(
                itemCode: 'RH-2',
                skuName: 'صابون',
                officialConsumerRsp: 20,
                avgSellingPrice: 22.4,
                priceDeltaPct: 12.0,
                totalUnitsSold: 40,
              ),
            ],
          ),
          stores: [],
          currentBranchMatrix: [],
          prevBranchMatrix: [],
          yoyCurrentBranchMatrix: [],
        );

    testWidgets(
        '2+4+5. neutral strip, 3-line names with tooltip, isolated minus',
        (tester) async {
      tester.view.physicalSize = const Size(1440, 3000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await http.runWithClient(() async {
        await tester.pumpWidget(MaterialApp(
          theme: AppTheme.light(),
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: Scaffold(
              body: SellOutExplorerScreen(
                apiClient: ApiClient(
                    tenantId: 'tenant-adeco', allowMockFallback: false),
                repository: _OneShotRepo(data()),
              ),
            ),
          ),
        ));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));
        await tester.pumpAndSettle(const Duration(seconds: 1));

        final cs = Theme.of(tester.element(find.byType(SellOutExplorerScreen)))
            .colorScheme;
        expect(find.widgetWithText(M3SectionTitle, 'الأسعار وهامش السلسلة'),
            findsOneWidget);
        final strip = tester.widget<M3ChipSurface>(
            find.byKey(const ValueKey('price_summary_strip')));
        expect(strip.color, cs.surfaceContainerHigh);

        final names = find.byKey(const ValueKey('price_matrix_sku_name'));
        expect(names, findsNWidgets(2));
        for (final e in names.evaluate()) {
          final t = e.widget as Text;
          expect(t.maxLines, 3);
          expect(t.style?.fontSize, 14.0);
          final tip = find.ancestor(
              of: find.byWidget(t), matching: find.byType(Tooltip));
          expect(tester.widget<Tooltip>(tip.first).message, t.data);
        }
        // The long name really wraps onto a second line.
        final para = tester.renderObject<RenderParagraph>(find.descendant(
            of: find.byWidgetPredicate((w) => w is Text && w.data == longName),
            matching: find.byType(RichText)));
        expect(para.size.height, greaterThan(30.0));

        final texts = find
            .byKey(const ValueKey('price_matrix_delta_pct'))
            .evaluate()
            .map((e) => (e.widget as AtomicNumericText).text)
            .toList();
        expect(texts,
            containsAll(['\u2066\u22123.5%\u2069', '\u2066+12.0%\u2069']));
        expect(texts.any((t) => t.contains('-')), isFalse);

        final v = _violations(tester).toSet().toList()..sort();
        expect(v, isEmpty, reason: v.join('\n'));
      },
          () => MockClient((req) async => http.Response.bytes(
                utf8.encode(jsonEncode(req.url.path.contains('archive') ||
                        req.url.path.contains('upload')
                    ? <Object>[]
                    : {'records': [], 'total_count': 0})),
                200,
                headers: {'content-type': 'application/json'},
              )));
    });
  });
}

class _OneShotRepo extends SellOutExplorerRepository {
  _OneShotRepo(this._data)
      : super(ApiClient(tenantId: 'tenant-adeco', allowMockFallback: false));
  final SellOutExplorerData _data;

  @override
  Future<Result<SellOutExplorerData>> load(SellOutExplorerQuery q,
          {bool forceRefresh = false}) async =>
      Success(_data);
}
