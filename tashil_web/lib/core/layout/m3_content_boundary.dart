import 'package:flutter/widgets.dart';

/// M3ContentBoundary expands across the full available viewport width
/// (`double.infinity`) so all dashboards, KPI cards, and tables utilize the entire
/// dedicated content area.
class M3ContentBoundary extends StatelessWidget {
  final Widget child;
  final double maxWidth;
  final EdgeInsetsGeometry? padding;
  final AlignmentGeometry alignment;

  const M3ContentBoundary({
    super.key,
    required this.child,
    this.maxWidth = double.infinity,
    this.padding,
    this.alignment = AlignmentDirectional.topStart,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: padding != null ? Padding(padding: padding!, child: child) : child,
    );
  }
}
