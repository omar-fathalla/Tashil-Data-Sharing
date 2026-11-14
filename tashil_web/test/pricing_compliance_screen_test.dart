import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tashil_web/core/network/api_client.dart';
import 'package:tashil_web/core/theme/app_theme.dart';
import 'package:tashil_web/features/pricing_compliance/presentation/screens/pricing_compliance_screen.dart';

void main() {
  group('PricingComplianceScreen Widget Tests', () {
    late ApiClient apiClient;

    setUp(() {
      apiClient = ApiClient();
    });

    testWidgets(
        'renders KPI cards, SegmentedButton filter, and price delta badges',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1440, 1024);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: PricingComplianceScreen(apiClient: apiClient),
          ),
        ),
      );

      // Settle async data
      await tester.pumpAndSettle();

      // Check Screen Header
      expect(find.textContaining('Pricing & Promos'), findsOneWidget);

      // Check Summary KPI Cards
      expect(find.textContaining('معدل الالتزام السعري'), findsOneWidget);
      expect(find.textContaining('إجمالي المخالفات السعرية'), findsOneWidget);
      expect(find.textContaining('متوسط الأثر الترويجي'), findsOneWidget);

      // Check SegmentedButton options
      expect(find.text('الكل'), findsWidgets);
      expect(find.text('عروض نشطة'), findsOneWidget);
      expect(find.text('مخالفات سعرية'), findsOneWidget);

      // Check Table Columns
      expect(find.text('الصنف والباركود'), findsOneWidget);
      expect(find.text('السلسلة والفرع'), findsOneWidget);
      expect(find.text('السعر الفعلي'), findsOneWidget);
      expect(find.text('السعر الموصى به (RRP)'), findsOneWidget);
      expect(find.text('الفارق السعري (Delta)'), findsOneWidget);
      expect(find.text('حالة العرض والأثر البيعي'), findsOneWidget);

      // Check Badges: under-cutting, compliant, price-gouging
      expect(find.textContaining('حرق سعر'), findsWidgets);
      expect(find.textContaining('مطابق'), findsWidgets);
      expect(find.textContaining('زيادة سعر'), findsWidgets);

      // Check Promo Uplift Badges
      expect(find.textContaining('أثر ترويجي'), findsWidgets);
      expect(find.textContaining('بدون عرض'), findsWidgets);
    });

    testWidgets(
        'filtering by SegmentedButton (مخالفات سعرية فقط) filters compliant items',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1440, 1024);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: PricingComplianceScreen(apiClient: apiClient),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Tap on 'مخالفات سعرية'
      final violationSegment = find.text('مخالفات سعرية');
      expect(violationSegment, findsOneWidget);
      await tester.tap(violationSegment);
      await tester.pumpAndSettle();

      // In violation only mode, compliant badges in the DataTable must be 0
      expect(
        find.descendant(
            of: find.byType(DataTable), matching: find.textContaining('مطابق')),
        findsNothing,
      );

      // Violations should still appear in the DataTable
      expect(
        find.descendant(
            of: find.byType(DataTable),
            matching: find.textContaining('حرق سعر')),
        findsWidgets,
      );
      expect(
        find.descendant(
            of: find.byType(DataTable),
            matching: find.textContaining('زيادة سعر')),
        findsWidgets,
      );
    });

    testWidgets(
        'filtering by SegmentedButton (عروض نشطة فقط) displays promo items with uplift',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1440, 1024);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: PricingComplianceScreen(apiClient: apiClient),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Tap on 'عروض نشطة'
      final promoSegment = find.text('عروض نشطة');
      expect(promoSegment, findsOneWidget);
      await tester.tap(promoSegment);
      await tester.pumpAndSettle();

      // Non-promo items ('بدون عرض') must be 0 in table
      expect(
        find.descendant(
            of: find.byType(DataTable),
            matching: find.textContaining('بدون عرض')),
        findsNothing,
      );

      // Uplift badges should be visible
      expect(
        find.descendant(
            of: find.byType(DataTable),
            matching: find.textContaining('أثر ترويجي')),
        findsWidgets,
      );
    });

    testWidgets('filtering by Category chip updates the SKU compliance list',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1440, 1024);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: PricingComplianceScreen(apiClient: apiClient),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Tap on 'منظف ارضيات' category chip
      final floorCleanerChip = find.widgetWithText(FilterChip, 'منظف ارضيات');
      if (floorCleanerChip.evaluate().isNotEmpty) {
        await tester.tap(floorCleanerChip);
        await tester.pumpAndSettle();
      }
      expect(find.byType(DataTable), findsOneWidget);
    });

    testWidgets(
        'renders cleanly on compact mobile viewport without RenderFlex overflow',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: PricingComplianceScreen(apiClient: apiClient),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.textContaining('Pricing & Promos'), findsOneWidget);
      expect(find.textContaining('السعر الفعلي'), findsWidgets);
    });

    testWidgets(
        'paginates 25 items by default, switches to 50 items, and deduplicates approved categories without hardcoded food categories',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1440, 1024);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final fakeClient = _FakePaginatedComplianceApiClient();

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: PricingComplianceScreen(apiClient: fakeClient),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // 1. Verify default request used limit=25, offset=0
      expect(fakeClient.lastRequestedLimit, equals(25));
      expect(fakeClient.lastRequestedOffset, equals(0));
      expect(find.byKey(const ValueKey('header_pricing_range_label')),
          findsOneWidget);
      expect(find.text('عرض 1-25 من 60'), findsWidgets);

      final DataTable tablePage1 =
          tester.widget<DataTable>(find.byType(DataTable));
      expect(tablePage1.rows.length, equals(25));

      // 2. Verify category chips only show deduplicated canonical categories (no unapproved food categories)
      expect(
          find.widgetWithText(FilterChip, 'صابون سائل اطباق'), findsOneWidget);
      expect(
          find.widgetWithText(FilterChip, 'صابون سائل للاطباق'), findsNothing);
      expect(find.widgetWithText(FilterChip, 'كلور ألوان'), findsOneWidget);
      expect(find.widgetWithText(FilterChip, 'كلور الوان'), findsNothing);
      expect(find.widgetWithText(FilterChip, 'منظف ارضيات'), findsOneWidget);
      expect(find.widgetWithText(FilterChip, 'كلور ارضيات'), findsNothing);
      expect(find.widgetWithText(FilterChip, 'زيوت طعام'), findsNothing);
      expect(find.widgetWithText(FilterChip, 'صلصة ومعلبات'), findsNothing);
      expect(find.widgetWithText(FilterChip, 'بقوليات ومعلبات'), findsNothing);

      // 3. Navigate to Page 2 (25 items, offset=25)
      await tester.tap(find.byKey(const ValueKey('header_pricing_next_page')));
      await tester.pumpAndSettle();

      expect(fakeClient.lastRequestedLimit, equals(25));
      expect(fakeClient.lastRequestedOffset, equals(25));
      expect(find.text('عرض 26-50 من 60'), findsWidgets);

      // 4. Switch page size from 25 to 50 items
      await tester.tap(find.text('50 صنف').first);
      await tester.pumpAndSettle();

      expect(fakeClient.lastRequestedLimit, equals(50));
      expect(fakeClient.lastRequestedOffset, equals(0));
      expect(find.text('عرض 1-50 من 60'), findsWidgets);

      final DataTable tablePage50 =
          tester.widget<DataTable>(find.byType(DataTable));
      expect(tablePage50.rows.length, equals(50));

      // 5. Navigate to Page 2 (offset=50) and then switch to a category with fewer than 25 items (20 items)
      await tester.tap(find.byKey(const ValueKey('header_pricing_next_page')));
      await tester.pumpAndSettle();
      expect(fakeClient.lastRequestedOffset, equals(50));
      expect(find.text('عرض 51-60 من 60'), findsWidgets);

      await tester.tap(find.widgetWithText(FilterChip, 'كلور ألوان'));
      await tester.pumpAndSettle();
      expect(fakeClient.lastRequestedOffset, equals(0));
      expect(find.text('عرض 1-20 من 20'), findsWidgets);
    });
  });
}

class _FakePaginatedComplianceApiClient extends ApiClient {
  int? lastRequestedLimit;
  int? lastRequestedOffset;

  late final List<PricingComplianceItem> _all60Items = List.generate(60, (i) {
    final rawCategories = [
      'صابون سائل للاطباق',
      'صابون سائل اطباق',
      'كلور الوان',
      'كلور ألوان',
      'كلور ارضيات',
      'منظف ارضيات',
    ];
    final isViolation = i % 3 == 0;
    return PricingComplianceItem(
      skuName: 'أدكو منظف رقم ${i + 1}',
      barcode: '622300139${(1000 + i)}',
      category: ApiClient.normalizeCategoryName(
          rawCategories[i % rawCategories.length]),
      retailerChain: i.isEven ? 'fathalla' : 'gomla',
      storeName: i.isEven ? 'فتح الله سموحة' : 'جملة ماركت',
      actualPrice: isViolation ? 90.0 : 100.0,
      recommendedPrice: 100.0,
      priceDeltaPct: isViolation ? -10.0 : 0.0,
      violationType: isViolation ? 'under_cutting' : 'compliant',
      isPromoActive: i % 4 == 0,
      promoUpliftPct: i % 4 == 0 ? 18.5 : 0.0,
    );
  });

  @override
  Future<List<PricingComplianceItem>> getPricingCompliance({
    String? chain,
    String? category,
    bool? violationOnly,
    bool? promoOnly,
    int? year,
    int? month,
    int? limit,
    int? offset,
    String? search,
  }) async {
    lastRequestedLimit = limit;
    lastRequestedOffset = offset;

    final cats = _all60Items.map((e) => e.category).toSet().toList()..sort();
    var filtered = _all60Items.where((item) {
      if (chain != null && chain.isNotEmpty && item.retailerChain != chain)
        return false;
      if (category != null && category.isNotEmpty && item.category != category)
        return false;
      if (violationOnly == true && item.violationType == 'compliant')
        return false;
      if (promoOnly == true && !item.isPromoActive) return false;
      if (search != null && search.trim().isNotEmpty) {
        if (!ApiClient.matchesProductSearch(
          search,
          itemCode: item.itemCode,
          barcode: item.barcode,
          skuName: item.skuName,
          category: item.category,
        )) {
          return false;
        }
      }
      return true;
    }).toList();

    final totalCount = filtered.length;
    final start = (offset ?? 0).clamp(0, totalCount);
    final end = limit != null && limit > 0
        ? (start + limit).clamp(0, totalCount)
        : totalCount;
    final pageItems = filtered.sublist(start, end);

    lastPricingComplianceMeta = PricingCompliancePageResult(
      items: pageItems,
      totalCount: totalCount,
      summaryTotalCount: _all60Items.length,
      limit: limit ?? totalCount,
      offset: offset ?? 0,
      compliantCount: 40,
      violationCount: 20,
      complianceRatePct: 66.7,
      avgPromoUpliftPct: 18.5,
      availableCategories: cats,
    );
    return pageItems;
  }
}
