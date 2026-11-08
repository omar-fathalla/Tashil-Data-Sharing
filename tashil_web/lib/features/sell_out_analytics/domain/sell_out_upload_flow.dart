import '../../../core/network/api_client.dart';

/// Outcome of a Sell-Out preview → confirm → commit flow.
enum SellOutUploadFlowStatus {
  cancelled,
  previewFailed,
  commitFailed,
  committed,
}

class SellOutUploadFlowResult {
  final SellOutUploadFlowStatus status;
  final IngestionResultModel? preview;
  final IngestionResultModel? committed;
  final Object? error;

  /// True when [replaceArchiveId] was never deleted (or delete was not attempted).
  final bool replacedArchivePreserved;

  /// True only when replace delete ran after a successful commit.
  final bool replacedArchiveDeleted;

  const SellOutUploadFlowResult({
    required this.status,
    this.preview,
    this.committed,
    this.error,
    required this.replacedArchivePreserved,
    this.replacedArchiveDeleted = false,
  });
}

/// Dependencies for [runSellOutUploadFlow] (injected for unit tests).
class SellOutUploadFlowDeps {
  final Future<IngestionResultModel> Function({
    required String filename,
    required List<int> bytes,
    String? targetChain,
    String? periodDate,
    required bool dryRun,
  }) upload;

  final Future<IngestionResultModel> Function({
    required String batchId,
    String? targetChain,
    String? periodDate,
  }) commit;

  final Future<void> Function({required String batchId}) discard;

  final Future<bool> Function(String archiveId) deleteArchive;

  /// Returns true to commit, false/null to cancel.
  final Future<bool?> Function(IngestionResultModel preview) confirm;

  const SellOutUploadFlowDeps({
    required this.upload,
    required this.commit,
    required this.discard,
    required this.deleteArchive,
    required this.confirm,
  });
}

/// Preview (dry-run) → user confirm → commit.
///
/// **Replace safety:** [replaceArchiveId] is deleted only after a successful
/// commit. Cancel, preview/parse failure, and commit failure leave the old
/// archive (and its BigQuery rows) intact.
Future<SellOutUploadFlowResult> runSellOutUploadFlow({
  required SellOutUploadFlowDeps deps,
  required String filename,
  required List<int> bytes,
  String? targetChain,
  String? periodDate,
  String? replaceArchiveId,
}) async {
  final replacing = replaceArchiveId != null && replaceArchiveId.isNotEmpty;

  late final IngestionResultModel preview;
  try {
    preview = await deps.upload(
      filename: filename,
      bytes: bytes,
      targetChain: targetChain,
      periodDate: periodDate,
      dryRun: true,
    );
  } catch (e) {
    return SellOutUploadFlowResult(
      status: SellOutUploadFlowStatus.previewFailed,
      error: e,
      replacedArchivePreserved: true,
    );
  }

  if (!preview.isStaged || preview.isCommitted) {
    // Unexpected non-staged success: still never delete old until explicit commit path.
    return SellOutUploadFlowResult(
      status: SellOutUploadFlowStatus.committed,
      preview: preview,
      committed: preview,
      replacedArchivePreserved: true,
    );
  }

  final shouldCommit = await deps.confirm(preview) ?? false;
  if (!shouldCommit) {
    if (preview.batchId.isNotEmpty) {
      try {
        await deps.discard(batchId: preview.batchId);
      } catch (_) {}
    }
    return SellOutUploadFlowResult(
      status: SellOutUploadFlowStatus.cancelled,
      preview: preview,
      replacedArchivePreserved: true,
    );
  }

  try {
    final committed = await deps.commit(
      batchId: preview.batchId,
      targetChain: targetChain,
      periodDate: periodDate,
    );

    var deleted = false;
    if (replacing) {
      try {
        deleted = await deps.deleteArchive(replaceArchiveId);
      } catch (_) {
        deleted = false;
      }
    }

    return SellOutUploadFlowResult(
      status: SellOutUploadFlowStatus.committed,
      preview: preview,
      committed: committed,
      replacedArchivePreserved: !deleted,
      replacedArchiveDeleted: deleted,
    );
  } catch (e) {
    return SellOutUploadFlowResult(
      status: SellOutUploadFlowStatus.commitFailed,
      preview: preview,
      error: e,
      replacedArchivePreserved: true,
    );
  }
}
