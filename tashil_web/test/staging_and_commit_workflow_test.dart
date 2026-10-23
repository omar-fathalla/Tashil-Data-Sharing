import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tashil_web/core/network/api_client.dart';
import 'package:tashil_web/core/theme/app_theme.dart';
import 'package:tashil_web/core/utils/web_file_helper.dart';
import 'package:tashil_web/features/data_ingestion/presentation/screens/upload_portal_screen.dart';

void main() {
  group('UploadPortalScreen Staging, Chain Mismatch & Commit Workflow Tests', () {
    testWidgets('Upload stages data first, shows staging banner, commit and discard actions', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1440, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final apiClient = ApiClient(tenantId: 'tenant_adeco');
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: UploadPortalScreen(apiClient: apiClient),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Pick a sample CSV file
      WebFileHelper.nextMockPickedFile = PickedFileData(
        name: 'fathalla_october_sales.csv',
        bytes: WebFileHelper.sampleCarrefourCsvBytes(),
      );

      // Attempting to drop a file onto the dropzone before selecting chain shows red warning banner and blocks drop
      final droppedWithoutChain = WebFileHelper.simulateFileDrop(
        'fathalla_october_sales.csv',
        WebFileHelper.sampleCarrefourCsvBytes(),
      );
      await tester.pumpAndSettle();
      expect(droppedWithoutChain, isFalse);
      expect(find.byKey(const ValueKey('missing_chain_error_banner')), findsOneWidget);

      // Attempting to pick file before selecting chain also shows red warning banner and does NOT consume file
      await tester.tap(find.text('اختيار ملف'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('missing_chain_error_banner')), findsOneWidget);
      expect(WebFileHelper.nextMockPickedFile, isNotNull);

      // Select 'أسواق فتح الله' from chain dropdown -> clears red error banner
      await tester.tap(find.byKey(const ValueKey('ingestion_retail_chain_dropdown')));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('أسواق فتح الله').last);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('missing_chain_error_banner')), findsNothing);

      await tester.tap(find.text('اختيار ملف'));
      await tester.pump();
      await tester.pumpAndSettle();

      // 1. Verify staging banner & status (NOT auto-committed)
      expect(find.byKey(const ValueKey('staging_review_banner')), findsOneWidget);
      expect(find.text('وضع المعاينة والتدقيق الأمني (Staging & Review)'), findsOneWidget);
      expect(find.text('لم يتم الحفظ في BigQuery بعد'), findsOneWidget);
      expect(find.text('جاهز للاعتماد والحفظ النهائي'), findsOneWidget);

      // 2. Verify Commit & Discard action buttons are present
      expect(find.byKey(const ValueKey('commit_action_toolbar')), findsOneWidget);
      expect(find.descendant(of: find.byKey(const ValueKey('commit_action_toolbar')), matching: find.text('اعتماد البيانات')), findsOneWidget);
      expect(find.descendant(of: find.byKey(const ValueKey('commit_action_toolbar')), matching: find.text('إلغاء')), findsOneWidget);

      // 3. Test Discard action -> removes uncommitted file from archive as well
      final discardBtn = find.descendant(of: find.byKey(const ValueKey('commit_action_toolbar')), matching: find.text('إلغاء'));
      await tester.ensureVisible(discardBtn);
      await tester.tap(discardBtn);
      await tester.pumpAndSettle();

      // Preview should be cleared and discarded file should not remain in archive
      expect(find.byKey(const ValueKey('staging_review_banner')), findsNothing);
      expect(find.byKey(const ValueKey('commit_action_toolbar')), findsNothing);
      expect(find.text('fathalla_october_sales.csv'), findsNothing);
    });

    testWidgets('Detects retail chain mismatch and allows 1-click automatic chain correction updating archive counts', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1440, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final apiClient = ApiClient(tenantId: 'tenant_adeco');
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: UploadPortalScreen(apiClient: apiClient),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Select 'fathalla' first, then upload a file whose name/content is 'gomla' (Gomla Market)
      await tester.tap(find.byKey(const ValueKey('ingestion_retail_chain_dropdown')));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('أسواق فتح الله').last);
      await tester.pumpAndSettle();

      WebFileHelper.nextMockPickedFile = PickedFileData(
        name: 'Gomla_Market_October_Sales.csv',
        bytes: WebFileHelper.sampleCarrefourCsvBytes(),
      );

      await tester.tap(find.text('اختيار ملف'));
      await tester.pump();
      await tester.pumpAndSettle();

      // Verify Chain Mismatch Warning Card is rendered
      expect(find.byKey(const ValueKey('chain_mismatch_alert_card')), findsOneWidget);
      expect(find.text('تنبيه تعارض سلسلة التجزئة (Chain Mismatch Detected)'), findsOneWidget);
      expect(find.descendant(of: find.byKey(const ValueKey('chain_mismatch_alert_card')), matching: find.text('تصحيح السلسلة')), findsOneWidget);

      // Click 1-click chain fixer button
      final fixBtn = find.descendant(of: find.byKey(const ValueKey('chain_mismatch_alert_card')), matching: find.text('تصحيح السلسلة'));
      await tester.ensureVisible(fixBtn);
      await tester.tap(fixBtn);
      await tester.pumpAndSettle();

      // Warning card should disappear after correction and archive counts immediately reflect Gomla (2) and Fathalla (1)
      expect(find.byKey(const ValueKey('chain_mismatch_alert_card')), findsNothing);
      expect(find.text('جملة ماركت (2)'), findsWidgets);
      expect(find.text('أسواق فتح الله (1)'), findsWidgets);

      // Commit the staged data under corrected Gomla chain
      final commitBtn = find.descendant(of: find.byKey(const ValueKey('commit_action_toolbar')), matching: find.text('اعتماد البيانات'));
      await tester.ensureVisible(commitBtn);
      await tester.tap(commitBtn);
      await tester.pumpAndSettle();

      expect(find.text('تأكيد اعتماد وحفظ البيانات'), findsOneWidget);
      await tester.tap(find.text('تأكيد الحفظ والاعتماد'));
      await tester.pump();
      await tester.pumpAndSettle();

      // Verify committed success banner and archive counts still reflect Gomla (2) and Fathalla (1)
      expect(find.byKey(const ValueKey('committed_success_banner')), findsOneWidget);
      expect(find.text('تم حفظ واعتماد البيانات نهائياً في النظام (Committed to BigQuery)'), findsOneWidget);
      expect(find.text('جملة ماركت (2)'), findsWidgets);
      expect(find.text('أسواق فتح الله (1)'), findsWidgets);
    });
  });
}
