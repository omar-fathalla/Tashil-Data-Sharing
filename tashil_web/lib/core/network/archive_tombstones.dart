/// Helpers for client-side archive tombstones used by [ApiClient].
///
/// Failed deletes (403/502/…) must NOT add tombstones. Successful server list
/// responses should reconcile away stale tombstones so files the backend still
/// has reappear after earlier optimistic/failed deletes.

/// True when a delete HTTP status means the backend confirmed removal.
bool archiveDeleteHttpSucceeded(int statusCode) =>
    statusCode == 200 || statusCode == 204;

/// Removes server-listed ids/names from local tombstone sets (in place).
/// Returns how many tombstone entries were cleared.
int reconcileArchiveTombstones({
  required Iterable<String> serverIds,
  required Iterable<String> serverFileNamesLower,
  required Set<String> deletedIds,
  required Set<String> deletedFileNamesLower,
}) {
  var cleared = 0;
  for (final id in serverIds) {
    if (id.isNotEmpty && deletedIds.remove(id)) cleared++;
  }
  for (final name in serverFileNamesLower) {
    final n = name.trim().toLowerCase();
    if (n.isNotEmpty && deletedFileNamesLower.remove(n)) cleared++;
  }
  return cleared;
}

/// Filters archive files by tombstone sets (after optional reconcile).
List<T> filterArchiveFilesByTombstones<T>({
  required List<T> files,
  required String Function(T) idOf,
  required String Function(T) fileNameOf,
  required Set<String> deletedIds,
  required Set<String> deletedFileNamesLower,
}) {
  return files.where((f) {
    final id = idOf(f);
    if (id.isNotEmpty && deletedIds.contains(id)) return false;
    final name = fileNameOf(f).trim().toLowerCase();
    if (name.isNotEmpty && deletedFileNamesLower.contains(name)) return false;
    return true;
  }).toList();
}
