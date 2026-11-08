import 'package:flutter_test/flutter_test.dart';
import 'package:tashil_web/core/network/api_client.dart';
import 'package:tashil_web/features/sell_out_analytics/domain/sell_out_upload_flow.dart';

IngestionResultModel _preview({
  String batchId = 'batch-1',
  int validRows = 2,
  String mappingSource = 'deterministic',
}) {
  return IngestionResultModel(
    batchId: batchId,
    archiveId: '',
    filename: 'qa.xlsx',
    retailerDetected: 'fathalla',
    totalRows: validRows,
    validRows: validRows,
    anomalyRows: 0,
    totalRevenue: 200,
    totalQuantity: validRows,
    confidenceScore: 0.9,
    anomalies: const [],
    mappingSource: mappingSource,
    aiModelUsed: '',
    isStaged: true,
    isCommitted: false,
  );
}

IngestionResultModel _committed({String archiveId = 'new-arc'}) {
  return IngestionResultModel(
    batchId: 'batch-1',
    archiveId: archiveId,
    filename: 'qa.xlsx',
    retailerDetected: 'fathalla',
    totalRows: 2,
    validRows: 2,
    anomalyRows: 0,
    totalRevenue: 200,
    totalQuantity: 2,
    confidenceScore: 0.9,
    anomalies: const [],
    mappingSource: 'deterministic',
    isStaged: false,
    isCommitted: true,
  );
}

void main() {
  const oldId = 'old-archive-42';

  test('Replace→cancel preserves old archive (never deletes)', () async {
    final deleted = <String>[];
    var discarded = false;
    var commits = 0;

    final result = await runSellOutUploadFlow(
      filename: 'qa.xlsx',
      bytes: const [1, 2, 3],
      replaceArchiveId: oldId,
      deps: SellOutUploadFlowDeps(
        upload: ({
          required filename,
          required bytes,
          targetChain,
          periodDate,
          required dryRun,
        }) async {
          expect(dryRun, isTrue);
          expect(deleted, isEmpty, reason: 'must not delete before preview');
          return _preview();
        },
        commit: ({required batchId, targetChain, periodDate}) async {
          commits += 1;
          return _committed();
        },
        discard: ({required batchId}) async {
          discarded = true;
        },
        deleteArchive: (id) async {
          deleted.add(id);
          return true;
        },
        confirm: (_) async => false,
      ),
    );

    expect(result.status, SellOutUploadFlowStatus.cancelled);
    expect(result.replacedArchivePreserved, isTrue);
    expect(result.replacedArchiveDeleted, isFalse);
    expect(deleted, isEmpty);
    expect(discarded, isTrue);
    expect(commits, 0);
  });

  test('Replace→parse/preview error preserves old archive', () async {
    final deleted = <String>[];

    final result = await runSellOutUploadFlow(
      filename: 'bad.xlsx',
      bytes: const [9],
      replaceArchiveId: oldId,
      deps: SellOutUploadFlowDeps(
        upload: ({
          required filename,
          required bytes,
          targetChain,
          periodDate,
          required dryRun,
        }) async {
          throw Exception('parse failed');
        },
        commit: ({required batchId, targetChain, periodDate}) async =>
            _committed(),
        discard: ({required batchId}) async {},
        deleteArchive: (id) async {
          deleted.add(id);
          return true;
        },
        confirm: (_) async => true,
      ),
    );

    expect(result.status, SellOutUploadFlowStatus.previewFailed);
    expect(result.replacedArchivePreserved, isTrue);
    expect(deleted, isEmpty);
  });

  test('Replace→commit failure preserves old archive', () async {
    final deleted = <String>[];

    final result = await runSellOutUploadFlow(
      filename: 'qa.xlsx',
      bytes: const [1],
      replaceArchiveId: oldId,
      deps: SellOutUploadFlowDeps(
        upload: ({
          required filename,
          required bytes,
          targetChain,
          periodDate,
          required dryRun,
        }) async =>
            _preview(),
        commit: ({required batchId, targetChain, periodDate}) async {
          throw Exception('commit failed');
        },
        discard: ({required batchId}) async {},
        deleteArchive: (id) async {
          deleted.add(id);
          return true;
        },
        confirm: (_) async => true,
      ),
    );

    expect(result.status, SellOutUploadFlowStatus.commitFailed);
    expect(result.replacedArchivePreserved, isTrue);
    expect(result.replacedArchiveDeleted, isFalse);
    expect(deleted, isEmpty);
  });

  test('Replace→confirm deletes old archive only after successful commit',
      () async {
    final deleted = <String>[];
    var commitDone = false;

    final result = await runSellOutUploadFlow(
      filename: 'qa.xlsx',
      bytes: const [1],
      replaceArchiveId: oldId,
      deps: SellOutUploadFlowDeps(
        upload: ({
          required filename,
          required bytes,
          targetChain,
          periodDate,
          required dryRun,
        }) async {
          expect(deleted, isEmpty);
          return _preview();
        },
        commit: ({required batchId, targetChain, periodDate}) async {
          expect(deleted, isEmpty, reason: 'delete only after commit returns');
          commitDone = true;
          return _committed();
        },
        discard: ({required batchId}) async {},
        deleteArchive: (id) async {
          expect(commitDone, isTrue);
          deleted.add(id);
          return true;
        },
        confirm: (_) async => true,
      ),
    );

    expect(result.status, SellOutUploadFlowStatus.committed);
    expect(result.replacedArchiveDeleted, isTrue);
    expect(result.replacedArchivePreserved, isFalse);
    expect(deleted, [oldId]);
  });

  test('new upload (no replace) never calls deleteArchive', () async {
    var deletes = 0;
    final result = await runSellOutUploadFlow(
      filename: 'qa.xlsx',
      bytes: const [1],
      deps: SellOutUploadFlowDeps(
        upload: ({
          required filename,
          required bytes,
          targetChain,
          periodDate,
          required dryRun,
        }) async =>
            _preview(),
        commit: ({required batchId, targetChain, periodDate}) async =>
            _committed(),
        discard: ({required batchId}) async {},
        deleteArchive: (_) async {
          deletes += 1;
          return true;
        },
        confirm: (_) async => true,
      ),
    );
    expect(result.status, SellOutUploadFlowStatus.committed);
    expect(deletes, 0);
  });
}
