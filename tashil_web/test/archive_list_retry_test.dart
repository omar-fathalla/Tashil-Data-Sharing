// After a deploy, Cloud Run answered the uploaded-files list with a 429 (no
// CORS headers → browser "CORS / net::ERR_FAILED") while the single instance
// was busy, and the screen showed "no files". The client must retry transient
// failures with backoff and, if they persist, show an error with retry.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tashil_web/core/network/api_client.dart';
import 'package:tashil_web/core/theme/app_theme.dart';
import 'package:tashil_web/features/sell_out_analytics/presentation/screens/sell_in_explorer_screen.dart';
import 'package:tashil_web/features/sell_out_analytics/presentation/screens/sell_out_explorer_screen.dart';

final _ok = jsonEncode({
  'tenant_id': 'tenant-adeco',
  'total_count': 1,
  'files': [
    {
      'id': 'arch_1',
      'file_type': 'sell_out',
      'file_name': 'out26.xlsx',
      'retail_chain': 'fathalla',
      'rows_ingested': 81294,
      'total_units': 1532854,
      'uploaded_at': '2026-11-13T10:00:00Z',
    }
  ],
});

Future<UploadedFilesArchiveResponse> _list(
    String tenant, List<Object> script, List<int> calls) {
  var i = 0;
  return http.runWithClient(() {
    final api = ApiClient(tenantId: tenant, allowMockFallback: false);
    return api.getUploadedFilesArchive(fileType: 'sell_out');
  },
      () => MockClient((req) async {
            calls.add(i);
            final step = script[i < script.length ? i : script.length - 1];
            i++;
            if (step is int) {
              return http.Response(step == 200 ? _ok : 'busy', step);
            }
            throw step;
          }));
}

class _FailingArchiveApi extends ApiClient {
  _FailingArchiveApi() : super(allowMockFallback: false);
  @override
  Future<UploadedFilesArchiveResponse> getUploadedFilesArchive({
    String? chain,
    String? year,
    String? searchQuery,
    String? targetTenant,
    String? fileType,
    bool forceRefresh = false,
  }) async =>
      throw ArchiveLoadException('HTTP 429');
}

void main() {
  setUp(() => ApiClient.archiveRetryDelays = const [
        Duration.zero,
        Duration.zero,
        Duration.zero
      ]);

  test('429 then 200: retried, files returned', () async {
    final calls = <int>[];
    final res = await _list('tenant-retry-a', [429, 200], calls);
    expect(calls.length, 2);
    expect(res.files.single.totalUnits, 1532854);
  });

  test('network/CORS error then 503 then 200: retried', () async {
    final calls = <int>[];
    final res = await _list('tenant-retry-b',
        [http.ClientException('XMLHttpRequest error.'), 503, 200], calls);
    expect(calls.length, 3);
    expect(res.files, hasLength(1));
  });

  test('non-transient 401 is not retried', () async {
    final calls = <int>[];
    await expectLater(_list('tenant-retry-c', [401, 200], calls),
        throwsA(isA<ArchiveLoadException>()));
    expect(calls.length, 1);
  });

  test('persistent 429: bounded attempts, then ArchiveLoadException', () async {
    final calls = <int>[];
    await expectLater(_list('tenant-retry-d', [429], calls),
        throwsA(isA<ArchiveLoadException>()));
    expect(calls.length, 4); // 1 + 3 retries
  });

  for (final sellIn in [false, true]) {
    testWidgets(
        '${sellIn ? 'Sell-In' : 'Sell-Out'} files tab: failed load shows error + retry, not "no files"',
        (tester) async {
      tester.view.physicalSize = const Size(1600, 3000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final api = _FailingArchiveApi();
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light(),
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(
              body: sellIn
                  ? SellInExplorerScreen(apiClient: api)
                  : SellOutExplorerScreen(apiClient: api)),
        ),
      ));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining(RegExp('^الملفات المرفوعة')).first);
      await tester.pumpAndSettle();
      final kind = sellIn ? 'sell_in' : 'sell_out';
      expect(
          find.byKey(ValueKey('${kind}_archive_load_error')), findsOneWidget);
      expect(find.text('لا توجد ملفات مرفوعة بعد.'), findsNothing);
      expect(find.text('إعادة المحاولة'), findsOneWidget);
    });
  }
}
