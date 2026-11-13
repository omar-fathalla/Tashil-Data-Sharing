/// Display-only helper: strips a leading word-prefix shared by every name
/// in a dataset, cut at a separator (`-`, `–`, `—`, `:`), including the
/// separator and surrounding whitespace.
///
/// This never changes stored data, upload parsing, dedup keys, or matching.
/// Callers must apply it only when rendering a label.
///
/// Rules:
/// - Fewer than two names, or no common prefix that ends at a separator:
///   names are returned unchanged.
/// - Never returns an empty name. If stripping would leave any name empty,
///   the original names are returned unchanged.
library;

const _separators = {'-', '–', '—', ':'};

/// Returns [names] with a shared leading prefix removed, or [names] as-is.
List<String> stripSharedLeadingPrefix(List<String> names) {
  if (names.length < 2) return List<String>.from(names);

  final trimmed = [for (final n in names) n.trim()];
  final prefix = _commonPrefix(trimmed);
  if (prefix == null || prefix.isEmpty) return List<String>.from(names);

  final cut = _prefixEndingAtSeparator(prefix);
  if (cut == null || cut.isEmpty) return List<String>.from(names);

  final out = <String>[];
  for (final t in trimmed) {
    if (!t.startsWith(cut)) return List<String>.from(names);
    final rest = t.substring(cut.length).trim();
    if (rest.isEmpty) return List<String>.from(names);
    out.add(rest);
  }
  return out;
}

/// Map of original name → display name for a dataset.
Map<String, String> displayNamesWithoutSharedPrefix(Iterable<String> names) {
  final list = names.toList();
  final stripped = stripSharedLeadingPrefix(list);
  return {
    for (var i = 0; i < list.length; i++) list[i]: stripped[i],
  };
}

/// Display form of [name] given the full [dataset] of names.
String displayNameWithoutSharedPrefix(String name, Iterable<String> dataset) {
  return displayNamesWithoutSharedPrefix(dataset)[name] ?? name;
}

String? _commonPrefix(List<String> items) {
  if (items.isEmpty) return null;
  final first = items.first.runes.toList();
  var length = first.length;
  for (final item in items.skip(1)) {
    final runes = item.runes.toList();
    var i = 0;
    final n = length < runes.length ? length : runes.length;
    while (i < n && first[i] == runes[i]) {
      i++;
    }
    length = i;
    if (length == 0) return null;
  }
  return String.fromCharCodes(first.take(length));
}

/// The longest prefix of [commonPrefix] that ends at a separator, plus any
/// whitespace that follows the separator and is still inside [commonPrefix].
String? _prefixEndingAtSeparator(String commonPrefix) {
  var last = -1;
  for (var i = 0; i < commonPrefix.length; i++) {
    if (_separators.contains(commonPrefix[i])) last = i;
  }
  if (last < 0) return null;
  var end = last + 1;
  while (end < commonPrefix.length && commonPrefix[end].trim().isEmpty) {
    end++;
  }
  return commonPrefix.substring(0, end);
}
