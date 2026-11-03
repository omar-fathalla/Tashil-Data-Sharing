import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tashil_web/core/network/api_client.dart';
import 'package:tashil_web/core/theme/app_theme.dart';
import 'package:tashil_web/core/utils/web_file_helper.dart';
import 'package:tashil_web/core/widgets/archive_actions_group.dart';
import 'package:tashil_web/features/sell_out_analytics/presentation/screens/sell_out_explorer_screen.dart';

const _server403 = 'مسموح للمشرف العام بس.';

TenantUserModel _user(String role) => TenantUserModel(
      userId: 'u-$role',
      tenantId: 'adeco',
      email: '$role@example.com',
      fullName: role,
      role: role,
    );

/// Every DELETE is refused with 403; other calls fail (screen uses mock data). Uploads are recorded.
MockClient _refusingServer(List<String> uploads, List<String> deletes) => MockClient((req) async {
      if (req.method == 'DELETE') {
        deletes.add(req.url.path);
        return http.Response(jsonEncode({'error': 'forbidden', 'message': _server403}), 403,
            headers: {'content-type': 'application/json; charset=utf-8'});
      }
      if (req.method == 'POST' && req.url.path.contains('upload')) uploads.add(req.url.path);
      return http.Response('down', 500);
    });

Future<void> _pumpUploadedFilesTab(WidgetTester tester, ApiClient api) async {
  tester.view.physicalSize = const Size(2400, 1400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  await tester.pumpWidget(MaterialApp(
    theme: AppTheme.light(),
    home: Scaffold(body: SellOutExplorerScreen(apiClient: api)),
  ));
  await tester.pumpAndSettle();
  await tester.tap(find.textContaining('Uploaded Files'));
  await tester.pumpAndSettle();
}

void main() {
  group('deleteArchivedFile (M1)', () {
    test('403 returns false, keeps the local list, and exposes the server message', () async {
      final deletes = <String>[];
      await http.runWithClient(() async {
        final api = ApiClient(tenantId: 'tenant-adeco', allowMockFallback: true);
        final before = (await api.getUploadedFilesArchive()).files.map((f) => f.id).toList();
        expect(before, isNotEmpty);
        final ok = await api.deleteArchivedFile(before.first, fileName: 'x.xlsx');
        expect(ok, isFalse);
        expect(api.lastArchiveDeleteError, _server403);
        final after = (await api.getUploadedFilesArchive()).files.map((f) => f.id).toList();
        expect(after, before);
      }, () => _refusingServer(<String>[], deletes));
      expect(deletes, hasLength(1));
    });

    test('403 without an Arabic server message falls back to the Arabic default', () {
      expect(archiveDeleteRefusedMessage(403, '{"error":"forbidden"}'), contains('للمشرف العام'));
      expect(archiveDeleteRefusedMessage(403, 'not json'), contains('للمشرف العام'));
    });
  });

  group('upload 403 message (L3)', () {
    test('prefers the server Arabic message, else uploadForbiddenMessage', () {
      expect(
        () => throwIfUploadRefused(403, jsonEncode({'message': _server403}), 'fallback'),
        throwsA(isA<UploadRejectedException>().having((e) => e.message, 'message', _server403)),
      );
      expect(
        () => throwIfUploadRefused(403, '{"error":"forbidden"}', 'fallback'),
        throwsA(isA<UploadRejectedException>().having((e) => e.message, 'message', uploadForbiddenMessage)),
      );
    });
  });

  group('Sell-Out archive actions (M1)', () {
    testWidgets('vendor_admin sees no Edit/Delete on Sell-Out archive rows', (tester) async {
      final api = ApiClient(tenantId: 'tenant-adeco')..currentUser = _user('vendor_admin');
      await _pumpUploadedFilesTab(tester, api);
      final groups = tester.widgetList<ArchiveActionsGroup>(find.byType(ArchiveActionsGroup)).toList();
      expect(groups, isNotEmpty);
      for (final g in groups) {
        expect(g.showEdit, isFalse);
        expect(g.showDelete, isFalse);
      }
      expect(find.text('Delete'), findsNothing);
      expect(find.text('Edit'), findsNothing);
      expect(find.text('Download'), findsWidgets);
    });

    testWidgets('refused delete shows no success and keeps the row', (tester) async {
      final uploads = <String>[];
      final deletes = <String>[];
      await http.runWithClient(() async {
        final api = ApiClient(tenantId: 'tenant-adeco')..currentUser = _user('super_admin');
        await _pumpUploadedFilesTab(tester, api);
        final rowsBefore = find.byType(ArchiveActionsGroup).evaluate().length;
        await tester.ensureVisible(find.text('Delete').first);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Delete').first);
        await tester.pumpAndSettle();
        final confirm = find.descendant(of: find.byType(AlertDialog), matching: find.byType(FilledButton));
        await tester.tap(confirm.last);
        await tester.pumpAndSettle();
        expect(deletes, hasLength(1));
        expect(find.textContaining('تم حذف'), findsNothing);
        expect(find.textContaining(_server403), findsOneWidget);
        expect(find.byType(ArchiveActionsGroup).evaluate().length, rowsBefore);
      }, () => _refusingServer(uploads, deletes));
    });

    testWidgets('refused delete aborts Replace: no upload, no success', (tester) async {
      final uploads = <String>[];
      final deletes = <String>[];
      await http.runWithClient(() async {
        final api = ApiClient(tenantId: 'tenant-adeco')..currentUser = _user('super_admin');
        await _pumpUploadedFilesTab(tester, api);
        WebFileHelper.nextMockPickedFile =
            PickedFileData(name: 'replace.xlsx', bytes: Uint8List.fromList([1, 2, 3]));
        await tester.ensureVisible(find.text('Edit').first);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Edit').first);
        await tester.pumpAndSettle();
        expect(deletes, hasLength(1));
        expect(uploads, isEmpty);
        expect(find.textContaining('تم استبدال'), findsNothing);
        expect(find.textContaining(_server403), findsOneWidget);
      }, () => _refusingServer(uploads, deletes));
      WebFileHelper.nextMockPickedFile = null;
    });
  });

  group('ArchiveActionsGroup (L1)', () {
    testWidgets('showDelete:false hides Delete (Sell-In vendor_admin)', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ArchiveActionsGroup(
            showEdit: false,
            showDelete: false,
            isEditing: false,
            isDeleting: false,
            onEdit: () {},
            onDownload: () {},
            onDelete: () {},
          ),
        ),
      ));
      expect(find.text('Delete'), findsNothing);
      expect(find.text('Edit'), findsNothing);
      expect(find.text('Download'), findsOneWidget);
    });
  });
}
