import 'package:flutter/material.dart';
import '../theme/m3_shape.dart';
import '../theme/m3_spacing.dart';

enum M3CardVariant { filled, outlined, elevated }

/// M3 card with the three spec variants. Use instead of
/// `Container(decoration: BoxDecoration(...boxShadow...))`.
class M3Card extends StatelessWidget {
  const M3Card({
    super.key,
    required this.child,
    this.variant = M3CardVariant.outlined,
    this.padding = M3Spacing.pSm,
    this.onTap,
    this.clip = Clip.antiAlias,
  });

  const M3Card.filled({
    super.key,
    required this.child,
    this.padding = M3Spacing.pSm,
    this.onTap,
    this.clip = Clip.antiAlias,
  }) : variant = M3CardVariant.filled;

  const M3Card.outlined({
    super.key,
    required this.child,
    this.padding = M3Spacing.pSm,
    this.onTap,
    this.clip = Clip.antiAlias,
  }) : variant = M3CardVariant.outlined;

  final Widget child;
  final M3CardVariant variant;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final Clip clip;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    Widget content = Padding(padding: padding, child: child);
    if (onTap != null) {
      content = InkWell(onTap: onTap, child: content);
    }
    switch (variant) {
      case M3CardVariant.filled:
        return Card.filled(
          color: cs.surfaceContainerHighest,
          shape: M3Shape.shapeMd,
          clipBehavior: clip,
          child: content,
        );
      case M3CardVariant.elevated:
        return Card(
          elevation: 1.0,
          color: cs.surfaceContainerLow,
          shape: M3Shape.shapeMd,
          clipBehavior: clip,
          child: content,
        );
      case M3CardVariant.outlined:
        return Card.outlined(
          clipBehavior: clip,
          child: content,
        );
    }
  }
}
