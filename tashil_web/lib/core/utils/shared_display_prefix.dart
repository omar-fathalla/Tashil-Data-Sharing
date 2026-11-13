/// Display-only helper: for each name, strips the longest leading
/// separator-segment (`-`, `–`, `—`, `:`, including the separator and
/// surrounding whitespace) that is shared by at least two names in the
/// dataset after normalisation.
///
/// Multiple prefix clusters are handled independently, so a minority
/// group such as "… مواد عناية - …" is stripped even when another
/// "… ماركت - …" group is the majority. Matching is robust to Arabic
/// letter variants (ة/ه, أ/إ/آ/ا), dash variants, and invisible/odd
/// whitespace (NBSP, thin space, RLM, ZWJ, …).
///
/// A name is never left empty. If stripping would make two originally
/// different names (after normalisation) share a display label, enough
/// of the original is kept to disambiguate.
///
/// This never changes stored data, upload parsing, dedup keys, or matching.
/// Callers must apply it only when rendering a label.
library;

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

/// Returns [names] with per-name shared leading prefixes removed, or
/// [names] as-is when no shared prefix exists.
List<String> stripSharedLeadingPrefix(List<String> names) {
  if (names.length < 2) return List<String>.from(names);

  final originals = List<String>.from(names);
  final normalized = [for (final n in originals) _normalize(n)];
  final stripped = <String>[];

  for (var i = 0; i < originals.length; i++) {
    final prefix = _longestSharedSeparatorPrefix(normalized[i], normalized);
    if (prefix == null || prefix.isEmpty) {
      stripped.add(originals[i]);
      continue;
    }
    final cut = _originalIndexAfterNormalized(originals[i], prefix);
    if (cut == null) {
      stripped.add(originals[i]);
      continue;
    }
    final rest = originals[i].substring(cut).trim();
    stripped.add(rest.isEmpty ? originals[i] : rest);
  }

  return _disambiguate(originals, normalized, stripped);
}

/// Map of original name → display name for a dataset.
Map<String, String> displayNamesWithoutSharedPrefix(Iterable<String> names) {
  final list = names.toList();
  final stripped = stripSharedLeadingPrefix(list);
  return {for (var i = 0; i < list.length; i++) list[i]: stripped[i]};
}

/// Display form of [name] given the full [dataset] of names.
String displayNameWithoutSharedPrefix(String name, Iterable<String> dataset) {
  return displayNamesWithoutSharedPrefix(dataset)[name] ?? name;
}

/// Longest leading separator-segment of [name] that is a prefix of at
/// least two normalised names in [all].
String? _longestSharedSeparatorPrefix(String name, List<String> all) {
  if (name.isEmpty || all.length < 2) return null;
  String? best;
  for (var i = 0; i < name.length; i++) {
    if (name[i] != '-' && name[i] != ':') continue;
    final cut = name.substring(0, i + 1);
    if (cut.isEmpty) continue;
    final rest = name.substring(cut.length).trim();
    if (rest.isEmpty) continue;
    var count = 0;
    for (final other in all) {
      if (other.startsWith(cut)) count++;
    }
    if (count < 2) continue;
    if (best == null || cut.length > best.length) best = cut;
  }
  return best;
}

/// When aggressive stripping would collapse two originally-different
/// names onto one label, keep the remainder after their longest common
/// prefix (trimmed of a leftover leading separator) so the labels stay
/// unique. Names that already normalise to the same string may share a
/// label. If there is no common prefix, the originals are kept.
List<String> _disambiguate(
  List<String> originals,
  List<String> normalized,
  List<String> stripped,
) {
  final out = List<String>.from(stripped);

  final groups = <String, List<int>>{};
  for (var i = 0; i < out.length; i++) {
    groups.putIfAbsent(out[i], () => []).add(i);
  }

  for (final indexes in groups.values) {
    final distinctNorm = <String>{for (final i in indexes) normalized[i]};
    if (distinctNorm.length < 2) continue;

    final common = _longestCommonPrefix(distinctNorm);
    for (final i in indexes) {
      if (common.isEmpty) {
        out[i] = originals[i];
        continue;
      }
      final cut = _originalIndexAfterNormalized(originals[i], common);
      if (cut == null) {
        out[i] = originals[i];
        continue;
      }
      final rest = _trimLeadingSeparator(originals[i].substring(cut));
      out[i] = rest.isEmpty ? originals[i] : rest;
    }
  }

  // If the common-prefix remainder still collides (should be rare),
  // fall back to the original strings for that bucket.
  final seen = <String, int>{};
  final collide = <int>{};
  for (var i = 0; i < out.length; i++) {
    final prev = seen[out[i]];
    if (prev == null) {
      seen[out[i]] = i;
      continue;
    }
    if (normalized[prev] != normalized[i]) {
      collide.add(prev);
      collide.add(i);
    }
  }
  for (final i in collide) {
    out[i] = originals[i];
  }
  return out;
}

String _longestCommonPrefix(Iterable<String> values) {
  final list = values.toList();
  if (list.isEmpty) return '';
  var prefix = list.first;
  for (final s in list.skip(1)) {
    var i = 0;
    final n = prefix.length < s.length ? prefix.length : s.length;
    while (i < n && prefix[i] == s[i]) {
      i++;
    }
    prefix = prefix.substring(0, i);
    if (prefix.isEmpty) return '';
  }
  return prefix;
}

/// Trim leading whitespace and a single leftover separator so a common
/// prefix that ends just before `- rest` yields `rest`.
String _trimLeadingSeparator(String input) {
  var start = 0;
  final units = input.runes.toList();
  while (start < units.length &&
      (_ignorable.contains(units[start]) || _spaces.contains(units[start]))) {
    start++;
  }
  if (start < units.length &&
      (_dashes.contains(units[start]) || units[start] == 0x003A)) {
    start++;
    while (start < units.length &&
        (_ignorable.contains(units[start]) || _spaces.contains(units[start]))) {
      start++;
    }
  }
  var consumed = 0;
  for (var k = 0; k < start; k++) {
    consumed += String.fromCharCode(units[k]).length;
  }
  return input.substring(consumed).trim();
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
    final ch = _dashes.contains(rune)
        ? '-'
        : _foldLetter(String.fromCharCode(rune));
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
