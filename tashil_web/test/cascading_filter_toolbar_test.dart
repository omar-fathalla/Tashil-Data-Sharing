import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tashil_web/core/theme/app_theme.dart';
import 'package:tashil_web/features/sell_out_analytics/presentation/widgets/cascading_filter_toolbar.dart';

void main() {
  group('CascadingFilterToolbar Widget & Layout Tests', () {
    testWidgets('renders all filter controls, search field, date range, and export buttons', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      bool excelExported = false;
      bool pdfExported = false;

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: SingleChildScrollView(
              child: CascadingFilterToolbar(
                selectedChain: null,
                selectedStoreId: null,
                selectedCategory: null,
                selectedDateRange: null,
                searchQuery: '',
                onChainChanged: (_) {},
                onStoreChanged: (_) {},
                onCategoryChanged: (_) {},
                onDateRangeChanged: (_) {},
                onSearchChanged: (_) {},
                onExportExcel: () => excelExported = true,
                onExportPdf: () => pdfExported = true,
              ),
            ),
          ),
        ),
      );

      // Verify controls exist
      expect(find.byKey(const ValueKey('sellout_date_range_chip')), findsOneWidget);
      expect(find.byKey(const ValueKey('export_excel_button')), findsOneWidget);
      expect(find.byKey(const ValueKey('export_pdf_button')), findsOneWidget);
      expect(find.text('Search SKU or Barcode...'), findsOneWidget);
      // DropdownMenu also lays out its entries offstage for sizing.
      expect(find.text('All Chains'), findsWidgets);

      // Tap export buttons to ensure callbacks fire
      await tester.tap(find.byKey(const ValueKey('export_excel_button')));
      await tester.pump();
      expect(excelExported, isTrue);

      await tester.tap(find.byKey(const ValueKey('export_pdf_button')));
      await tester.pump();
      expect(pdfExported, isTrue);
    });

    testWidgets('verifies Date Range and Export buttons are on the same vertical row in wide view', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: SingleChildScrollView(
              child: CascadingFilterToolbar(
                selectedChain: null,
                selectedStoreId: null,
                selectedCategory: null,
                selectedDateRange: null,
                searchQuery: '',
                onChainChanged: (_) {},
                onStoreChanged: (_) {},
                onCategoryChanged: (_) {},
                onDateRangeChanged: (_) {},
                onSearchChanged: (_) {},
                onExportExcel: () {},
                onExportPdf: () {},
              ),
            ),
          ),
        ),
      );

      final dateRangeTop = tester.getTopLeft(find.byKey(const ValueKey('sellout_date_range_chip'))).dy;
      final excelButtonTop = tester.getTopLeft(find.byKey(const ValueKey('export_excel_button'))).dy;
      final pdfButtonTop = tester.getTopLeft(find.byKey(const ValueKey('export_pdf_button'))).dy;

      // Both Date Range and Export buttons must be on the exact same row (same vertical dy offset)
      expect((dateRangeTop - excelButtonTop).abs(), lessThanOrEqualTo(1.0));
      expect((excelButtonTop - pdfButtonTop).abs(), lessThanOrEqualTo(1.0));
    });

    testWidgets('all dropdowns have transparent focusColor to prevent nested double input highlights', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: SingleChildScrollView(
              child: CascadingFilterToolbar(
                selectedChain: null,
                selectedStoreId: null,
                selectedCategory: null,
                selectedDateRange: null,
                searchQuery: '',
                onChainChanged: (_) {},
                onStoreChanged: (_) {},
                onCategoryChanged: (_) {},
                onDateRangeChanged: (_) {},
                onSearchChanged: (_) {},
                onExportExcel: () {},
                onExportPdf: () {},
              ),
            ),
          ),
        ),
      );

      // All toolbar dropdowns are M3 DropdownMenu (no legacy DropdownButton).
      expect(find.byType(DropdownButton<String?>), findsNothing);
      final dropdowns = tester.widgetList<DropdownMenu<String?>>(find.byType(DropdownMenu<String?>));
      expect(dropdowns.length, greaterThanOrEqualTo(3));
      for (final dd in dropdowns) {
        expect(dd.requestFocusOnTap, isFalse);
      }
    });

    testWidgets('chain dropdown contains English-only names (Beet El-Gomla and Institutions)', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: SingleChildScrollView(
              child: CascadingFilterToolbar(
                selectedChain: null,
                selectedStoreId: null,
                selectedCategory: null,
                selectedDateRange: null,
                searchQuery: '',
                onChainChanged: (_) {},
                onStoreChanged: (_) {},
                onCategoryChanged: (_) {},
                onDateRangeChanged: (_) {},
                onSearchChanged: (_) {},
                onExportExcel: () {},
                onExportPdf: () {},
              ),
            ),
          ),
        ),
      );

      // Open the chains dropdown
      await tester.tap(find.byKey(const ValueKey('sellout_chain_dropdown')));
      await tester.pumpAndSettle();

      // Verify English names exist without Arabic parentheses
      expect(find.text('Beet El-Gomla'), findsWidgets);
      expect(find.text('Institutions'), findsWidgets);
      expect(find.text('Beet El-Gomla (بيت الجملة)'), findsNothing);
      expect(find.text('Institutions (قطاع المؤسسات)'), findsNothing);
    });

    testWidgets('tapping barcode camera scanner button opens BarcodeScannerDialog and detects barcode', (WidgetTester tester) async {
      String searchedBarcode = '';

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: SingleChildScrollView(
              child: CascadingFilterToolbar(
                selectedChain: null,
                selectedStoreId: null,
                selectedCategory: null,
                selectedDateRange: null,
                searchQuery: '',
                onChainChanged: (_) {},
                onStoreChanged: (_) {},
                onCategoryChanged: (_) {},
                onDateRangeChanged: (_) {},
                onSearchChanged: (val) => searchedBarcode = val,
                onExportExcel: () {},
                onExportPdf: () {},
              ),
            ),
          ),
        ),
      );

      // Scanner button should be present in the search field
      final scannerButton = find.byKey(const ValueKey('barcode_camera_scanner_button'));
      expect(scannerButton, findsOneWidget);

      // Tap scanner button to open dialog
      await tester.tap(scannerButton);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Barcode dialog should be displayed with camera capture button
      expect(find.text('Smart Barcode Scanner'), findsOneWidget);
      expect(find.byKey(const ValueKey('scanner_simulate_capture_button')), findsOneWidget);

      // Tap simulate capture button
      await tester.tap(find.byKey(const ValueKey('scanner_simulate_capture_button')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();

      // Verify barcode was populated into search
      expect(searchedBarcode, equals('99069570'));
    });
  });
}

