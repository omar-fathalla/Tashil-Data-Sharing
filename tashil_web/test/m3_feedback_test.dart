import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tashil_web/core/theme/app_theme.dart';
import 'package:tashil_web/core/widgets/m3_feedback.dart';

void main() {
  group('M3Feedback & Data Deduplication Standard Tests', () {
    testWidgets('showDuplicateWarning renders amber warning icon and Arabic message', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () {
                  M3Feedback.showDuplicateWarning(
                    context,
                    title: 'تنبيه: ملف أو سجل مكرر بالكامل',
                    message: 'تم رصد هذا الملف مسبقاً وتخطي إعادة المعالجة لمنع تكرار البيانات.',
                    duplicateIdentifier: 'fact_adeco_carrefour_store01_6221001_2026-10-12',
                  );
                },
                child: const Text('Show Warning'),
              ),
            ),
          ),
        ),
      );

      // Tap button to trigger duplicate warning dialog
      await tester.tap(find.text('Show Warning'));
      await tester.pumpAndSettle();

      // Verify the amber warning icon is rendered
      expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);

      // Verify zero-tolerance compliance: strictly NO green checkmark icon
      expect(find.byIcon(Icons.check_circle_rounded), findsNothing);
      expect(find.byIcon(Icons.check_circle), findsNothing);

      // Verify text contents
      expect(find.text('تنبيه: ملف أو سجل مكرر بالكامل'), findsOneWidget);
      expect(find.text('تم رصد هذا الملف مسبقاً وتخطي إعادة المعالجة لمنع تكرار البيانات.'), findsOneWidget);
      expect(find.text('fact_adeco_carrefour_store01_6221001_2026-10-12'), findsOneWidget);

      // Dismiss dialog
      expect(find.text('إغلاق وتخطي التكرار'), findsOneWidget);
      await tester.tap(find.text('إغلاق وتخطي التكرار'));
      await tester.pumpAndSettle();

      // Dialog should now be closed
      expect(find.text('تنبيه: ملف أو سجل مكرر بالكامل'), findsNothing);
    });

    testWidgets('showSuccess renders success snackbar with check icon', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () {
                  M3Feedback.showSuccess(context, 'تمت العملية بنجاح');
                },
                child: const Text('Show Success'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Show Success'));
      await tester.pump();

      expect(find.text('تمت العملية بنجاح'), findsOneWidget);
      expect(find.byIcon(Icons.check_circle_rounded), findsOneWidget);
    });

    testWidgets('showError renders error snackbar with alert icon', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () {
                  M3Feedback.showError(context, 'حدث خطأ في النظام');
                },
                child: const Text('Show Error'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Show Error'));
      await tester.pump();

      expect(find.text('حدث خطأ في النظام'), findsOneWidget);
      expect(find.byIcon(Icons.error_outline_rounded), findsOneWidget);
    });
  });
}
