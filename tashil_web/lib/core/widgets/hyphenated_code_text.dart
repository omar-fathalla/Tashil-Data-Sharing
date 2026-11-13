import 'package:flutter/material.dart';

/// Displays a hyphenated code so each token stays intact.
///
/// Flutter's paragraph breaker can emergency-split the last token when the
/// column is only a few pixels short (`FGCC-0700-00` / `02`). Wrapping one
/// [Text] per token (with the trailing '-') makes '-' the only wrap point.
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
    final tokens = code.split('-');
    final alignment = switch (textAlign) {
      TextAlign.left || TextAlign.start => WrapAlignment.start,
      TextAlign.right || TextAlign.end => WrapAlignment.end,
      _ => WrapAlignment.center,
    };
    return Semantics(
      label: code,
      excludeSemantics: true,
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
              style: style,
            ),
        ],
      ),
    );
  }
}
