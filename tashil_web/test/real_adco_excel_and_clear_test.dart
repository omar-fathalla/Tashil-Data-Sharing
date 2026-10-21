import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tashil_web/core/network/api_client.dart';
import 'package:tashil_web/features/data_ingestion/presentation/screens/upload_portal_screen.dart';
import 'package:tashil_web/features/executive_dashboard/presentation/widgets/pareto_category_section.dart';

void main() {
  group('Real Adco Excel Ingestion, Branch Auto-Creation & Fake Data Wipe', () {
    test('clearTenantData resets all records, branches, and KPIs to zero, and loadRealAdcoExcel restores real 34 Fathalla branches and 82 suppliers', () async {
      final apiClient = ApiClient(tenantId: 'adeco');

      // Initially has real Adco 2026 data loaded
      final initialKpis = await apiClient.getExecutiveKPIs();
      expect(initialKpis.totalRevenue, greaterThan(0));
      expect(initialKpis.totalMarketRevenue, closeTo(51725316.94, 1.0));
      expect(initialKpis.activeStoresCount, equals(34));
      expect(initialKpis.tenantMarketSharePct, closeTo(18.44, 0.1));
      expect(initialKpis.competitorsCount, greaterThanOrEqualTo(81));
      expect(initialKpis.supplierShares, isNotEmpty);
      expect(initialKpis.supplierShares.first.supplierName, contains('ديكو'));

      // 1. Wipe all data
      await apiClient.clearTenantData();
      expect(apiClient.isCurrentTenantCleared, isTrue);

      final clearedKpis = await apiClient.getExecutiveKPIs();
      expect(clearedKpis.totalRevenue, equals(0.0));
      expect(clearedKpis.totalUnitsSold, equals(0));
      expect(clearedKpis.activeStoresCount, equals(0));

      final clearedRecords = await apiClient.getRecords();
      expect(clearedRecords, isEmpty);

      final clearedStores = await apiClient.getStoreBenchmarkMatrix();
      expect(clearedStores, isEmpty);

      // 2. Re-load 40-Adco -2026.xlsx
      final summary = await apiClient.loadRealAdcoExcel();
      expect(apiClient.isCurrentTenantCleared, isFalse);
      expect(summary.autoCreatedStoresCount, equals(34));
      expect(summary.competitorsDetected, greaterThanOrEqualTo(81));
      expect(summary.tenantMarketSharePct, closeTo(18.44, 0.1));
      expect(summary.discoveredBranches, isNotEmpty);
      expect(
        summary.discoveredBranches
            .map((b) => '${b['branch_name'] ?? b['store_name'] ?? ''}')
            .join(' '),
        allOf(contains('سموحة'), contains('جاردينيا'), contains('هانوفيل')),
      );

      final reloadedStores = await apiClient.getStoreBenchmarkMatrix();
      expect(reloadedStores, isNotEmpty);
      expect(
        reloadedStores.map((s) => s.storeName).join(' '),
        contains('سموحة'),
      );
    });

    testWidgets('UploadPortalScreen has no demo buttons and displays enterprise multi-tab ingestion header', (tester) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final apiClient = ApiClient(tenantId: 'adeco');

      await tester.pumpWidget(
        MaterialApp(
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: Scaffold(
              body: UploadPortalScreen(apiClient: apiClient),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('clear_fake_data_button')), findsNothing);
      expect(find.byKey(const ValueKey('load_real_adco_excel_button')), findsNothing);
      expect(find.byKey(const ValueKey('ingestion_ai_tier_dropdown')), findsNothing);
      expect(find.text('بوابة استيعاب البيانات الذكية'), findsOneWidget);
      expect(find.text('استيعاب التابات المتعددة (Multi-Tab Ingestion)'), findsOneWidget);
    });

    testWidgets('ParetoCategorySection renders Competing Suppliers Market Share card', (tester) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final apiClient = ApiClient(tenantId: 'adeco');
      final kpis = await apiClient.getExecutiveKPIs();

      await tester.pumpWidget(
        MaterialApp(
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: Scaffold(
              body: SingleChildScrollView(
                child: ParetoCategorySection(
                  categories: kpis.categoryContributions,
                  paretoSkus: kpis.paretoSkus,
                  supplierShares: kpis.supplierShares,
                  tenantMarketSharePct: kpis.tenantMarketSharePct,
                  totalMarketRevenue: kpis.totalMarketRevenue,
                  competitorsCount: kpis.competitorsCount,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('supplier_market_share_card')), findsOneWidget);
      expect(find.textContaining('الحصة السوقية لشركة أديكو مقارنة بالموردين المنافسين'), findsOneWidget);
      expect(find.textContaining('حصة أديكو السوقية: 18.44% (#1)'), findsOneWidget);
    });

    test('uploadFile correctly extracts repeated branches from Column H under إسم الفرع and skips preamble', () async {
      final apiClient = ApiClient(tenantId: 'adeco');

      const csvData = '''Details for Net Value,,,,,,,,,
,,,,,,,,,
السنة,الشهر,المورد,الفئة,الباركود,إسم الصنف,الوحدة,إسم الفرع,"صافى كمية
المبيعات","صافى قيمة 
المبيعات"
2025,يناير,ادكو / 318,منعمات ملابس مركزة,6223000238875,فلفيتا معطر ملابس مركز نسيم البحر 750 مل,قطعة,الإبراهيمية,17,612
2025,يناير,ادكو / 318,منعمات ملابس مركزة,6223000238868,فلفيتا معطر ملابس مركز همسات اللافندر 750 مل,قطعة,الجمرك,15,540
2025,يناير,ادكو / 318,منعمات ملابس مركزة,6223000234464,فلفيتا منعم ملابس مركز عطر الرفاهيه 1لتر,قطعة,الزيتون,6,763
2025,يناير,ادكو / 318,منعمات ملابس مركزة,6223000234488,فلفيتا منعم ملابس مركز عطر الاناقه 1لتر,قطعة,الساحل,7,927
2025,يناير,ادكو / 318,منعمات ملابس مركزة,6223000234525,فلفيتا منعم ملابس مركز عطر فريش 1لتر,قطعة,العصافرة,6,776
2025,يناير,ادكو / 318,منعمات ملابس مركزة,6223000234549,فلفيتا منعم ملابس مركز عطر ريلاكس 1لتر,قطعة,الإبراهيمية,11,1427
''';

      final bytes = utf8.encode(csvData);
      final res = await apiClient.uploadFile(
        'تقرير مبيعات فروع جملة ماركت.csv',
        bytes,
        targetChain: 'gomla',
      );

      expect(res.autoCreatedStoresCount, equals(5));
      expect(res.discoveredBranches.length, equals(5));
      final branchNames = res.discoveredBranches.map((b) => b['store_name']).toList();
      expect(branchNames, containsAll(['الإبراهيمية', 'الجمرك', 'الزيتون', 'الساحل', 'العصافرة']));
      expect(res.validRows, equals(6));
      expect(res.totalRevenue, equals(612 + 540 + 763 + 927 + 776 + 1427));
    });
  });
}
