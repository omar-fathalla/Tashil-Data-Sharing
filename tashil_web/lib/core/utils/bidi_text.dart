/// Display-only Unicode isolates for mixed Arabic/LTR text.
///
/// CanvasKit does not use the OS bidi engine the same way as native
/// widgets; Latin filenames, codes and punctuation inside an Arabic
/// sentence must be wrapped so "file.xlsx" and "؟" stay in the right
/// order. These marks are zero-width, never stored, never exported.
library;

/// Left-to-Right Isolate (U+2066).
const kLri = '\u2066';

/// Pop Directional Isolate (U+2069).
const kPdi = '\u2069';

/// Right-to-Left Mark (U+200F). Keeps a trailing ASCII '.' or ')' at
/// the end of an RTL sentence instead of jumping to the start.
const kRlm = '\u200F';

/// Wraps [text] in LRI…PDI so Latin/code/filename runs stay LTR
/// inside surrounding Arabic.
String ltrIsolate(String text) {
  if (text.isEmpty) return text;
  if (text.startsWith(kLri) && text.endsWith(kPdi)) return text;
  return '$kLri$text$kPdi';
}

/// `"filename.xlsx"` with the Latin name isolated so the Arabic
/// question mark after it stays at the end of the sentence.
String quotedLtr(String text) => '"${ltrIsolate(text)}"';

/// Append an RLM so a trailing Latin punctuation mark does not
/// visually move to the start of an RTL sentence.
String rtlEnd(String sentence) => '$sentence$kRlm';
