import 'package:flutter/material.dart';

/// Single-line [SegmentedButton] label with a minimum width.
///
/// `SegmentedButton` does not forward `ButtonStyle.minimumSize` to its
/// segments, so a theme-level `Size(112, 40)` never reaches them. The width
/// has to come from the label instead. Segments all take the width of the
/// widest one, so the default 64dp + 2 × 12dp padding + the 18dp check and
/// 8dp gap gives ≥ 112dp per segment (mockup `.seg button`).
class M3SegmentLabel extends StatelessWidget {
  const M3SegmentLabel(this.text, {super.key, this.minWidth = 64.0});

  final String text;

  /// Minimum label width (excluding the segment padding and check icon).
  final double minWidth;

  @override
  Widget build(BuildContext context) => ConstrainedBox(
        constraints: BoxConstraints(minWidth: minWidth),
        child: Text(
          text,
          textAlign: TextAlign.center,
          maxLines: 1,
          softWrap: false,
          overflow: TextOverflow.visible,
        ),
      );
}
