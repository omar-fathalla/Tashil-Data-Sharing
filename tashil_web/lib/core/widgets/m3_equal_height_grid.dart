import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';


/// Sell-Out is the reference KPI row: 4 columns at ≥960, 2 at ≥580, else 1.
/// Prefer [forWidthAndCount] so pages with 3 or 5 cards fill rows evenly
/// (3 across, or 3+2) instead of leaving a lonely last card (4+1).
/// [M3EqualHeightGrid] stretches an incomplete last row so 3+2 has no empty
/// third slot (the two trailing cards share the full row width).
abstract final class M3KpiGridColumns {
  static const double fourColMinWidth = 960.0;
  static const double twoColMinWidth = 580.0;

  static int forWidth(double width) => width >= fourColMinWidth
      ? 4
      : (width >= twoColMinWidth ? 2 : 1);

  /// Minimum card width when [forWidthAndCount] may step above [forWidth]
  /// to hit an exact divisor (e.g. 6 cards → 3+3 at ~880, not 2-col only).
  static const double minEvenCardWidth = 200.0;

  /// Column count that keeps card width in the Sell-Out family while
  /// maximizing how full the last row is (same card size, evenly filled).
  ///
  /// Examples at ≥960: 4 cards → 4; 3 cards → 3; 5 cards → 3 (3+2, not 4+1).
  /// At ~880: 6 cards → 3 (3+3); exact divisors preferred when cards stay
  /// ≥ [minEvenCardWidth]. Incomplete last rows are stretched by
  /// [M3EqualHeightGrid] so they fill the full width.
  static int forWidthAndCount(double width, int childCount) {
    final maxCols = forWidth(width);
    if (childCount <= 1) return 1;
    if (childCount <= maxCols) return childCount;

    // May rise above [forWidth] when an exact divisor keeps cards wide enough
    // (6 @ ~880 → 3), but never past Sell-Out's 4-col cap, and never when
    // [forWidth] already says single-column (< twoColMinWidth).
    final byMinWidth = width >= minEvenCardWidth
        ? (width / minEvenCardWidth).floor()
        : 1;
    final allowed = maxCols < 2
        ? maxCols
        : math.min(
            childCount,
            math.min(4, math.max(maxCols, byMinWidth)),
          );

    for (var c = allowed; c >= 2; c--) {
      if (childCount % c == 0) return c;
    }
    var best = maxCols;
    var bestLast = childCount % maxCols;
    if (maxCols < 2) return 1;
    for (var c = maxCols - 1; c >= 2; c--) {
      final last = childCount % c;
      if (last > bestLast) {
        best = c;
        bestLast = last;
      }
    }
    return best;
  }
}

/// Grid whose cards all share the tallest card's height (KPI rows,
/// side-by-side section cards).
///
/// Children are laid out in [columns] columns (width split by [flex], equal
/// by default), placed start-to-end in the ambient text direction. Every
/// child is first measured at its natural height, then laid out again with a
/// tight height equal to the tallest one, so no intrinsic-size pass is needed
/// (children may contain LayoutBuilders).
class M3EqualHeightGrid extends MultiChildRenderObjectWidget {
  const M3EqualHeightGrid({
    super.key,
    required this.columns,
    this.spacing = 0.0,
    this.runSpacing = 0.0,
    this.flex,
    required super.children,
  }) : assert(columns > 0);

  final int columns;
  final double spacing;
  final double runSpacing;

  /// Optional relative column widths, one per column.
  final List<double>? flex;

  @override
  RenderObject createRenderObject(BuildContext context) {
    assert(flex == null || flex!.length == columns);
    return RenderM3EqualHeightGrid(
      columns: columns,
      spacing: spacing,
      runSpacing: runSpacing,
      flex: flex,
      textDirection: Directionality.of(context),
    );
  }

  @override
  void updateRenderObject(
    BuildContext context,
    RenderM3EqualHeightGrid renderObject,
  ) {
    renderObject
      ..columns = columns
      ..spacing = spacing
      ..runSpacing = runSpacing
      ..flex = flex
      ..textDirection = Directionality.of(context);
  }
}

class _GridParentData extends ContainerBoxParentData<RenderBox> {}

class RenderM3EqualHeightGrid extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _GridParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _GridParentData> {
  RenderM3EqualHeightGrid({
    required int columns,
    required double spacing,
    required double runSpacing,
    required List<double>? flex,
    required TextDirection textDirection,
  })  : _columns = columns,
        _spacing = spacing,
        _runSpacing = runSpacing,
        _flex = flex,
        _textDirection = textDirection;

  int _columns;
  set columns(int v) {
    if (v == _columns) return;
    _columns = v;
    markNeedsLayout();
  }

  double _spacing;
  set spacing(double v) {
    if (v == _spacing) return;
    _spacing = v;
    markNeedsLayout();
  }

  double _runSpacing;
  set runSpacing(double v) {
    if (v == _runSpacing) return;
    _runSpacing = v;
    markNeedsLayout();
  }

  List<double>? _flex;
  set flex(List<double>? v) {
    if (listEquals(v, _flex)) return;
    _flex = v;
    markNeedsLayout();
  }

  TextDirection _textDirection;
  set textDirection(TextDirection v) {
    if (v == _textDirection) return;
    _textDirection = v;
    markNeedsLayout();
  }

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _GridParentData) {
      child.parentData = _GridParentData();
    }
  }

  List<RenderBox> get _kids {
    final out = <RenderBox>[];
    var c = firstChild;
    while (c != null) {
      out.add(c);
      c = childAfter(c);
    }
    return out;
  }

  List<double> _columnWidths(double width, {required int countInRow}) {
    assert(countInRow > 0 && countInRow <= _columns);
    final usable = math.max(0.0, width - _spacing * (countInRow - 1));
    final f = _flex ?? List<double>.filled(_columns, 1.0);
    final used = f.take(countInRow).toList();
    final total = used.fold<double>(0.0, (a, b) => a + b);
    return [for (final v in used) usable * v / total];
  }

  int get _rows => (childCount + _columns - 1) ~/ _columns;

  int _countInRow(int row, int kidCount) {
    final start = row * _columns;
    return math.min(_columns, kidCount - start);
  }

  double _cardHeight(double width, double Function(RenderBox, double) measure) {
    var h = 0.0;
    final kids = _kids;
    for (var i = 0; i < kids.length; i++) {
      final row = i ~/ _columns;
      final col = i % _columns;
      final widths =
          _columnWidths(width, countInRow: _countInRow(row, kids.length));
      h = math.max(h, measure(kids[i], widths[col]));
    }
    return h;
  }

  double _total(double cardH) =>
      _rows == 0 ? 0.0 : cardH * _rows + _runSpacing * (_rows - 1);

  @override
  double computeMinIntrinsicWidth(double height) => 0.0;

  @override
  double computeMaxIntrinsicWidth(double height) => 0.0;

  @override
  double computeMinIntrinsicHeight(double width) =>
      computeMaxIntrinsicHeight(width);

  @override
  double computeMaxIntrinsicHeight(double width) =>
      _total(_cardHeight(width, (c, w) => c.getMaxIntrinsicHeight(w)));

  @override
  Size computeDryLayout(covariant BoxConstraints constraints) {
    final width = constraints.maxWidth;
    final h = _cardHeight(
      width,
      (c, w) => c.getDryLayout(BoxConstraints(minWidth: w, maxWidth: w)).height,
    );
    return constraints.constrain(Size(width, _total(h)));
  }

  @override
  void performLayout() {
    final width = constraints.maxWidth;
    final kids = _kids;
    // Pass 1: natural heights (incomplete last row is stretched full-width).
    var cardH = 0.0;
    for (var i = 0; i < kids.length; i++) {
      final row = i ~/ _columns;
      final col = i % _columns;
      final widths =
          _columnWidths(width, countInRow: _countInRow(row, kids.length));
      final w = widths[col];
      kids[i].layout(
        BoxConstraints(minWidth: w, maxWidth: w),
        parentUsesSize: true,
      );
      cardH = math.max(cardH, kids[i].size.height);
    }
    // Pass 2: everyone gets the tallest height.
    final rtl = _textDirection == TextDirection.rtl;
    for (var i = 0; i < kids.length; i++) {
      final col = i % _columns;
      final row = i ~/ _columns;
      final widths =
          _columnWidths(width, countInRow: _countInRow(row, kids.length));
      final w = widths[col];
      // Not tight (no max height), so a child never becomes a
      // relayout boundary: when its content changes the grid re-measures.
      kids[i].layout(BoxConstraints(minWidth: w, maxWidth: w, minHeight: cardH),
          parentUsesSize: true);
      var x = 0.0;
      for (var c = 0; c < col; c++) {
        x += widths[c] + _spacing;
      }
      if (rtl) x = width - x - w;
      (kids[i].parentData! as _GridParentData).offset = Offset(
        x,
        row * (cardH + _runSpacing),
      );
    }
    size = constraints.constrain(Size(width, _total(cardH)));
  }

  @override
  void paint(PaintingContext context, Offset offset) =>
      defaultPaint(context, offset);

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      defaultHitTestChildren(result, position: position);
}
