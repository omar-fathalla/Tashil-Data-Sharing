/// Display-only helper: strips a leading segment that is shared by the
/// majority of names in a dataset, cut at a separator (`-`, `–`, `—`, `:`),
/// including the separator and surrounding whitespace.
///
/// Matching is robust to Arabic letter variants (ة/ه, أ/إ/آ/ا), dash
/// variants, and invisible/odd whitespace (NBSP, thin space, RLM, ZWJ, …).
/// A prefix is used when at least two names, and at least 50% of the list,
/// share it after normalisation. It is applied per name only when that name
/// has the prefix and the remainder would not be empty.
///
/// This never changes stored data, upload parsing, dedup keys, or matching.
/// Callers must apply it only when rendering a label.
library;

const _separators = {'-', '–', '—', ':'};

/// Format / bidi marks that must not participate in the comparison.
const _ignorable = {
  0x00AD, // soft hyphen
  0x061C, // Arabic letter mark
  0x200B, // ZWSP
  0x200C, // ZWNJ
  0x200D, // ZWJ
  0x200E, // LRM
  0x200F, // RLM
  0x202A, 0x202B, 0x202C, 0x202D, 0x202E,
  0x2060, // word joiner
  0x2066, 0x2067, 0x2068, 0x2069, // bidi isolates
  0xFEFF, // BOM
};

const _spaces = {
  0x0009, 0x000A, 0x000B, 0x000C, 0x000D, 0x0020,
  0x00A0, // NBSP
  0x1680,
  0x2000, 0x2001, 0x2002, 0x2003, 0x2004, 0x2005, 0x2006,
  0x2007, 0x2008, 0x2009, 0x200A,
  0x202F, // narrow NBSP
  0x205F, 0x3000,
};

const _dashes = {
  0x002D, // hyphen-minus
  0x2010, 0x2011, 0x2012, 0x2013, 0x2014, 0x2015,
  0x2212, // minus
  0xFE58, 0xFE63, 0xFF0D,
};

/// Returns [names] with a majority leading prefix removed, or [names] as-is
/// when no majority prefix exists.
List<String> stripSharedLeadingPrefix(List<String> names) {
  if (names.length < 2) return List<String>.from(names);

  final originals = List<String>.from(names);
  final normalized = [for (final n in originals) _normalize(n)];
  final prefix = _majoritySeparatorPrefix(normalized);
  if (prefix == null || prefix.isEmpty) return originals;

  final out = <String>[];
  for (var i = 0; i < originals.length; i++) {
    if (!normalized[i].startsWith(prefix)) {
      out.add(originals[i]);
      continue;
    }
    final cut = _originalIndexAfterNormalized(originals[i], prefix);
    if (cut == null) {
      out.add(originals[i]);
      continue;
    }
    final rest = originals[i].substring(cut).trim();
    out.add(rest.isEmpty ? originals[i] : rest);
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

/// Lowercase-style fold used only for comparison, never written back.
String _normalize(String input) {
  final buf = StringBuffer();
  var pendingSpace = false;
  var started = false;
  for (final rune in input.runes) {
    if (_ignorable.contains(rune)) continue;
    if (_spaces.contains(rune)) {
      if (started) pendingSpace = true;
      continue;
    }
    if (pendingSpace) {
      buf.write(' ');
      pendingSpace = false;
    }
    started = true;
    if (_dashes.contains(rune)) {
      buf.write('-');
      continue;
    }
    buf.write(_foldLetter(String.fromCharCode(rune)));
  }
  return buf.toString();
}

String _foldLetter(String ch) {
  switch (ch) {
    case 'ة':
      return 'ه';
    case 'أ':
    case 'إ':
    case 'آ':
    case 'ٱ':
      return 'ا';
    default:
      return ch;
  }
}

/// Longest normalised prefix that ends at a separator, shared by at least
/// two names and at least half the dataset.
String? _majoritySeparatorPrefix(List<String> normalized) {
  final n = normalized.length;
  if (n < 2) return null;
  final minCount = n.isEven ? n ~/ 2 : (n / 2).ceil();
  final needed = minCount < 2 ? 2 : minCount;

  final candidates = <String>{};
  for (final name in normalized) {
    for (var i = 0; i < name.length; i++) {
      if (name[i] != '-' && name[i] != ':') continue;
      final cut = name.substring(0, i + 1);
      if (cut.isNotEmpty) candidates.add(cut);
    }
  }

  String? best;
  var bestCount = 0;
  for (final cut in candidates) {
    var count = 0;
    var emptyRemainder = false;
    for (final name in normalized) {
      if (!name.startsWith(cut)) continue;
      final rest = name.substring(cut.length).trim();
      if (rest.isEmpty) {
        emptyRemainder = true;
        continue;
      }
      count++;
    }
    // A prefix that would empty every matching name is unusable; names
    // whose remainder would be empty are simply left unchanged later.
    if (emptyRemainder && count < needed) continue;
    if (count < needed) continue;
    if (best == null ||
        cut.length > best.length ||
        (cut.length == best.length && count > bestCount)) {
      best = cut;
      bestCount = count;
    }
  }
  return best;
}

/// Index in [original] just after the characters that normalise to
/// [normPrefix], skipping trailing whitespace so the remainder starts
/// at the next visible character.
int? _originalIndexAfterNormalized(String original, String normPrefix) {
  if (normPrefix.isEmpty) return null;
  var ni = 0;
  var i = 0;
  final units = original.runes.toList();
  var pendingSpace = false;
  var started = false;

  bool emit(String ch) {
    if (ni >= normPrefix.length) return false;
    if (normPrefix[ni] != ch) return false;
    ni++;
    return true;
  }

  while (i < units.length && ni < normPrefix.length) {
    final rune = units[i];
    if (_ignorable.contains(rune)) {
      i++;
      continue;
    }
    if (_spaces.contains(rune)) {
      if (started) pendingSpace = true;
      i++;
      continue;
    }
    if (pendingSpace) {
      if (!emit(' ')) return null;
      pendingSpace = false;
      if (ni >= normPrefix.length) break;
    }
    started = true;
    final ch =
        _dashes.contains(rune) ? '-' : _foldLetter(String.fromCharCode(rune));
    if (!emit(ch)) return null;
    i++;
    if (ni >= normPrefix.length) break;
  }
  if (ni < normPrefix.length) {
    // Trailing spaces in the prefix can be satisfied by pending/original space.
    if (pendingSpace && normPrefix[ni] == ' ') {
      ni++;
      pendingSpace = false;
    }
    while (ni < normPrefix.length && normPrefix[ni] == ' ') {
      ni++;
    }
    if (ni < normPrefix.length) return null;
  }
  // Skip remaining whitespace / ignorables in the original so the
  // remainder starts at the first visible character.
  while (i < units.length &&
      (_ignorable.contains(units[i]) || _spaces.contains(units[i]))) {
    i++;
  }
  var consumed = 0;
  for (var k = 0; k < i; k++) {
    consumed += String.fromCharCode(units[k]).length;
  }
  return consumed;
}
