import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tashil_web/core/network/api_client.dart';
import 'package:tashil_web/core/widgets/archive_actions_group.dart';

// Hotfix for prod 2477d63: the web app sent tenant_id=tenant-adeco next to a token carrying "adeco",
// and the backend refused every Sell-In upload with 403.
void main() {
  test('uploadSellInFile sends no tenant_id in the query or the form', () async {
    final seen = <http.Request>[];
    await http.runWithClient(() async {
      final api = ApiClient(tenantId: 'tenant-adeco', allowMockFallback: false);
      await api.uploadSellInFile(filename: 'si.xlsx', fileBytes: const [1, 2, 3], chain: 'qa_test');
    }, () => MockClient((req) async {
          seen.add(req);
          return http.Response(jsonEncode({'batch_id': 'b1', 'filename': 'si.xlsx'}), 200,
              headers: {'content-type': 'application/json'});
        }));
    expect(seen, hasLength(1));
    expect(seen.single.url.queryParameters.containsKey('tenant_id'), isFalse);
    expect(seen.single.url.queryParameters['chain'], 'qa_test');
    expect(utf8.decode(seen.single.bodyBytes, allowMalformed: true).contains('name="tenant_id"'), isFalse);
  });

  test('a 403 upload shows the clear Arabic reason, not a generic job failure', () async {
    Object? caught;
    await http.runWithClient(() async {
      final api = ApiClient(tenantId: 'tenant-adeco', allowMockFallback: true);
      try {
        await api.uploadSellInFile(filename: 'si.xlsx', fileBytes: const [1], chain: 'qa_test', replaceArchiveId: 'arch_1');
      } catch (e) {
        caught = e;
      }
    }, () => MockClient((req) async => http.Response(jsonEncode({'error': 'forbidden'}), 403)));
    expect(caught, isA<UploadRejectedException>());
    expect((caught as UploadRejectedException).message, uploadForbiddenMessage);
    expect(() => throwIfUploadRefused(403, '{}', 'x'), throwsA(isA<UploadRejectedException>()));
  });

  testWidgets('ArchiveActionsGroup hides Edit when showEdit is false', (tester) async {
    Future<void> pump(bool showEdit) => tester.pumpWidget(MaterialApp(
          home: Scaffold(
            body: ArchiveActionsGroup(showEdit: showEdit, onEdit: () {}, onDownload: () {}, onDelete: () {}),
          ),
        ));
    await pump(true);
    expect(find.text('Edit'), findsOneWidget);
    await pump(false);
    expect(find.text('Edit'), findsNothing);
    expect(find.text('Download'), findsOneWidget);
    expect(find.text('Delete'), findsOneWidget);
  });
}
