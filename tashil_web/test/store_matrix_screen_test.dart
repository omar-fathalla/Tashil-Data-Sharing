import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tashil_web/core/network/api_client.dart';
import 'package:tashil_web/core/theme/app_theme.dart';
import 'package:tashil_web/features/store_benchmark/presentation/screens/store_matrix_screen.dart';

void main() {
  group('StoreMatrixScreen Widget Tests', () {
    late ApiClient apiClient;

    setUp(() {
      apiClient = ApiClient();
    });

    testWidgets('renders screen header, tier KPI cards, and store ranking table', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1440, 1024);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: StoreMatrixScreen(apiClient: apiClient),
          ),
        ),
      );

      // Allow async data loading
      await tester.pumpAndSettle();

      // Check Header
      expect(find.textContaining('Store Matrix Benchmarking'), findsOneWidget);

      // Check Regional Selector Segments
      expect(find.text('كافة المناطق'), findsOneWidget);
      expect(find.text('شرق الإسكندرية'), findsWidgets);
      expect(find.text('غرب الإسكندرية'), findsWidgets);
      expect(find.text('القاهرة الكبرى'), findsWidgets);

      // Check Tier Summary KPI Cards
      expect(find.textContaining('Tier A (الفئة الأولى - الرائدة)'), findsOneWidget);
      expect(find.textContaining('Tier B (الفئة المتوسطة)'), findsOneWidget);
      expect(find.textContaining('Tier C (الفئة القياسية / الناشئة)'), findsOneWidget);

      // Check Table Columns
      expect(find.text('الترتيب'), findsOneWidget);
      expect(find.text('اسم الفرع والسلسلة'), findsOneWidget);
      expect(find.text('المنطقة الجغرافية'), findsOneWidget);
      expect(find.text('تصنيف الفئة'), findsOneWidget);
      expect(find.text('إجمالي المبيعات'), findsOneWidget);
      expect(find.text('إجمالي الوحدات'), findsOneWidget);
      expect(find.text('معدل السرعة اليومي'), findsOneWidget);

      // Check Store Items
      expect(find.text('كارفور المعادي سيتي سنتر'), findsOneWidget);
      expect(find.text('فتح الله جملة ماركت - سموحة'), findsOneWidget);
      expect(find.text('فتح الله - المنشية'), findsOneWidget);

      // Check Ranks and Tier Badges
      expect(find.text('#1'), findsOneWidget);
      expect(find.text('Tier A'), findsWidgets);
      expect(find.text('Tier B'), findsWidgets);
      expect(find.text('Tier C'), findsWidgets);

      // Check Velocity indicator presence
      expect(find.byIcon(Icons.trending_up_rounded), findsWidgets);

      // Verify DataTable stretches to fill the full available card content width on desktop
      final dataTableSize = tester.getSize(find.byType(DataTable));
      expect(dataTableSize.width, greaterThanOrEqualTo(1300.0));
    });

    testWidgets('filtering by regional selector updates the store list', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1440, 1024);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: StoreMatrixScreen(apiClient: apiClient),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Tap on 'شرق الإسكندرية' segment
      final eastAlexSegment = find.text('شرق الإسكندرية').first;
      await tester.tap(eastAlexSegment);
      await tester.pumpAndSettle();

      // In East Alex: Smouha and Stanley exist
      expect(find.text('فتح الله جملة ماركت - سموحة'), findsOneWidget);
      expect(find.text('فتح الله - ستانلي'), findsOneWidget);

      // Cairo and West Alex stores should NOT be present in table
      expect(find.text('كارفور المعادي سيتي سنتر'), findsNothing);
      expect(find.text('فتح الله - المنشية'), findsNothing);
    });

    testWidgets('filtering by Tier segment updates the store list', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1440, 1024);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: StoreMatrixScreen(apiClient: apiClient),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Tap on 'Tier C' segment in M3SegmentedButtonGroup
      final tierCSegment = find.text('Tier C').first;
      expect(tierCSegment, findsOneWidget);
      await tester.tap(tierCSegment);
      await tester.pumpAndSettle();

      // Only Tier C store (Mansheya) should be in table
      expect(find.text('فتح الله - المنشية'), findsOneWidget);
      expect(find.text('كارفور المعادي سيتي سنتر'), findsNothing);
    });

    testWidgets('renders cleanly on compact mobile viewport without RenderFlex overflow', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: StoreMatrixScreen(apiClient: apiClient),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.textContaining('Store Matrix Benchmarking'), findsOneWidget);
      expect(find.text('#1'), findsOneWidget);
    });
  });
}
