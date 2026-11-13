import 'dart:ui';

import '../../../../core/network/api_client.dart';

/// Aligns [competitor] to [own] by (year, month): entry i is the competitor
/// point for own month i, or null when the competitor has no price that
/// month. Never falls back to another month or year.
List<SkuMonthlyPricePointModel?> alignSeriesToMonths(
  List<SkuMonthlyPricePointModel> own,
  List<SkuMonthlyPricePointModel> competitor,
) {
  final byKey = <int, SkuMonthlyPricePointModel>{
    for (final p in competitor) p.year * 100 + p.monthNum: p,
  };
  return [for (final p in own) byKey[p.year * 100 + p.monthNum]];
}

/// One price callout to place next to its data point.
class CalloutRequest {
  const CalloutRequest({
    required this.anchor,
    required this.size,
    required this.preferredDy,
  });

  /// Data point centre.
  final Offset anchor;

  /// Callout box size (text + padding).
  final Size size;

  /// Preferred vertical offset of the box centre from [anchor]
  /// (negative = above).
  final double preferredDy;
}

/// Places callouts in order (earlier = higher priority) so no two boxes
/// overlap and no box covers a data point in [markers]. Each callout tries
/// its preferred side, then the opposite side, then one step further out on
/// each side; a callout that fits nowhere inside [bounds] is hidden (null).
List<Rect?> layoutCallouts(
  List<CalloutRequest> requests, {
  required Rect bounds,
  List<Rect> markers = const [],
  double gap = 2.0,
}) {
  final placed = <Rect>[];
  final out = <Rect?>[];
  for (final r in requests) {
    final d = r.preferredDy;
    final step = r.size.height + gap;
    final candidates = <double>[d, -d, d + d.sign * step, -d - d.sign * step];
    Rect? chosen;
    for (final dy in candidates) {
      final rect = Rect.fromCenter(
        center: r.anchor.translate(0, dy),
        width: r.size.width,
        height: r.size.height,
      );
      if (rect.top < bounds.top || rect.bottom > bounds.bottom) continue;
      final grown = rect.inflate(gap / 2);
      if (placed.any(grown.overlaps)) continue;
      if (markers.any(grown.overlaps)) continue;
      chosen = rect;
      break;
    }
    if (chosen != null) placed.add(chosen);
    out.add(chosen);
  }
  return out;
}
