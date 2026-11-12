import 'package:flutter/material.dart';

import '../theme/m3_shape.dart';

/// Small tonal container (tag, badge, chip-like row, highlight strip) drawn
/// with a real [Material] surface instead of `Container(BoxDecoration)`.
///
/// - Colours must be colour-scheme roles (solid, no `withOpacity`).
/// - When [onTap] is set, an [InkWell] provides the official M3 state layers
///   (hover 8 %, focus/pressed 10 %) and a keyboard focus highlight.
/// - Preserves the inherited [DefaultTextStyle] (unlike a bare [Material]).
class M3TonalSurface extends StatelessWidget {
  const M3TonalSurface({
    super.key,
    required this.color,
    required this.child,
    this.borderColor,
    this.borderWidth = 1.0,
    this.borderRadius = M3Shape.radiusSm,
    this.circle = false,
    this.padding = EdgeInsets.zero,
    this.alignment,
    this.width,
    this.height,
    this.constraints,
    this.onTap,
    this.tooltip,
  });

  final Color color;
  final Widget child;
  final Color? borderColor;
  final double borderWidth;
  final BorderRadius borderRadius;
  final bool circle;
  final EdgeInsetsGeometry padding;
  final AlignmentGeometry? alignment;
  final double? width;
  final double? height;
  final BoxConstraints? constraints;
  final VoidCallback? onTap;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final side = borderColor == null
        ? BorderSide.none
        : BorderSide(color: borderColor!, width: borderWidth);
    final ShapeBorder shape = circle
        ? CircleBorder(side: side)
        : RoundedRectangleBorder(borderRadius: borderRadius, side: side);

    Widget content = child;
    if (alignment != null) {
      content = Align(alignment: alignment!, child: content);
    }
    content = Padding(padding: padding, child: content);
    if (onTap != null) {
      content = InkWell(onTap: onTap, customBorder: shape, child: content);
    }
    Widget surface = Material(
      color: color,
      shape: shape,
      clipBehavior: Clip.antiAlias,
      textStyle: DefaultTextStyle.of(context).style,
      child: content,
    );
    if (width != null || height != null) {
      surface = SizedBox(width: width, height: height, child: surface);
    }
    if (constraints != null) {
      surface = ConstrainedBox(constraints: constraints!, child: surface);
    }
    if (tooltip != null) surface = Tooltip(message: tooltip!, child: surface);
    return surface;
  }
}
