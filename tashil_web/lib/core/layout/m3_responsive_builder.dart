import 'package:flutter/widgets.dart';
import 'window_size_classes.dart';

typedef M3ResponsiveWidgetBuilder = Widget Function(
  BuildContext context,
  M3LayoutMetrics metrics,
  BoxConstraints constraints,
);

/// M3ResponsiveBuilder evaluates BoxConstraints and passes computed M3LayoutMetrics
/// to the builder callback.
class M3ResponsiveBuilder extends StatelessWidget {
  final M3ResponsiveWidgetBuilder builder;

  const M3ResponsiveBuilder({
    super.key,
    required this.builder,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final metrics = M3Layout.fromConstraints(constraints);
        return builder(context, metrics, constraints);
      },
    );
  }
}
