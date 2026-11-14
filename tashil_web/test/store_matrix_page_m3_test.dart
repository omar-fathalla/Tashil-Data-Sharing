// Store Matrix M3 parity with Sell-Out: shared KPI cards of equal height,
// tables fill the page with no leftover horizontal scroll, names wrap to 3
// lines and stay start-aligned, other columns are centred, dropdowns and
// filter tabs are unclipped, and a shared leading branch prefix is stripped
// on display only. Made-up live-like fixtures. Real Cairo font. 1280 and 1024.
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:tashil_web/core/data/app_cache.dart';
import 'package:tashil_web/core/data/result.dart';
import 'package:tashil_web/core/network/api_client.dart';
import 'package:tashil_web/core/theme/app_theme.dart';
import 'package:tashil_web/core/utils/arabic_plural.dart';
import 'package:tashil_web/core/widgets/m3_search_field.dart';
import 'package:tashil_web/core/widgets/m3_summary_kpi_card.dart';
import 'package:tashil_web/core/widgets/table_scroll_container.dart';
import 'package:tashil_web/features/navigation/presentation/desktop_sidebar.dart';
import 'package:tashil_web/features/sell_out_analytics/presentation/screens/sell_out_explorer_screen.dart';
import 'package:tashil_web/features/store_benchmark/data/store_benchmark_repository.dart';
import 'package:tashil_web/features/store_benchmark/presentation/screens/store_matrix_screen.dart';

import 'support/real_fonts.dart';

const _prefix = 'عائلة فتح الله ماركت - ';

final kLiveLikeStores = <StoreBenchmarkItem>[
  StoreBenchmarkItem(
    storeId: 's1',
    storeName:
        '$_prefix'
        'فرع سموحة التجاري الجديد بجوار سيتي سنتر الإسكندرية',
    retailerChain: 'fathalla',
    region: 'شرق الإسكندرية',
    tier: 'Tier A',
    totalRevenue: 127133355,
    totalUnits: 81294,
    velocityUnitsPerDay: 124.7,
    rank: 1,
  ),
  StoreBenchmarkItem(
    storeId: 's2',
    storeName:
        '$_prefix'
        'فرع المنشية البحري المطل على الميدان الرئيسي',
    retailerChain: 'fathalla',
    region: 'غرب الإسكندرية',
    tier: 'Tier B',
    totalRevenue: 18450220,
    totalUnits: 22011,
    velocityUnitsPerDay: 41.3,
    rank: 2,
  ),
  StoreBenchmarkItem(
    storeId: 's3',
    storeName:
        '$_prefix'
        'فرع ستانلي على الكورنيش بجوار فندق الشيراتون',
    retailerChain: 'fathalla',
    region: 'شرق الإسكندرية',
    tier: 'Tier C',
    totalRevenue: 9622110,
    totalUnits: 15440,
    velocityUnitsPerDay: 22.8,
    rank: 3,
  ),
];

const kStrippedNames = [
  'فرع سموحة التجاري الجديد بجوار سيتي سنتر الإسكندرية',
  'فرع المنشية البحري المطل على الميدان الرئيسي',
  'فرع ستانلي على الكورنيش بجوار فندق الشيراتون',
];

class StoreMatrixFixtureRepo extends StoreBenchmarkRepository {
  StoreMatrixFixtureRepo(super.api, {List<StoreBenchmarkItem>? items})
    : items = items ?? kLiveLikeStores;

  final List<StoreBenchmarkItem> items;

  @override
  Future<Result<List<StoreBenchmarkItem>>> loadMatrix({
    String? region,
    String? tier,
    String? chain,
    int? year,
    int? month,
    bool forceRefresh = false,
  }) async {
    var out = List<StoreBenchmarkItem>.from(items);
    if (region != null && region.isNotEmpty) {
      out = out.where((s) => s.region == region).toList();
    }
    if (tier != null && tier.isNotEmpty) {
      out = out.where((s) => s.tier == tier).toList();
    }
    if (chain != null && chain.isNotEmpty) {
      out = out.where((s) => s.retailerChain == chain).toList();
    }
    return Success(out);
  }
}

class _KpiMetrics {
  _KpiMetrics(this.size, this.padding, this.iconSize, this.fonts, this.weights);
  final Size size;
  final EdgeInsetsGeometry? padding;
  final double? iconSize;
  final List<double?> fonts;
  final List<FontWeight?> weights;
  @override
  String toString() =>
      'size=$size padding=$padding icon=$iconSize fonts=$fonts weights=$weights';
}

_KpiMetrics _kpi(WidgetTester tester, Finder card) {
  final texts = find.descendant(of: card, matching: find.byType(Text));
  final styles = [
    for (final e in texts.evaluate())
      (find
                  .descendant(
                    of: find.byWidget(e.widget),
                    matching: find.byType(RichText),
                  )
                  .evaluate()
                  .first
                  .widget
              as RichText)
          .text
          .style,
  ];
  return _KpiMetrics(
    tester.getSize(card),
    tester
        .widget<Container>(
          find.descendant(of: card, matching: find.byType(Container)).first,
        )
        .padding,
    tester
        .widget<Icon>(
          find.descendant(of: card, matching: find.byType(Icon)).first,
        )
        .size,
    [for (final st in styles) st?.fontSize],
    [for (final st in styles) st?.fontWeight],
  );
}

List<String> clippedDropdowns(WidgetTester tester) {
  final out = <String>[];
  for (final e
      in find
          .byType(DropdownMenu<int>)
          .evaluate()
          .followedBy(find.byType(DropdownMenu<String>).evaluate())
          .followedBy(find.byType(DropdownMenu<String?>).evaluate())) {
    final dd = e.widget as DropdownMenu;
    final label = dd.label is Text ? (dd.label! as Text).data : '?';
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
        '$label: "$text" ${tp.width.toStringAsFixed(1)} > '
        '${box.size.width.toStringAsFixed(1)}',
      );
    }
    tp.dispose();
  }
  return out;
}

void expectTextFullyVisible(WidgetTester tester, Finder f, String what) {
  expect(f, findsWidgets, reason: what);
  final e = f.evaluate().first;
  final widget = e.widget;
  if (widget is Text && widget.data != null) {
    final box = tester.getRect(f.first);
    final style = widget.style;
    final tp = TextPainter(
      text: TextSpan(text: widget.data, style: style),
      textDirection: Directionality.of(e),
      textScaler: MediaQuery.textScalerOf(e),
      maxLines: widget.maxLines,
    )..layout();
    final cut =
        (widget.overflow == TextOverflow.ellipsis &&
            widget.maxLines != null &&
            tp.didExceedMaxLines) ||
        (widget.maxLines == 1 && tp.width > box.width + 0.5);
    tp.dispose();
    expect(
      cut,
      isFalse,
      reason: '$what is truncated ($box, overflow=${widget.overflow})',
    );
  }
  try {
    final p = tester.renderObject<RenderParagraph>(f.first);
    expect(p.didExceedMaxLines, isFalse, reason: '$what exceeded maxLines');
  } catch (_) {}
}

double horizontalScrollExtent(WidgetTester tester, Finder table) {
  final scrollable = find.ancestor(
    of: table,
    matching: find.byWidgetPredicate(
      (w) =>
          w is Scrollable &&
          w.axisDirection != AxisDirection.down &&
          w.axisDirection != AxisDirection.up,
    ),
  );
  if (scrollable.evaluate().isEmpty) return 0.0;
  return tester
      .state<ScrollableState>(scrollable.first)
      .position
      .maxScrollExtent;
}

void expectInViewport(
  WidgetTester tester,
  Finder f,
  double width,
  String what,
) {
  expect(f, findsWidgets, reason: what);
  final r = tester.getRect(f.first);
  expect(r.left, greaterThanOrEqualTo(-0.5), reason: '$what $r');
  expect(r.right, lessThanOrEqualTo(width + 0.5), reason: '$what $r');
}

Future<void> pumpStoreMatrix(
  WidgetTester tester, {
  double width = 1280,
  double height = 3000,
  bool sidebar = false,
  StoreBenchmarkRepository? repository,
}) async {
  tester.view.physicalSize = Size(width, height);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final api = ApiClient();
  final page = StoreMatrixScreen(
    apiClient: api,
    repository: repository ?? StoreMatrixFixtureRepo(api),
  );
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
        child: Scaffold(
          body: sidebar
              ? Row(
                  children: [
                    DesktopSidebar(
                      selectedIndex: 6,
                      onDestinationSelected: (_) {},
                      activeTenant: 'adeco',
                      onTenantChanged: (_) {},
                    ),
                    Expanded(child: page),
                  ],
                )
              : page,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  GoogleFonts.config.allowRuntimeFetching = false;
  setUpAll(loadRealCairoFont);
  setUp(AppCache.clear);

  for (final width in const [1280.0, 1024.0]) {
    testWidgets(
      'Store Matrix table does not scroll horizontally at ${width.toInt()} with long branch names',
      (tester) async {
        await pumpStoreMatrix(tester, width: width);
        expect(tester.takeException(), isNull);
        final table = find.byKey(const ValueKey('store_matrix_table'));
        expect(table, findsOneWidget);
        expect(find.byType(TableScrollContainer), findsWidgets);
        expect(
          horizontalScrollExtent(tester, table),
          lessThanOrEqualTo(2.0),
          reason:
              'store matrix table must fill the page with no leftover scroll at $width',
        );
        expectInViewport(
          tester,
          find.text('اسم الفرع والسلسلة'),
          width,
          'name header',
        );
        expectInViewport(
          tester,
          find.text('معدل السرعة اليومي'),
          width,
          'velocity header',
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'Store Matrix file/branch names wrap to 3 lines; other cells are centred',
    (tester) async {
      await pumpStoreMatrix(tester);
      final name = find.byKey(const ValueKey('store_name_s1'));
      expect(name, findsOneWidget);
      final nameText = tester.widget<Text>(
        find.descendant(of: name, matching: find.byType(Text)).first,
      );
      expect(nameText.maxLines, 3);
      expect(nameText.textAlign, TextAlign.start);
      expect(nameText.data, kStrippedNames.first);

      final region = find.text('شرق الإسكندرية').first;
      expect(tester.widget<Text>(region).maxLines, 3);
      expect(tester.widget<Text>(region).textAlign, TextAlign.center);
    },
  );

  testWidgets(
    'Store Matrix strips a shared branch prefix (display only) and shows the remainder',
    (tester) async {
      await pumpStoreMatrix(tester, width: 1280, sidebar: true);
      for (final name in kStrippedNames) {
        expect(find.text(name), findsOneWidget);
        expectTextFullyVisible(tester, find.text(name), name);
        expectInViewport(tester, find.text(name), 1280, name);
      }
      expect(find.textContaining(_prefix.trim()), findsNothing);
      expect(find.textContaining('عائلة فتح الله ماركت'), findsNothing);
    },
  );

  testWidgets(
    'Store Matrix strips a live-like فرع prefix via the shared helper',
    (tester) async {
      const prefix = 'فرع سلسلة تجريبية - ';
      final items = [
        StoreBenchmarkItem(
          storeId: 's1',
          storeName: '${prefix}سيدي جابر ميني',
          retailerChain: 'fathalla',
          region: 'شرق الإسكندرية',
          tier: 'Tier A',
          totalRevenue: 866000,
          totalUnits: 12099,
          velocityUnitsPerDay: 1209.9,
          rank: 1,
        ),
        StoreBenchmarkItem(
          storeId: 's2',
          storeName: '${prefix}نيس2',
          retailerChain: 'fathalla',
          region: 'شرق الإسكندرية',
          tier: 'Tier A',
          totalRevenue: 717900,
          totalUnits: 9150,
          velocityUnitsPerDay: 915.0,
          rank: 2,
        ),
        StoreBenchmarkItem(
          storeId: 's3',
          storeName: '${prefix}الدخيلة ميني',
          retailerChain: 'fathalla',
          region: 'غرب الإسكندرية',
          tier: 'Tier A',
          totalRevenue: 674600,
          totalUnits: 8430,
          velocityUnitsPerDay: 843.0,
          rank: 3,
        ),
        StoreBenchmarkItem(
          storeId: 's4',
          storeName: 'غير موزع علي فرع',
          retailerChain: 'fathalla',
          region: 'شرق الإسكندرية',
          tier: 'Tier C',
          totalRevenue: 192900,
          totalUnits: 0,
          velocityUnitsPerDay: 0,
          rank: 4,
        ),
      ];
      await pumpStoreMatrix(
        tester,
        width: 1280,
        sidebar: true,
        repository: StoreMatrixFixtureRepo(ApiClient(), items: items),
      );
      expect(find.text('سيدي جابر ميني'), findsOneWidget);
      expect(find.text('نيس2'), findsOneWidget);
      expect(find.text('الدخيلة ميني'), findsOneWidget);
      expect(find.text('غير موزع علي فرع'), findsOneWidget);
      expect(find.textContaining(prefix.trim()), findsNothing);
    },
  );

  testWidgets('Store Matrix search, short labels, and unclipped dropdowns', (
    tester,
  ) async {
    await pumpStoreMatrix(tester, width: 1280, sidebar: true);
    expect(find.byType(M3SearchFieldWidth), findsOneWidget);
    expect(find.text('السنة'), findsWidgets);
    expect(find.text('الشهر'), findsWidgets);
    expect(find.text('السلسلة'), findsWidgets);
    expect(find.text('السنة المالية:'), findsNothing);
    expect(find.text('سلسلة التجزئة:'), findsNothing);
    expect(clippedDropdowns(tester), isEmpty);
    expectTextFullyVisible(tester, find.text('السنة').first, 'السنة');
    expectTextFullyVisible(tester, find.text('السلسلة').first, 'السلسلة');
  });

  testWidgets(
    'Store Matrix region and tier tabs stay fully visible at 1280 with sidebar',
    (tester) async {
      await pumpStoreMatrix(tester, width: 1280, sidebar: true);
      const labels = [
        'كافة المناطق',
        'شرق الإسكندرية',
        'غرب الإسكندرية',
        'الدلتا والبحيرة',
        'القاهرة الكبرى',
        'Tier A',
        'Tier B',
        'Tier C',
      ];
      for (final label in labels) {
        expectInViewport(tester, find.text(label), 1280, label);
        expectTextFullyVisible(tester, find.text(label), label);
      }
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Store Matrix uses arabic plural counts and shared KPI cards', (
    tester,
  ) async {
    await pumpStoreMatrix(tester);
    expect(find.byType(M3SummaryKpiCard), findsNWidgets(3));
    expect(find.byKey(const ValueKey('kpi_card_Tier A')), findsOneWidget);
    expect(find.byKey(const ValueKey('kpi_card_Tier B')), findsOneWidget);
    expect(find.byKey(const ValueKey('kpi_card_Tier C')), findsOneWidget);
    expect(find.textContaining(countBranches(3)), findsWidgets);
    expect(find.textContaining(countBranches(1)), findsWidgets);
  });

  for (final width in const [1280.0, 1024.0]) {
    testWidgets('Store Matrix KPI cards match the Sell-Out reference @$width', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 3200);
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
            child: Scaffold(
              body: SellOutExplorerScreen(apiClient: ApiClient()),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final ref = _kpi(
        tester,
        find.byKey(const ValueKey('kpi_card_Net Sales (EGP)')),
      );

      await pumpStoreMatrix(tester, width: width);
      final cards = find.byWidgetPredicate(
        (w) =>
            w is M3SummaryKpiCard &&
            w.key is ValueKey<String> &&
            (w.key as ValueKey<String>).value.startsWith('kpi_card_Tier'),
      );
      expect(cards, findsNWidgets(3));
      final sizes = [
        for (final e in cards.evaluate())
          tester.getSize(find.byWidget(e.widget)),
      ];
      expect(sizes[1].width, closeTo(sizes[0].width, 0.5));
      expect(sizes[2].width, closeTo(sizes[0].width, 0.5));
      expect(sizes[1].height, closeTo(sizes[0].height, 0.5));
      expect(sizes[2].height, closeTo(sizes[0].height, 0.5));
      for (final e in cards.evaluate()) {
        final m = _kpi(tester, find.byWidget(e.widget));
        final why = 'store-matrix ${e.widget.key}: $m\nsell-out: $ref';
        expect(m.padding, ref.padding, reason: why);
        expect(m.iconSize, ref.iconSize, reason: why);
        expect(m.iconSize, M3SummaryKpiStyle.iconSize, reason: why);
        expect(m.padding, M3SummaryKpiStyle.padding, reason: why);
        expect(m.fonts, ref.fonts, reason: why);
        expect(m.weights, ref.weights, reason: why);
        // Store Matrix has 3 tier cards; Sell-Out has 4, so widths differ.
        // Token padding, type, icon and height must still match.
        if (width >= 1280) {
          expect(m.size.height, closeTo(ref.size.height, 0.5), reason: why);
        } else {
          expect(
            m.size.height,
            greaterThanOrEqualTo(ref.size.height),
            reason: why,
          );
        }
      }
    });
  }

  testWidgets('Store Matrix KPI values stay on one line at 1280', (
    tester,
  ) async {
    await pumpStoreMatrix(tester, width: 1280, sidebar: true);
    for (final key in [
      'kpi_value_Tier A',
      'kpi_value_Tier B',
      'kpi_value_Tier C',
    ]) {
      final f = find.byKey(ValueKey(key));
      expect(f, findsOneWidget);
      expectTextFullyVisible(tester, f, key);
      final texts = find.descendant(of: f, matching: find.byType(Text));
      final target = texts.evaluate().isEmpty ? f : texts.first;
      try {
        final p = tester.renderObject<RenderParagraph>(target);
        expect(p.didExceedMaxLines, isFalse, reason: '$key wrapped/clipped');
        final tp = TextPainter(
          text: p.text,
          textDirection: p.textDirection,
          textScaler: MediaQuery.textScalerOf(tester.element(target)),
          maxLines: 1,
        )..layout();
        expect(tp.didExceedMaxLines, isFalse, reason: '$key is not one line');
        tp.dispose();
      } catch (e) {
        fail('$key paragraph: $e');
      }
    }
  });

  testWidgets(
    'empty tier KPIs show «—» + Arabic note, not fake 0 ج.م',
    (tester) async {
      final onlyA = [
        StoreBenchmarkItem(
          storeId: 's1',
          storeName: 'فرع سموحة',
          retailerChain: 'fathalla',
          region: 'شرق الإسكندرية',
          tier: 'Tier A',
          totalRevenue: 1200000,
          totalUnits: 9000,
          velocityUnitsPerDay: 90.0,
          rank: 1,
        ),
      ];
      await pumpStoreMatrix(
        tester,
        repository: StoreMatrixFixtureRepo(ApiClient(), items: onlyA),
      );
      expect(tester.widget<Text>(find.byKey(const ValueKey('kpi_value_Tier B'))).data,
          '—');
      expect(tester.widget<Text>(find.byKey(const ValueKey('kpi_value_Tier C'))).data,
          '—');
      expect(
        tester.widget<Text>(find.byKey(const ValueKey('kpi_subtitle_Tier B'))).data,
        'لا توجد فروع في هذه الفئة',
      );
      expect(
        tester.widget<Text>(find.byKey(const ValueKey('kpi_subtitle_Tier C'))).data,
        'لا توجد فروع في هذه الفئة',
      );
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('kpi_card_Tier B')),
          matching: find.textContaining('0 ج.م'),
        ),
        findsNothing,
      );
      expect(
        tester.widget<Text>(find.byKey(const ValueKey('kpi_value_Tier A'))).data,
        isNot('—'),
      );
    },
  );

  testWidgets(
    'zero velocity shows «—» + note, not fake 0.0 / يوم',
    (tester) async {
      final items = [
        StoreBenchmarkItem(
          storeId: 's1',
          storeName: 'فرع سموحة',
          retailerChain: 'fathalla',
          region: 'شرق الإسكندرية',
          tier: 'Tier A',
          totalRevenue: 500000,
          totalUnits: 0,
          velocityUnitsPerDay: 0,
          rank: 1,
        ),
        StoreBenchmarkItem(
          storeId: 's2',
          storeName: 'فرع المنشية',
          retailerChain: 'fathalla',
          region: 'غرب الإسكندرية',
          tier: 'Tier B',
          totalRevenue: 400000,
          totalUnits: 1200,
          velocityUnitsPerDay: 40.0,
          rank: 2,
        ),
      ];
      await pumpStoreMatrix(
        tester,
        repository: StoreMatrixFixtureRepo(ApiClient(), items: items),
      );
      expect(find.text('0.0 / يوم'), findsNothing);
      expect(find.text('0.0'), findsNothing);
      expect(find.text('لا توجد بيانات سرعة'), findsOneWidget);
      expect(find.text('وحدة / يوم'), findsOneWidget);
      expect(find.text('40.0'), findsOneWidget);
      expect(find.text('—'), findsWidgets);
    },
  );

  testWidgets(
    'sort meta chip is short word + description under M3ChipSurface',
    (tester) async {
      await pumpStoreMatrix(tester);
      expect(find.byKey(const ValueKey('store_matrix_sort_chip')), findsOneWidget);
      expect(find.byKey(const ValueKey('store_matrix_period_chip')), findsOneWidget);
      expect(find.text('ترتيب'), findsOneWidget);
      expect(find.text('حسب إجمالي المبيعات تنازلياً'), findsOneWidget);
      expect(find.text('الترتيب حسب إجمالي المبيعات تنازلياً'), findsNothing);
    },
  );
}
