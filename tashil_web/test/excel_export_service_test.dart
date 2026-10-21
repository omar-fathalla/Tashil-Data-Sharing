import 'package:flutter_test/flutter_test.dart';
import 'package:tashil_web/core/utils/excel_export_service.dart';

void main() {
  group('ExcelExportService Unit Tests', () {
    test('generateCsv includes UTF-8 BOM and formats Arabic data correctly', () {
      final headers = ['الباركود', 'اسم الصنف', 'السلسلة', 'الكمية', 'الإيراد'];
      final rows = [
        ['6221001122334', 'زيت أديكو ممتاز 1 لتر', 'كارفور المعادي', 450, 29250.0],
        ['6221001998877', 'سمن أديكو "خاص، فاخر"', 'فتح الله سموحة', 320, 30400.0],
      ];

      final csv = ExcelExportService.generateCsv(headers: headers, rows: rows);

      // Verify UTF-8 BOM is at the start (crucial for Microsoft Excel Arabic display)
      expect(csv.startsWith('\uFEFF'), isTrue);

      // Verify header presence
      expect(csv.contains('"الباركود","اسم الصنف","السلسلة","الكمية","الإيراد"'), isTrue);

      // Verify row data presence and escaping of quotes/commas
      expect(csv.contains('"6221001122334"'), isTrue);
      expect(csv.contains('"زيت أديكو ممتاز 1 لتر"'), isTrue);
      expect(csv.contains('"سمن أديكو ""خاص، فاخر"""'), isTrue);
    });

    test('generatePrintableReport generates valid RTL HTML with Cairo font and tables', () {
      final headers = ['الباركود', 'اسم الصنف', 'الفرع', 'صافي الإيراد'];
      final rows = [
        ['6221001122334', 'زيت أديكو ممتاز 1 لتر', 'كارفور المعادي', '29,250 ج.م'],
      ];

      final html = ExcelExportService.generatePrintableReport(
        title: 'تقرير حركة مبيعات التجزئة',
        headers: headers,
        rows: rows,
        metadata: {
          'الشركة': 'أديكو (Adeco)',
          'الفترة': 'أكتوبر 2026',
        },
      );

      // Verify HTML boilerplate and RTL orientation
      expect(html.contains('<!DOCTYPE html>'), isTrue);
      expect(html.contains('dir="rtl"'), isTrue);
      expect(html.contains('lang="ar"'), isTrue);

      // Verify Cairo font inclusion
      expect(html.contains('family=Cairo'), isTrue);

      // Verify title and metadata
      expect(html.contains('تقرير حركة مبيعات التجزئة'), isTrue);
      expect(html.contains('أديكو (Adeco)'), isTrue);
      expect(html.contains('أكتوبر 2026'), isTrue);

      // Verify table headers and cells
      expect(html.contains('<th>الباركود</th>'), isTrue);
      expect(html.contains('<th>اسم الصنف</th>'), isTrue);
      expect(html.contains('<td>زيت أديكو ممتاز 1 لتر</td>'), isTrue);
      expect(html.contains('<td>29,250 ج.م</td>'), isTrue);

      // Verify print stylesheet
      expect(html.contains('@media print'), isTrue);
    });

    test('downloadCsv and downloadHtml record filename, content, and MIME type', () {
      ExcelExportService.resetLastDownloaded();
      expect(ExcelExportService.lastDownloadedFilename, isNull);

      const csvContent = '\uFEFF"الباركود","الكمية"\r\n"6221155001234","120"\r\n';
      ExcelExportService.downloadCsv('sellout_test.csv', csvContent);

      expect(ExcelExportService.lastDownloadedFilename, equals('sellout_test.csv'));
      expect(ExcelExportService.lastDownloadedContent, equals(csvContent));
      expect(ExcelExportService.lastDownloadedMimeType, equals('text/csv;charset=utf-8'));

      const htmlContent = '<!DOCTYPE html><html dir="rtl" lang="ar"><body>تقرير</body></html>';
      ExcelExportService.downloadHtml('sellout_report.html', htmlContent);

      expect(ExcelExportService.lastDownloadedFilename, equals('sellout_report.html'));
      expect(ExcelExportService.lastDownloadedContent, equals(htmlContent));
      expect(ExcelExportService.lastDownloadedMimeType, equals('text/html;charset=utf-8'));
    });
  });
}
