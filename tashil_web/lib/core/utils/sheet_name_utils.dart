import 'package:flutter/widgets.dart';

/// Short display label for an uploaded Excel sheet name: its first word
/// (split on `_`, `-`, spaces and `.`), cut to [maxChars] characters with an
/// ellipsis. Show the full name in a tooltip next to it.
String sheetShortName(String name, {int maxChars = 6}) {
  final trimmed = name.trim();
  if (trimmed.isEmpty) return trimmed;
  final first = trimmed.split(RegExp(r'[_\-\s.]+')).firstWhere(
        (w) => w.isNotEmpty,
        orElse: () => trimmed,
      );
  final chars = first.characters;
  return chars.length > maxChars ? '${chars.take(maxChars)}…' : first;
}
