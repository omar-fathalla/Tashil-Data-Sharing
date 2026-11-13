// The uploaded-files tables showed the stored row count twice: Sell-Out
// "الوحدات المباعة" repeated rows_ingested (المعاملات), and Sell-In "Cases"
// fell back to rows_ingested when total_cases was 0. Each column must show
// its own backend field.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tashil_web/core/network/api_client.dart';
import 'package:tashil_web/core/theme/app_theme.dart';
import 'package:tashil_web/core/utils/currency_formatter.dart';
import 'package:tashil_web/features/sell_out_analytics/presentation/screens/sell_in_explorer_screen.dart';
import 'package:tashil_web/features/sell_out_analytics/presentation/screens/sell_out_explorer_screen.dart';

class _ArchiveApi extends ApiClient {
  _ArchiveApi(this.byType);
  final Map<String, List<Map<String, dynamic>>> byType;

  @override
  Future<UploadedFilesArchiveResponse> getUploadedFilesArchive({
    String? chain,
    String? year,
    String? searchQuery,
    String? targetTenant,
    String? fileType,
  }) async {
    final files = (byType[fileType] ?? const [])
        .map(ArchivedExcelFileModel.fromJson)
        .toList();
    return UploadedFilesArchiveResponse(
        tenantId: 'tenant-adeco',
        totalCount: files.length,
        chainCounts: const {},
        files: files);
  }
}

Map<String, dynamic> _file(
        String id, String type, Map<String, dynamic> extra) =>
    {
      'id': id,
      'tenant_id': 'tenant-adeco',
      'file_type': type,
      'file_name': '$id.xlsx',
      'retail_chain': 'fathalla',
      'target_year': '2026',
      'target_month': '01',
      'branches_count': 3,
      'total_revenue': 1000.0,
      'uploaded_at': '2026-11-13T10:00:00Z',
      ...extra,
    };

String _text(WidgetTester t, String key) =>
    t.widget<Text>(find.byKey(ValueKey(key))).data!;

Future<void> _pump(WidgetTester tester, Widget screen) async {
  tester.view.physicalSize = const Size(1600, 3000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    theme: AppTheme.light(),
    home: Directionality(
        textDirection: TextDirection.rtl, child: Scaffold(body: screen)),
  ));
  await tester.pumpAndSettle();
}

void main() {
  test('total_units parses; missing stays null (no rows fallback)', () {
    final a = ArchivedExcelFileModel.fromJson(_file(
        'a', 'sell_out', {'rows_ingested': 81294, 'total_units': 1532854}));
    expect(a.rowsIngested, 81294);
    expect(a.totalUnits, 1532854);
    final b = ArchivedExcelFileModel.fromJson(
        _file('b', 'sell_out', {'rows_ingested': 10}));
    expect(b.totalUnits, isNull);
  });

  testWidgets('Sell-Out files: المعاملات = rows, الوحدات المباعة = total_units',
      (tester) async {
    final api = _ArchiveApi({
      'sell_out': [
        _file('out_a', 'sell_out',
            {'rows_ingested': 81294, 'total_units': 1532854}),
        _file('out_b', 'sell_out', {'rows_ingested': 500}),
      ],
    });
    await _pump(tester, SellOutExplorerScreen(apiClient: api));
    await tester.tap(find.textContaining(RegExp('^الملفات المرفوعة')).first);
    await tester.pumpAndSettle();
    expect(_text(tester, 'file_rows_out_a'),
        CurrencyFormatter.formatNumber(81294));
    expect(_text(tester, 'file_units_out_a'),
        CurrencyFormatter.formatNumber(1532854));
    expect(
        _text(tester, 'file_rows_out_b'), CurrencyFormatter.formatNumber(500));
    expect(_text(tester, 'file_units_out_b'), '—');
  });

  testWidgets('Sell-In files: Transactions = rows, Cases = total_cases',
      (tester) async {
    final api = _ArchiveApi({
      'sell_in': [
        _file('in_a', 'sell_in',
            {'rows_ingested': 40927, 'total_cases': 609430.0}),
        _file('in_b', 'sell_in', {'rows_ingested': 7826, 'total_cases': 0.0}),
      ],
    });
    await _pump(tester, SellInExplorerScreen(apiClient: api));
    await tester.tap(find.textContaining(RegExp('^الملفات المرفوعة')).first);
    await tester.pumpAndSettle();
    expect(_text(tester, 'sellin_file_rows_in_a'),
        CurrencyFormatter.formatNumber(40927));
    expect(_text(tester, 'sellin_file_cases_in_a'),
        CurrencyFormatter.formatNumber(609430));
    expect(_text(tester, 'sellin_file_cases_in_b'),
        CurrencyFormatter.formatNumber(0));
  });
}
