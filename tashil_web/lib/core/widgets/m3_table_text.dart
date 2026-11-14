import 'package:flutter/material.dart';

import 'm3_wrap_text.dart';

/// Shared table header/cell text: **centered** by default, wraps up to
/// [maxLines] (≤3) with tooltip when still clipped. Use for every column —
/// including product/branch/item name columns — so headers and body share
/// one axis (Sell-Out / TM visual-consistency rule).
class M3TableText extends StatelessWidget {
  const M3TableText(
    this.text, {
    super.key,
    this.style,
    this.maxLines = 3,
    this.textAlign = TextAlign.center,
  });

  final String text;
  final TextStyle? style;
  final int maxLines;
  final TextAlign textAlign;

  /// [DataColumn.headingRowAlignment] for every centered column.
  static const MainAxisAlignment headingAlignment = MainAxisAlignment.center;

  @override
  Widget build(BuildContext context) {
    return M3WrapText(
      text,
      style: style,
      maxLines: maxLines,
      textAlign: textAlign,
    );
  }
}
