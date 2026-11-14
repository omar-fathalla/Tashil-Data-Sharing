import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';


/// Sell-Out is the reference KPI row: 4 columns at ≥960, 2 at ≥580, else 1.
/// Pages with 5 cards use the same breakpoints (4+1 at the live 1280+sidebar
/// shell) so card width and the 138px height stay in family.
abstract final class M3KpiGridColumns {
  static const double fourColMinWidth = 960.0;
  static const double twoColMinWidth = 580.0;

  static int forWidth(double width) => width >= fourColMinWidth
      ? 4
      : (width >= twoColMinWidth ? 2 : 1);
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

  List<double> _columnWidths(double width) {
    final usable = math.max(0.0, width - _spacing * (_columns - 1));
    final f = _flex ?? List<double>.filled(_columns, 1.0);
    final total = f.fold<double>(0.0, (a, b) => a + b);
    return [for (final v in f) usable * v / total];
  }

  int get _rows => (childCount + _columns - 1) ~/ _columns;

  double _cardHeight(double width, double Function(RenderBox, double) measure) {
    final widths = _columnWidths(width);
    var h = 0.0;
    final kids = _kids;
    for (var i = 0; i < kids.length; i++) {
      h = math.max(h, measure(kids[i], widths[i % _columns]));
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
    final widths = _columnWidths(width);
    final kids = _kids;
    // Pass 1: natural heights.
    var cardH = 0.0;
    for (var i = 0; i < kids.length; i++) {
      final w = widths[i % _columns];
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
