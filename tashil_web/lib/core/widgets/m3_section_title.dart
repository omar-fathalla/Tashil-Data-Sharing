import 'package:flutter/material.dart';

/// The one section/card title style on a page: M3 `titleMedium`
/// (16/24, w500, onSurface). Do not add weight overrides per section.
class M3SectionTitle extends StatelessWidget {
  const M3SectionTitle(this.text, {super.key, this.maxLines, this.overflow});

  final String text;
  final int? maxLines;
  final TextOverflow? overflow;

  static TextStyle? styleOf(BuildContext context) =>
      Theme.of(context).textTheme.titleMedium;

  @override
  Widget build(BuildContext context) => Text(
        text,
        maxLines: maxLines,
        overflow: overflow,
        style: styleOf(context),
      );
}
