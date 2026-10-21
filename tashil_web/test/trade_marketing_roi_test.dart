import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tashil_web/core/network/api_client.dart';
import 'package:tashil_web/core/theme/app_theme.dart';
import 'package:tashil_web/features/trade_marketing/presentation/screens/trade_marketing_roi_screen.dart';

void main() {
  group('Trade Marketing & Promo ROI Screen Tests', () {
    late ApiClient apiClient;

    setUp(() {
      apiClient = ApiClient();
    });

    testWidgets(
      'Renders 4 symmetrical KPI cards, English SegmentedButton tabs, MoM/YoY growth matrix, and supports adding expenses',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(1600, 1100);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

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
            home: TradeMarketingRoiScreen(apiClient: apiClient),
          ),
        );

        await tester.pumpAndSettle();

        // Verify 4 symmetrical KPI cards (Arabic on top, English below)
        expect(find.text('إجمالي المصروفات الترويجية'), findsOneWidget);
        expect(find.text('Total Trade Marketing Spend'), findsOneWidget);

        expect(find.text('نمو المبيعات عن الشهر السابق'), findsOneWidget);
        expect(find.text('MoM Sales Growth Lift'), findsOneWidget);

        expect(find.text('نمو المبيعات عن العام السابق'), findsOneWidget);
        expect(find.text('YoY Same-Month Sales Lift'), findsOneWidget);

        expect(find.text('العائد على الإنفاق التسويقي'), findsOneWidget);
        expect(find.text('Return on Marketing Spend (ROMI)'), findsOneWidget);

        // Verify 3 English SegmentedButton tabs
        expect(find.text('ROI & Growth Matrix'), findsOneWidget);
        expect(find.text('Campaigns & Expense Ledger'), findsOneWidget);
        expect(find.text('Activity & Brand Analytics'), findsOneWidget);

        // Verify 4 English MD3 Action Buttons
        expect(find.byKey(const ValueKey('btn_add_marketing_expense')), findsOneWidget);
        expect(find.byKey(const ValueKey('btn_roi_simulator')), findsOneWidget);
        expect(find.byKey(const ValueKey('btn_export_roi_excel')), findsOneWidget);
        expect(find.byKey(const ValueKey('btn_print_roi_pdf')), findsOneWidget);

        // Verify January 2026 Fathalla MoM and YoY growth badges in the matrix
        expect(find.textContaining('+32.4% MoM'), findsOneWidget);
        expect(find.textContaining('+41.2% YoY'), findsOneWidget);

        // Switch to Tab 1: Campaigns & Expense Ledger
        await tester.tap(find.text('Campaigns & Expense Ledger'));
        await tester.pumpAndSettle();

        expect(
          find.textContaining('سجل المصروفات الترويجية والحملات التفصيلي'),
          findsOneWidget,
        );

        // Switch to Tab 2: Activity & Brand Analytics
        await tester.tap(find.text('Activity & Brand Analytics'));
        await tester.pumpAndSettle();

        expect(
          find.textContaining('توزيع الميزانية التسويقية حسب نوع النشاط الترويجي'),
          findsOneWidget,
        );
      },
    );
  });
}
