import 'package:flutter/material.dart';

import '../theme/m3_shape.dart';

/// Small tonal container (tag, badge, chip-like row, highlight strip) drawn
/// with a real [Material] surface instead of `Container(BoxDecoration)`.
///
/// - Colours must be colour-scheme roles (solid, no `withOpacity`).
/// - When [onTap] is set, an [InkWell] provides the official M3 state layers
///   (hover 8 %, focus/pressed 10 %), a 3dp `secondary` focus ring, button
///   semantics and a 48dp minimum height.
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
      content =
          _FocusRingInkWell(onTap: onTap!, shape: shape, child: content);
    }
    Widget surface = Material(
      color: color,
      shape: shape,
      clipBehavior: onTap != null ? Clip.antiAlias : Clip.none,
      textStyle: DefaultTextStyle.of(context).style,
      child: content,
    );
    if (onTap != null) {
      // Tappable: announced as a button with a 48dp minimum target.
      surface = Semantics(
        button: true,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48.0),
          child: surface,
        ),
      );
    }
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

/// InkWell that paints a 3dp `secondary` ring while keyboard-focused.
class _FocusRingInkWell extends StatefulWidget {
  const _FocusRingInkWell({
    required this.onTap,
    required this.shape,
    required this.child,
  });

  final VoidCallback onTap;
  final ShapeBorder shape;
  final Widget child;

  @override
  State<_FocusRingInkWell> createState() => _FocusRingInkWellState();
}

class _FocusRingInkWellState extends State<_FocusRingInkWell> {
  bool _focused = false;

  ShapeBorder _ringShape(Color color) {
    final ring = BorderSide(color: color, width: 3.0);
    final s = widget.shape;
    if (s is CircleBorder) return s.copyWith(side: ring);
    if (s is RoundedRectangleBorder) return s.copyWith(side: ring);
    return RoundedRectangleBorder(side: ring);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return DecoratedBox(
      position: DecorationPosition.foreground,
      decoration: ShapeDecoration(
        shape: _focused
            ? _ringShape(cs.secondary)
            : const RoundedRectangleBorder(),
      ),
      child: InkWell(
        onTap: widget.onTap,
        customBorder: widget.shape,
        onFocusChange: (f) => setState(() => _focused = f),
        child: widget.child,
      ),
    );
  }
}
