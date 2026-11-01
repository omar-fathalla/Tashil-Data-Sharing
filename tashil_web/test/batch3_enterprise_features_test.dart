import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tashil_web/core/network/api_client.dart';
import 'package:tashil_web/core/theme/app_theme.dart';
import 'package:tashil_web/core/utils/excel_export_service.dart';
import 'package:tashil_web/features/auth/presentation/widgets/user_profile_dialog.dart';
import 'package:tashil_web/features/data_ingestion/presentation/screens/upload_portal_screen.dart';
import 'package:tashil_web/features/executive_dashboard/presentation/screens/executive_screen.dart';
import 'package:tashil_web/features/executive_dashboard/presentation/widgets/bento_kpi_grid.dart';
import 'package:tashil_web/features/executive_dashboard/presentation/widgets/pareto_category_section.dart';
import 'package:tashil_web/features/oos_monitor/presentation/screens/oos_dashboard_screen.dart';
import 'package:tashil_web/features/sell_out_analytics/presentation/screens/sell_out_explorer_screen.dart';
import 'package:tashil_web/features/super_admin/presentation/screens/super_admin_screen.dart';
import 'package:tashil_web/features/super_admin/presentation/widgets/audit_logs_panel.dart';

void main() {
  group('Batch 3 — 1. YoY/MoM Growth, OSA%, Category Contribution & Pareto 80/20', () {
    test('CategoryContributionModel and ParetoSkuItemModel serialize and handle empty/missing JSON fields', () {
      final cat = CategoryContributionModel.fromJson({
        'category': 'زيوت طعام',
        'total_revenue': 2328110.4,
        'total_units': 18456,
        'share_pct': 48.0,
        'sku_count': 6,
      });
      expect(cat.category, equals('زيوت طعام'));
      expect(cat.sharePct, equals(48.0));
      expect(cat.skuCount, equals(6));
      expect(cat.toJson()['share_pct'], equals(48.0));

      final emptyCat = CategoryContributionModel.fromJson({});
      expect(emptyCat.category, equals(''));
      expect(emptyCat.totalRevenue, equals(0.0));
      expect(emptyCat.sharePct, equals(0.0));

      final pareto = ParetoSkuItemModel.fromJson({
        'barcode': '6221155001234',
        'sku_name': 'Adeco Extra Virgin Olive Oil 500ml',
        'category': 'زيوت طعام',
        'total_revenue': 1425000.0,
        'total_units': 5700,
        'revenue_share_pct': 29.4,
        'cumulative_share_pct': 29.4,
        'is_top_80_contributor': true,
      });
      expect(pareto.isTop80Contributor, isTrue);
      expect(pareto.cumulativeSharePct, equals(29.4));
      expect(pareto.toJson()['is_top_80_contributor'], isTrue);

      final emptyPareto = ParetoSkuItemModel.fromJson({});
      expect(emptyPareto.isTop80Contributor, isFalse);
      expect(emptyPareto.revenueSharePct, equals(0.0));
    });

    test('ApiClient returns tenant-isolated YoY, MoM, OSA%, categories, and Pareto 80/20 SKUs', () async {
      final adecoClient = ApiClient(tenantId: 'tenant-adeco');
      final adecoKpis = await adecoClient.getExecutiveKPIs();
      expect(adecoKpis.revenueMomPct, equals(14.8));
      expect(adecoKpis.revenueYoyPct, equals(24.5));
      expect(adecoKpis.unitsMomPct, equals(9.2));
      expect(adecoKpis.unitsYoyPct, equals(16.4));
      expect(adecoKpis.osaRatePct, equals(96.8));
      expect(adecoKpis.oosRatePct, equals(3.2));
      expect(adecoKpis.categoryContributions.length, equals(3));
      expect(adecoKpis.categoryContributions.first.category, equals('زيوت طعام'));
      expect(adecoKpis.paretoSkus.length, equals(5));
      expect(adecoKpis.paretoSkus.where((s) => s.isTop80Contributor).length, equals(3));

      final uniClient = ApiClient(tenantId: 'tenant-unilever');
      final uniKpis = await uniClient.getExecutiveKPIs();
      expect(uniKpis.osaRatePct, equals(97.1));
      expect(uniKpis.categoryContributions.first.category, equals('مشروبات ساخنة وشاي'));
      expect(uniKpis.paretoSkus.first.skuName, contains('Lipton'));
    });

    testWidgets('BentoKpiGrid displays MoM, YoY, and On-Shelf Availability (OSA%) badges', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final apiClient = ApiClient(tenantId: 'tenant-adeco');
      final kpis = await apiClient.getExecutiveKPIs();

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: SingleChildScrollView(
              child: BentoKpiGrid(kpis: kpis),
            ),
          ),
        ),
      );

      expect(find.text('+14.8% مقارنة بالشهر السابق'), findsOneWidget);
      expect(find.text('MoM'), findsNWidgets(2));
      expect(find.text('+24.5% مقارنة بالعام السابق'), findsOneWidget);
      expect(find.text('YoY'), findsNWidgets(2));
      expect(find.text('+9.2% مقارنة بالشهر السابق'), findsOneWidget);
      expect(find.text('+16.4% مقارنة بالعام السابق'), findsOneWidget);
      expect(find.text('التوفر على الرف (OSA) 96.8%'), findsOneWidget);
      expect(find.textContaining('OSA '), findsWidgets);
      expect(find.textContaining('نفاد المخزون 3.2%'), findsOneWidget);
      expect(find.textContaining('OOS rate •'), findsOneWidget);
    });

    testWidgets('ParetoCategorySection renders Category Contribution and Pareto 80/20 cards and handles empty lists', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1440, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      // Empty state edge case
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: const Scaffold(
            body: ParetoCategorySection(categories: [], paretoSkus: []),
          ),
        ),
      );
      expect(find.byKey(const ValueKey('category_contribution_card')), findsNothing);

      // Populated state via ExecutiveScreen
      final apiClient = ApiClient(tenantId: 'tenant-adeco');
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: ExecutiveScreen(apiClient: apiClient),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Category Contribution'), findsOneWidget);
      expect(find.text('Top SKUs (Pareto 80/20)'), findsOneWidget);
      expect(find.text('المبيعات والحصة السوقية لكل فئة'), findsOneWidget);
      // Exclude the new Market Share section above, which also lists categories.
      final inNewSection = find.descendant(
        of: find.byKey(const ValueKey('market_share_section')),
        matching: find.text('زيوت طعام'),
      );
      expect(
        find.text('زيوت طعام').evaluate().length - inNewSection.evaluate().length,
        1,
      );

      // Verify interactive drilldown: tapping a category filters the Pareto list
      final existingCat = find.descendant(
        of: find.byKey(const ValueKey('category_contribution_card')),
        matching: find.text('زيوت طعام'),
      ).first;
      await tester.ensureVisible(existingCat);
      await tester.pumpAndSettle();
      await tester.tap(existingCat);
      await tester.pumpAndSettle();

      expect(find.textContaining('زيوت طعام · '), findsOneWidget);
      expect(find.text('عرض كل الفئات'), findsOneWidget);
      expect(find.text('عرض الكل'), findsOneWidget);

      // Tap clear to reset back to global Pareto SKUs
      await tester.tap(find.text('عرض كل الفئات'));
      await tester.pumpAndSettle();

      expect(find.textContaining('أصناف فئة:'), findsNothing);
      expect(find.text('تصنيف A'), findsNWidgets(3));
      expect(find.text('تصنيف B/C'), findsNWidgets(2));
    });

    testWidgets('OOSDashboardScreen renders On-Shelf Availability (مؤشر التوافر على الرفوف OSA%) summary card', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final apiClient = ApiClient(tenantId: 'tenant-adeco');
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: OOSDashboardScreen(apiClient: apiClient),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('osa_summary_card')), findsOneWidget);
      expect(find.text('مؤشر التوافر على الرفوف OSA%'), findsOneWidget);
      expect(find.text('96.8%'), findsOneWidget);
    });
  });

  group('Batch 3 — 2. 5-Role Enterprise RBAC Matrix, NDA Competitor Masking & Role Switcher', () {
    test('TenantUserModel maps all 5 enterprise roles and enforces permission flags', () {
      final superAdmin = TenantUserModel(
        userId: 'u1',
        tenantId: 'system',
        email: 'super@tashil.io',
        fullName: 'Super Admin',
        role: 'super_admin',
      );
      expect(superAdmin.roleDisplayAr, equals('مدير النظام المركزي'));
      expect(superAdmin.canUploadFiles, isTrue);
      expect(superAdmin.canExportFinancials, isTrue);
      expect(superAdmin.canViewAuditLogs, isTrue);

      final vendorAdmin = superAdmin.copyWith(role: 'vendor_admin', tenantId: 'adeco');
      expect(vendorAdmin.roleDisplayAr, equals('مدير الشركة الموردة'));
      expect(vendorAdmin.canUploadFiles, isTrue);
      expect(vendorAdmin.canExportFinancials, isTrue);
      expect(vendorAdmin.canViewAuditLogs, isTrue);

      final nsm = vendorAdmin.copyWith(role: 'national_sales_manager');
      expect(nsm.roleDisplayAr, equals('مدير المبيعات الوطني'));
      expect(nsm.canUploadFiles, isTrue);
      expect(nsm.canExportFinancials, isTrue);
      expect(nsm.canViewAuditLogs, isFalse);

      final chainKam = vendorAdmin.copyWith(role: 'chain_kam', assignedChain: 'carrefour');
      expect(chainKam.roleDisplayAr, equals('مدير حسابات السلاسل (KAM)'));
      expect(chainKam.canUploadFiles, isFalse);
      expect(chainKam.canExportFinancials, isTrue);
      expect(chainKam.canViewAuditLogs, isFalse);

      final fieldSup = vendorAdmin.copyWith(role: 'field_supervisor', assignedRegion: 'شرق الإسكندرية');
      expect(fieldSup.roleDisplayAr, equals('مشرف ميداني (Field Supervisor)'));
      expect(fieldSup.canUploadFiles, isFalse);
      expect(fieldSup.canExportFinancials, isFalse);
      expect(fieldSup.canViewAuditLogs, isFalse);
    });

    test('ApiClient enforces NDA competitor masking for chain_kam and region scoping for field_supervisor', () async {
      final apiClient = ApiClient(tenantId: 'tenant-adeco');
      apiClient.currentUser = TenantUserModel(
        userId: 'kam-1',
        tenantId: 'adeco',
        email: 'kam.carrefour@adeco-retail.com',
        fullName: 'Chain KAM Carrefour',
        role: 'chain_kam',
        assignedChain: 'carrefour',
      );

      expect(apiClient.requestHeaders['X-Simulated-Role'], equals('chain_kam'));
      expect(apiClient.requestHeaders['X-Assigned-Chain'], equals('carrefour'));

      // 1. NDA masking in ExecutiveKPIs
      final kpis = await apiClient.getExecutiveKPIs();
      final carrefourShare = kpis.chainShares.firstWhere((c) => c.retailerChain == 'carrefour');
      expect(carrefourShare.displayName, equals('كارفور (Carrefour)'));
      final competitorShares = kpis.chainShares.where((c) => c.retailerChain != 'carrefour').toList();
      expect(competitorShares, isNotEmpty);
      for (final comp in competitorShares) {
        expect(comp.retailerChain, equals('nda_redacted'));
        expect(comp.displayName, equals('سلسلة تجزئة منافسة (محمي بـ NDA)'));
      }

      // 2. Chain filtering in getRecords, getStoreBenchmarkMatrix, getPricingCompliance, getOOSAlerts
      final records = await apiClient.getRecords();
      expect(records, isNotEmpty);
      expect(records.every((r) => r.retailerChain == 'carrefour'), isTrue);

      final stores = await apiClient.getStoreBenchmarkMatrix();
      expect(stores, isNotEmpty);
      expect(stores.every((s) => s.retailerChain == 'carrefour'), isTrue);

      final compliance = await apiClient.getPricingCompliance();
      expect(compliance, isNotEmpty);
      expect(compliance.every((c) => c.retailerChain == 'carrefour'), isTrue);

      // OOS alerts: serve a mixed-chain server response and verify the
      // client strips competitor chains for the chain_kam persona.
      final alerts = await http.runWithClient(
        () => apiClient.getOOSAlerts(),
        () => MockClient((req) async {
          if (req.url.path.endsWith('/api/v1/analytics/oos-monitor')) {
            return http.Response(
              jsonEncode({
                'alerts': [
                  {'alert_id': 'a1', 'retailer_chain': 'carrefour', 'store_name': 'كارفور المعادي', 'sku_name': 'Adeco Oil 1L'},
                  {'alert_id': 'a2', 'retailer_chain': 'spinneys', 'store_name': 'سبينيس الرحاب', 'sku_name': 'Adeco Oil 1L'},
                  {'alert_id': 'a3', 'retailer_chain': 'fathalla', 'store_name': 'فتح الله سموحة', 'sku_name': 'Adeco Ghee 1kg'},
                ],
              }),
              200,
              headers: {'content-type': 'application/json; charset=utf-8'},
            );
          }
          throw http.ClientException('down');
        }),
      );
      expect(alerts, isNotEmpty);
      expect(alerts.length, 1, reason: 'competitor chain alerts must be filtered out');
      expect(alerts.every((a) => a.retailerChain == 'carrefour'), isTrue);

      // 3. Field supervisor region scoping
      apiClient.currentUser = TenantUserModel(
        userId: 'sup-1',
        tenantId: 'adeco',
        email: 'sup.alex@adeco-retail.com',
        fullName: 'Field Supervisor Alex',
        role: 'field_supervisor',
        assignedRegion: 'شرق الإسكندرية',
      );
      // Non-ASCII header values are percent-encoded so they are valid HTTP headers.
      expect(apiClient.requestHeaders['X-Assigned-Region'], equals(Uri.encodeComponent('شرق الإسكندرية')));
      final regionalStores = await apiClient.getStoreBenchmarkMatrix();
      expect(regionalStores, isNotEmpty);
      expect(regionalStores.every((s) => s.region == 'شرق الإسكندرية'), isTrue);
    });

    testWidgets('UserProfileDialog switches between the 5 RBAC personas and updates user scope', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final apiClient = ApiClient(tenantId: 'tenant-adeco');
      bool roleChangedCalled = false;

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: UserProfileDialog(
              apiClient: apiClient,
              tenantSlug: 'adeco',
              onRoleChanged: () => roleChangedCalled = true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('RBAC Role Switcher'), findsOneWidget);
      expect(find.text('Audit Logs'), findsOneWidget);

      // Open Audit Logs dialog from UserProfileDialog and verify AuditLogsPanel renders
      await tester.tap(find.text('Audit Logs'));
      await tester.pumpAndSettle();
      expect(find.byType(AuditLogsPanel), findsOneWidget);
      await tester.tap(find.byIcon(Icons.close_rounded));
      await tester.pumpAndSettle();

      // Switch to Chain KAM (Carrefour)
      final kamOption = find.byKey(const ValueKey('rbac_persona_chain_kam_carrefour'));
      await tester.ensureVisible(kamOption);
      await tester.tap(kamOption);
      await tester.pumpAndSettle();

      expect(roleChangedCalled, isTrue);
      expect(apiClient.currentUser?.role, equals('chain_kam'));
      expect(apiClient.currentUser?.assignedChain, equals('carrefour'));
      expect(find.text('Carrefour Chain'), findsOneWidget);
      // Audit logs button should be hidden for chain_kam
      expect(find.text('Audit Logs'), findsNothing);

      // Switch to Field Supervisor (Alexandria)
      final supOption = find.byKey(const ValueKey('rbac_persona_field_supervisor_alex'));
      await tester.ensureVisible(supOption);
      await tester.tap(supOption);
      await tester.pumpAndSettle();

      expect(apiClient.currentUser?.role, equals('field_supervisor'));
      expect(apiClient.currentUser?.assignedRegion, equals('شرق الإسكندرية'));
      expect(find.text('East Alexandria Region'), findsOneWidget);
    });

    testWidgets('SellOutExplorerScreen and UploadPortalScreen enforce RBAC restrictions for field_supervisor', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      ExcelExportService.resetLastDownloaded();

      final apiClient = ApiClient(tenantId: 'tenant-adeco');
      apiClient.currentUser = TenantUserModel(
        userId: 'sup-1',
        tenantId: 'adeco',
        email: 'sup.alex@adeco-retail.com',
        fullName: 'Field Supervisor Alex',
        role: 'field_supervisor',
        assignedRegion: 'شرق الإسكندرية',
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: SellOutExplorerScreen(apiClient: apiClient),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // RBAC restriction banner is visible
      expect(find.byKey(const ValueKey('rbac_export_restricted_banner')), findsOneWidget);

      // Tapping export is blocked and does not download a CSV
      await tester.tap(find.text('Export Excel'));
      await tester.pumpAndSettle();
      expect(ExcelExportService.lastDownloadedFilename, isNull);

      // UploadPortalScreen also shows RBAC upload restriction banner for field_supervisor
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: UploadPortalScreen(apiClient: apiClient),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('rbac_upload_restricted_banner')), findsOneWidget);
    });
  });

  group('Batch 3 — 3. Enterprise Security Audit Logs (AuditLogEntryModel & AuditLogsPanel)', () {
    test('ApiClient isolates tenant audit logs for vendor_admin and returns all logs for super_admin', () async {
      final adecoClient = ApiClient(tenantId: 'tenant-adeco');
      adecoClient.currentUser = TenantUserModel(
        userId: 'u-adeco',
        tenantId: 'adeco',
        email: 'admin@adeco-retail.com',
        fullName: 'Adeco Admin',
        role: 'vendor_admin',
      );

      final adecoLogs = await adecoClient.getAuditLogs();
      expect(adecoLogs, isNotEmpty);
      expect(adecoLogs.every((l) => l.tenantId == 'adeco'), isTrue);

      // Record a new audit log and verify it appears at the top
      final recorded = await adecoClient.recordAuditLog(
        action: 'EXPORT_EXCEL',
        resource: 'test_export.csv',
        details: 'تصدير تجريبي للتحقق من سجل التدقيق',
      );
      expect(recorded.action, equals('EXPORT_EXCEL'));

      final exportLogs = await adecoClient.getAuditLogs(actionFilter: 'EXPORT');
      expect(exportLogs.any((l) => l.resource == 'test_export.csv'), isTrue);

      // Super Admin sees logs across all tenants
      final superClient = ApiClient(tenantId: 'system');
      superClient.currentUser = TenantUserModel(
        userId: 'u-super',
        tenantId: 'system',
        email: 'superadmin@tashil.io',
        fullName: 'Super Admin',
        role: 'super_admin',
      );
      final allLogs = await superClient.getAuditLogs();
      expect(allLogs.any((l) => l.tenantId == 'adeco'), isTrue);
      expect(allLogs.any((l) => l.tenantId == 'unilever'), isTrue);
      expect(allLogs.any((l) => l.tenantId == 'system'), isTrue);
    });

    testWidgets('AuditLogsPanel renders inside SuperAdminScreen and filters by action chips', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1440, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final superClient = ApiClient(tenantId: 'system');
      superClient.currentUser = TenantUserModel(
        userId: 'u-super',
        tenantId: 'system',
        email: 'superadmin@tashil.io',
        fullName: 'Super Admin',
        role: 'super_admin',
      );

      // Seed two distinct audit events (served from the in-memory audit log
      // when the backend is unreachable in tests).
      await superClient.recordAuditLog(
        action: 'INGEST_UPLOAD',
        resource: 'batch3_upload_probe.xlsx',
        details: 'رفع ملف مبيعات batch3 probe',
      );
      await superClient.recordAuditLog(
        action: 'AUTH_LOGIN',
        resource: 'batch3_login_probe',
        details: 'تسجيل دخول batch3 probe',
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: SuperAdminScreen(apiClient: superClient),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(AuditLogsPanel), findsOneWidget);
      expect(find.text('Enterprise Security Audit Logs'), findsOneWidget);
      expect(find.text('batch3_upload_probe.xlsx'), findsWidgets);
      expect(find.text('batch3_login_probe'), findsWidgets);

      // Filter by the 'Uploads' segment
      final uploadsSegment = find.text('Uploads');
      await tester.ensureVisible(uploadsSegment);
      await tester.pumpAndSettle();
      await tester.tap(uploadsSegment);
      await tester.pumpAndSettle();

      expect(find.text('batch3_upload_probe.xlsx'), findsWidgets);
      expect(find.text('batch3_login_probe'), findsNothing);
    });
  });
}
