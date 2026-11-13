import 'package:flutter/material.dart';

/// Item codes are Latin/LTR. At the live 1280 shell the column is wide
/// enough for the longest hyphenated production code on one line. If the
/// column is narrower (1024+sidebar), hyphenated SKUs wrap at '-' only,
/// still in LTR order — a [Wrap] in an RTL parent previously reversed
/// `QA-NOT-IN-MASTER-999` into a visual `-IN-NOT-QA` / `999-MASTER`.
///
/// Some live "codes" are Arabic product phrases with spaces and no
/// dashes (`ماكسيل ماجيك متخصص عادي عادي`). Those must wrap at word
/// boundaries up to [maxLines], not clip on one line.
class HyphenatedCodeText extends StatelessWidget {
  const HyphenatedCodeText(
    this.code, {
    super.key,
    this.maxLines = 3,
    this.textAlign = TextAlign.center,
    this.style,
  });

  final String code;
  final int maxLines;
  final TextAlign textAlign;
  final TextStyle? style;

  static bool isHyphenatedSku(String code) {
    final t = code.trim();
    if (!t.contains('-') || t.contains(' ')) return false;
    return true;
  }

  static TextDirection directionFor(String code) {
    for (final rune in code.runes) {
      if (rune >= 0x0600 && rune <= 0x06FF) return TextDirection.rtl;
    }
    return TextDirection.ltr;
  }

  @override
  Widget build(BuildContext context) {
    final effectiveStyle = style ?? DefaultTextStyle.of(context).style;
    final direction = directionFor(code);
    return Semantics(
      label: code,
      excludeSemantics: true,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final painter = TextPainter(
            text: TextSpan(text: code, style: effectiveStyle),
            textDirection: direction,
            maxLines: 1,
          )..layout();
          final fitsOneLine = !constraints.hasBoundedWidth ||
              painter.width <= constraints.maxWidth + 0.5;
          if (fitsOneLine || maxLines <= 1) {
            return Text(
              code,
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.clip,
              textAlign: textAlign,
              textDirection: direction,
              style: effectiveStyle,
            );
          }
          if (isHyphenatedSku(code)) {
            final tokens = code.split('-');
            final alignment = switch (textAlign) {
              TextAlign.left || TextAlign.start => WrapAlignment.start,
              TextAlign.right || TextAlign.end => WrapAlignment.end,
              _ => WrapAlignment.center,
            };
            return Directionality(
              textDirection: TextDirection.ltr,
              child: Wrap(
                alignment: alignment,
                runAlignment: alignment,
                children: [
                  for (var i = 0; i < tokens.length; i++)
                    Text(
                      i == tokens.length - 1 ? tokens[i] : '${tokens[i]}-',
                      maxLines: 1,
                      softWrap: false,
                      overflow: TextOverflow.clip,
                      textAlign: textAlign,
                      style: effectiveStyle,
                    ),
                ],
              ),
            );
          }
          return Text(
            code,
            maxLines: maxLines,
            softWrap: true,
            overflow: TextOverflow.clip,
            textAlign: textAlign,
            textDirection: direction,
            style: effectiveStyle,
          );
        },
      ),
    );
  }
}
