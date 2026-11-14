import 'package:flutter/material.dart';

/// A numeric amount that must not wrap mid-number. The number and an
/// optional compact K/M suffix stay on one line; a trailing currency
/// («ج.م») may move to the next line when [maxWidth] is tighter than
/// the full string.
class AtomicNumericText extends StatelessWidget {
  const AtomicNumericText(
    this.text, {
    super.key,
    this.style,
    this.maxWidth,
    this.textAlign = TextAlign.center,
    this.overflow = TextOverflow.clip,
  });

  final String text;
  final TextStyle? style;
  final double? maxWidth;
  final TextAlign textAlign;
  final TextOverflow overflow;

  /// Split before a trailing «ج.م» / «قطعة», keeping bidi isolates on the
  /// numeric prefix so the minus stays on the left of the digits.
  static (String prefix, String? suffix) splitCurrency(String text) {
    for (final unit in ['ج.م', 'قطعة']) {
      final token = ' $unit';
      final idx = text.lastIndexOf(token);
      if (idx <= 0) continue;
      var prefix = text.substring(0, idx);
      var suffix = text.substring(idx + 1); // unit, maybe + PDI
      // Close an unclosed LRI/FSI on the prefix so line 1 is a complete run.
      if ((prefix.contains('\u2066') || prefix.contains('\u2068')) &&
          !prefix.contains('\u2069')) {
        prefix = '$prefix\u2069';
        if (suffix.endsWith('\u2069')) {
          suffix = suffix.substring(0, suffix.length - 1);
        }
      }
      return (prefix, suffix);
    }
    return (text, null);
  }

  @override
  Widget build(BuildContext context) {
    final style = this.style ?? DefaultTextStyle.of(context).style;
    final direction = Directionality.of(context);
    final maxW = maxWidth;
    final (prefix, suffix) = splitCurrency(text);

    Widget oneLine(String value) => Text(
          value,
          maxLines: 1,
          softWrap: false,
          overflow: overflow,
          textAlign: textAlign,
          style: style,
        );

    if (suffix == null || maxW == null) {
      return oneLine(text);
    }

    final fullPainter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: direction,
      maxLines: 1,
    )..layout();
    if (fullPainter.width <= maxW + 0.5) {
      return oneLine(text);
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: switch (textAlign) {
        TextAlign.left || TextAlign.start => CrossAxisAlignment.start,
        TextAlign.right || TextAlign.end => CrossAxisAlignment.end,
        _ => CrossAxisAlignment.center,
      },
      children: [
        oneLine(prefix),
        oneLine(suffix),
      ],
    );
  }
}
