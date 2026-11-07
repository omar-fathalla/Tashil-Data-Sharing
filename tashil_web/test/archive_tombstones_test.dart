import 'package:flutter_test/flutter_test.dart';
import 'package:tashil_web/core/network/api_client.dart';

void main() {
  group('archive delete HTTP success gate', () {
    test('only 200/204 apply local tombstones (403/502 leave list intact)', () {
      expect(archiveDeleteHttpSucceeded(200), isTrue);
      expect(archiveDeleteHttpSucceeded(204), isTrue);
      expect(archiveDeleteHttpSucceeded(403), isFalse);
      expect(archiveDeleteHttpSucceeded(502), isFalse);
      expect(archiveDeleteHttpSucceeded(500), isFalse);
      expect(archiveDeleteHttpSucceeded(404), isFalse);
    });
  });

  group('tombstone reconcile + filter', () {
    test('403/502 path: empty new tombstones keeps server files listed', () {
      final server = [
        _f('arch_1', '2026 out.xlsx'),
        _f('arch_2', '2025 out.xlsx'),
        _f('arch_3', '15_sellout_form_vs_sheet.xlsx'),
      ];
      final deletedIds = <String>{};
      final deletedNames = <String>{};
      // Simulate failed deletes: do NOT add tombstones when status is 403/502.
      for (final code in [403, 502]) {
        expect(archiveDeleteHttpSucceeded(code), isFalse);
      }
      final visible = filterArchiveFilesByTombstones(
        files: server,
        idOf: (f) => f.id,
        fileNameOf: (f) => f.fileName,
        deletedIds: deletedIds,
        deletedFileNamesLower: deletedNames,
      );
      expect(visible, hasLength(3));
    });

    test('stale tombstones are cleared when server still lists the files', () {
      final server = [
        _f('arch_1', '2026 out.xlsx'),
        _f('arch_2', '2025 out.xlsx'),
      ];
      final deletedIds = <String>{'arch_1', 'arch_gone'};
      final deletedNames = <String>{'2026 out.xlsx', 'ghost.xlsx'};
      final cleared = reconcileArchiveTombstones(
        serverIds: server.map((f) => f.id),
        serverFileNamesLower: server.map((f) => f.fileName.toLowerCase()),
        deletedIds: deletedIds,
        deletedFileNamesLower: deletedNames,
      );
      expect(cleared, greaterThanOrEqualTo(2));
      expect(deletedIds.contains('arch_1'), isFalse);
      expect(deletedNames.contains('2026 out.xlsx'), isFalse);
      // Unrelated tombstones remain until their own reconcile.
      expect(deletedIds.contains('arch_gone'), isTrue);
      expect(deletedNames.contains('ghost.xlsx'), isTrue);

      final visible = filterArchiveFilesByTombstones(
        files: server,
        idOf: (f) => f.id,
        fileNameOf: (f) => f.fileName,
        deletedIds: deletedIds,
        deletedFileNamesLower: deletedNames,
      );
      expect(visible, hasLength(2));
    });
  });

  group('ArchiveDeleteException surfaces 403/502', () {
    test('403 body', () {
      final ex = ArchiveDeleteException.fromResponse(
        403,
        '{"error":"Forbidden: your role cannot perform this action"}',
      );
      expect(ex.statusCode, 403);
      expect(ex.message.toLowerCase(), contains('forbidden'));
    });

    test('502 analytics failure', () {
      final ex = ArchiveDeleteException.fromResponse(
        502,
        '{"error":"archive_delete_analytics_failed","message":"bigquery: failed"}',
      );
      expect(ex.statusCode, 502);
      expect(ex.errorCode, 'archive_delete_analytics_failed');
      expect(ex.message, contains('bigquery'));
    });
  });
}

ArchivedExcelFileModel _f(String id, String name) => ArchivedExcelFileModel(
      id: id,
      batchId: 'b',
      fileType: 'sell_out',
      tenantId: 'tenant-adeco',
      fileName: name,
      contentType: 'application/vnd.ms-excel',
      fileSizeBytes: 1,
      retailChain: 'fathalla',
      chainNameAr: 'فتح الله',
      chainNameEn: 'Fathalla',
      targetYear: '2026',
      targetMonth: '01',
      rowsIngested: 1,
      branchesCount: 1,
      totalRevenue: 1,
      uploadedAt: '2026-01-01T00:00:00Z',
    );
