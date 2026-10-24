import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/m3_dropdown_tester.dart';
import 'package:tashil_web/core/network/api_client.dart';
import 'package:tashil_web/features/data_ingestion/presentation/screens/upload_portal_screen.dart';
import 'package:tashil_web/features/executive_dashboard/presentation/widgets/chain_share_pie.dart';
import 'package:tashil_web/features/super_admin/presentation/screens/super_admin_screen.dart';

void main() {
  group('Retail Chain Model & Per-Company ApiClient Tests', () {
    test('RetailChainModel serializes and deserializes with tenant_id', () {
      final json = {
        'chain_id': 'hyperone',
        'tenant_id': 'adeco',
        'display_name': 'هايبر وان (Hyper One)',
        'code': 'hyperone',
        'chain_type': 'hypermarket',
        'store_count': 4,
        'created_at': '2026-03-08T12:00:00Z',
      };

      final model = RetailChainModel.fromJson(json);
      expect(model.chainId, equals('hyperone'));
      expect(model.tenantId, equals('adeco'));
      expect(model.displayName, equals('هايبر وان (Hyper One)'));
      expect(model.code, equals('hyperone'));
      expect(model.chainType, equals('hypermarket'));
      expect(model.storeCount, equals(4));

      final serialized = model.toJson();
      expect(serialized['chain_id'], equals('hyperone'));
      expect(serialized['tenant_id'], equals('adeco'));
      expect(serialized['store_count'], equals(4));
    });

    test('ApiClient getRetailChains returns Adeco chains and isolates other companies', () async {
      final adecoClient = ApiClient(tenantId: 'tenant-adeco');
      final adecoChains = await adecoClient.getRetailChains();

      expect(adecoChains.isNotEmpty, isTrue);
      expect(adecoChains.any((c) => c.code == 'fathalla'), isTrue);
      expect(adecoChains.any((c) => c.code == 'gomla'), isTrue);
      expect(adecoChains.any((c) => c.code == 'beet-elgomla'), isTrue);

      final otherClient = ApiClient(tenantId: 'tenant-newco');
      final otherChains = await otherClient.getRetailChains();
      expect(otherChains, isEmpty);
    });

    test('ApiClient createRetailChain, updateRetailChain, and deleteRetailChain are strictly scoped per company', () async {
      final companyAClient = ApiClient(tenantId: 'tenant-companya');
      final companyBClient = ApiClient(tenantId: 'tenant-companyb');

      final newChain = await companyAClient.createRetailChain(
        displayName: 'هايبر وان الشيخ زايد',
      );

      expect(newChain.code, equals('hyperone'));
      expect(newChain.displayName, equals('هايبر وان الشيخ زايد (Hyper One Alshykh Zayd)'));
      expect(newChain.tenantId, equals('companya'));

      final chainsA = await companyAClient.getRetailChains();
      expect(chainsA.any((c) => c.code == 'hyperone'), isTrue);

      // Company B must NOT see Company A's chain
      final chainsB = await companyBClient.getRetailChains();
      expect(chainsB.any((c) => c.code == 'hyperone'), isFalse);

      // Update chain in Company A
      final updated = await companyAClient.updateRetailChain(
        code: 'hyperone',
        displayName: 'هايبر وان المعدل',
      );
      expect(updated.displayName, equals('هايبر وان المعدل (Hyper One Almadl)'));
      expect(
        ApiClient.getRetailChainShortAr('hyperone'),
        equals('هايبر وان المعدل'),
      );

      // Delete chain in Company A
      await companyAClient.deleteRetailChain('hyperone');
      final chainsAAfterDelete = await companyAClient.getRetailChains();
      expect(chainsAAfterDelete.any((c) => c.code == 'hyperone'), isFalse);
    });
  });

  group('SuperAdminScreen Per-Company Chains Architecture UI Tests', () {
    testWidgets('SuperAdminScreen shows per-company chains stat and removes global chain catalog', (tester) async {
      tester.view.physicalSize = const Size(1440, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final client = ApiClient(tenantId: 'system');
      await tester.pumpWidget(
        MaterialApp(
          home: SuperAdminScreen(apiClient: client),
        ),
      );
      await tester.pumpAndSettle();

      // Verify per-company chains metric tile
      expect(find.text('PER-COMPANY CHAINS'), findsOneWidget);
      expect(find.text('سلاسل خاصة بكل شركة (تُدار من صفحة الرفع)'), findsOneWidget);

      // Global Master Retail Chains Catalog and New Chain button are removed from SuperAdmin
      expect(find.text('Master Retail Chains Catalog'), findsNothing);
      expect(find.text('New Chain'), findsNothing);
    });
  });

  group('UploadPortalScreen Per-Company Chain Entry & Archive Tests', () {
    testWidgets('UploadPortalScreen displays per-company chain entry system and adds new chain to dropdown and archive tabs', (tester) async {
      tester.view.physicalSize = const Size(1440, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final client = ApiClient(tenantId: 'tenant-adeco');
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: UploadPortalScreen(apiClient: client),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Verify per-company chain management box is visible in UploadPortalScreen
      expect(find.byKey(const ValueKey('company_chains_management_box')), findsOneWidget);
      expect(find.textContaining('نظام إدخال سلاسل التجزئة بالشركة'), findsOneWidget);
      expect(find.byKey(const ValueKey('company_new_chain_input')), findsOneWidget);
      expect(find.byKey(const ValueKey('company_add_chain_button')), findsOneWidget);

      // Verify existing Adeco chains appear in M3 ButtonsGroup and in archive tabs
      expect(find.byKey(const ValueKey('company_chain_btn_fathalla')), findsOneWidget);
      expect(find.byKey(const ValueKey('company_chain_btn_gomla')), findsOneWidget);
      expect(find.byKey(const ValueKey('company_chain_btn_beet-elgomla')), findsOneWidget);

      // Add a new chain ("سعودي ماركت") directly from the Upload page
      await tester.enterText(
        find.byKey(const ValueKey('company_new_chain_input')),
        'سعودي ماركت',
      );
      await tester.tap(find.byKey(const ValueKey('company_add_chain_button')));
      await tester.pumpAndSettle();

      // Verify the new chain button is added and automatically selected in the dropdown and archive tabs
      expect(find.byKey(const ValueKey('company_chain_btn_seoudi')), findsOneWidget);
      expect(find.textContaining('سعودي ماركت'), findsWidgets);
      expect(find.text('سعودي ماركت (0)'), findsOneWidget);
    });

    testWidgets('UploadPortalScreen blocks upload and shows red warning when no retail chain is selected, then clears on selection', (tester) async {
      tester.view.physicalSize = const Size(1440, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final client = ApiClient(tenantId: 'tenant-adeco');
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: UploadPortalScreen(apiClient: client),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Initially no error banner
      expect(find.byKey(const ValueKey('missing_chain_error_banner')), findsNothing);

      // Attempt to click "اختيار ملف" without selecting any chain
      final pickBtn = find.text('اختيار ملف');
      await tester.ensureVisible(pickBtn);
      await tester.tap(pickBtn);
      await tester.pumpAndSettle();

      // Red warning banner appears
      expect(find.byKey(const ValueKey('missing_chain_error_banner')), findsOneWidget);

      // Select "جملة ماركت" from chain dropdown -> red error banner disappears automatically
      final dropdown = find.byKey(const ValueKey('ingestion_retail_chain_dropdown'));
      await tester.ensureVisible(dropdown);
      await tester.tap(dropdown);
      await tester.pumpAndSettle();
      await tester.tap(m3MenuEntry('جملة ماركت').last);
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('missing_chain_error_banner')), findsNothing);
    });

    testWidgets('UploadPortalScreen displays Retail Chain Excel Archive and filters by chain tab', (tester) async {
      tester.view.physicalSize = const Size(1440, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final client = ApiClient(tenantId: 'tenant-adeco');
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: UploadPortalScreen(apiClient: client),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Verify Excel Archive section is rendered with Fathalla, Gomla, and Beet El-Gomla workbooks
      expect(find.byKey(const ValueKey('excel_upload_archive_section')), findsOneWidget);
      expect(find.text('أرشيف شيتات الإكسيل المرفوعة حسب السلاسل'), findsOneWidget);
      expect(find.text('40-Adco -2026.xlsx'), findsOneWidget);
      expect(find.text('Book1 (2).xlsx'), findsOneWidget);
      expect(find.text('Book6.xlsx'), findsOneWidget);

      // Tap 'جملة ماركت (1)' segment in archive filter bar
      final gomlaTab = find.textContaining('جملة ماركت (').last;
      await tester.ensureVisible(gomlaTab);
      await tester.tap(gomlaTab);
      await tester.pumpAndSettle();

      expect(find.text('Book1 (2).xlsx'), findsOneWidget);
      expect(find.text('40-Adco -2026.xlsx'), findsNothing);
    });

    testWidgets('uploadFile respects selected targetChain, targetTenant, and periodDate parameters', (tester) async {
      final client = ApiClient(tenantId: 'tenant-adeco');
      final result = await client.uploadFile(
        'monthly_sales.csv',
        utf8.encode('باركود,اسم الصنف,الفرع,الكمية,صافي المبيعات\n6221155001234,Adeco Extra Virgin Olive Oil 500ml,فرع سموحة,10,2500\n'),
        targetChain: 'fathalla',
        targetTenant: 'adeco',
        periodDate: '2025-02-15',
      );

      expect(result.retailerDetected, equals('fathalla'));
      expect(result.validRows, greaterThanOrEqualTo(1));

      final committed = await client.commitStagedUpload(
        batchId: result.batchId,
        targetChain: 'fathalla',
        periodDate: '2025-02-15',
      );
      expect(committed.isCommitted, isTrue);
    });

    test('ChainSharePie.labelForChain and ApiClient resolve custom chain الوكالة (chain-1080314)', () {
      expect(ApiClient.generateChainCode('الوكالة'), equals('chain-1080314'));
      expect(ChainSharePie.labelForChain('chain-1080314'), equals('الوكالة (El Wakala)'));
      expect(ApiClient.getRetailChainShortAr('chain-1080314'), equals('الوكالة'));
      expect(ApiClient.getRetailChainDisplayName('chain-1080314'), equals('الوكالة (El Wakala)'));
    });
  });
}


