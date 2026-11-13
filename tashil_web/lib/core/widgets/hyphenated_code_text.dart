import 'package:flutter/material.dart';

/// Item codes are Latin/LTR. At the live 1280 shell the column is wide
/// enough for the longest production code on one line. If the column is
/// narrower (1024+sidebar), tokens wrap at '-' only, still in LTR order —
/// a [Wrap] in an RTL parent previously reversed `QA-NOT-IN-MASTER-999`
/// into a visual `-IN-NOT-QA` / `999-MASTER`.
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

  @override
  Widget build(BuildContext context) {
    final effectiveStyle = style ?? DefaultTextStyle.of(context).style;
    return Semantics(
      label: code,
      excludeSemantics: true,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final painter = TextPainter(
            text: TextSpan(text: code, style: effectiveStyle),
            textDirection: TextDirection.ltr,
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
              textDirection: TextDirection.ltr,
              style: effectiveStyle,
            );
          }
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
        },
      ),
    );
  }
}
