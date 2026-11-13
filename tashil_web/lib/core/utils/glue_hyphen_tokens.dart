/// Word joiner (U+2060). Display-only: not visible, not exported, not stored.
const kWordJoiner = '\u2060';

/// Keeps '-' as a wrap opportunity and glues characters inside each token
/// so Flutter cannot emergency-break mid-token when a column is just
/// slightly narrower than the last token (e.g. `FGCC-0700-0002`).
String glueHyphenTokens(String value) {
  if (!value.contains('-')) return value;
  return value.split('-').map((tok) {
    if (tok.length <= 1) return tok;
    return tok.split('').join(kWordJoiner);
  }).join('-');
}

/// Inverse of [glueHyphenTokens] for tests and comparisons.
String stripWordJoiners(String value) => value.replaceAll(kWordJoiner, '');
