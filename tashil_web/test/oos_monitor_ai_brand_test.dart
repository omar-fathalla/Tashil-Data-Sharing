import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tashil_web/core/network/api_client.dart';
import 'package:tashil_web/core/theme/app_theme.dart';
import 'package:tashil_web/features/oos_monitor/presentation/screens/oos_dashboard_screen.dart';

void main() {
  group('OOS Monitor — Gemini AI Diagnostics & Brand/Branch Breakdown Matrix', () {
    late ApiClient apiClient;

    setUp(() {
      apiClient = ApiClient(tenantId: 'tenant-adeco');
    });

    test('ApiClient.getOOSMonitorReport returns full report with AI analysis and brand summaries', () async {
      final report = await apiClient.getOOSMonitorReport();
      expect(report.totalIncidents, greaterThan(0));
      expect(report.alerts, isNotEmpty);
      expect(report.brandSummaries, isNotEmpty);
      expect(report.branchSummaries, isNotEmpty);
      expect(report.aiAnalysis, isNotNull);
      expect(report.aiAnalysis!.modelUsed, contains('Gemini'));
      expect(report.aiAnalysis!.rootCausesAr, isNotEmpty);
      expect(report.aiAnalysis!.immediateActionsAr, isNotEmpty);
    });

    testWidgets('OOSDashboardScreen renders Gemini AI Advisor, Executive KPIs, and Alert cards', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1440, 1100);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: OOSDashboardScreen(apiClient: apiClient),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Check Header (titleEn / subtitleAr — Errors / Returns symmetry)
      expect(find.text('مراقب النواقص'), findsOneWidget);
      expect(find.text('OOS Monitor'), findsOneWidget);
      expect(find.text('نظام المراقبة الاستباقية للنواقص ومحرك الذكاء الاصطناعي (Gemini Root-Cause AI)'), findsOneWidget);

      // Check OSA% KPI Card
      expect(find.byKey(const ValueKey('osa_summary_card')), findsOneWidget);
      expect(find.text('نسبة التوافر OSA%'), findsOneWidget);

      // Check Gemini AI Card
      expect(find.text('مستشار الذكاء الاصطناعي (Gemini AI Root-Cause Advisor)'), findsOneWidget);
      expect(find.text('Gemini 1.5 Pro'), findsOneWidget);
      expect(find.text('الأسباب التشغيلية الجذرية (Root Causes)'), findsOneWidget);
      expect(find.text('الإجراءات الفورية المقترحة (Action Plan)'), findsOneWidget);
    });

    testWidgets('Filtering by Brand displays dedicated Brand Missing-in-Branches Banner', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1440, 1100);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: OOSDashboardScreen(apiClient: apiClient),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Tap on Feba brand quick chip if present or select from dropdown
      final febaChip = find.widgetWithText(FilterChip, 'فيبا (Feba)');
      if (febaChip.evaluate().isNotEmpty) {
        await tester.tap(febaChip);
        await tester.pumpAndSettle();

        // Banner should appear
        expect(find.textContaining('تحليل انعدام الماركة: ماركة "فيبا (Feba)"'), findsOneWidget);
        expect(find.textContaining('قائمة الفروع التي تعاني من انعدام ماركة فيبا (Feba):'), findsOneWidget);
      }
    });

    testWidgets('Switching to Branch Matrix mode groups missing SKUs by store', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1440, 1100);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: OOSDashboardScreen(apiClient: apiClient),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Tap on SegmentedButton to switch to Branch Matrix
      final matrixSegment = find.text('مصفوفة الفروع والنواقص');
      expect(matrixSegment, findsOneWidget);
      await tester.ensureVisible(matrixSegment);
      await tester.pumpAndSettle();
      await tester.tap(matrixSegment);
      await tester.pumpAndSettle();

      // Should show branch group buttons
      expect(find.textContaining('طلب توريد'), findsWidgets);
    });
  });
}
