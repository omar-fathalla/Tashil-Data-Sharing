import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Vertical stack (children stretched to the full width) whose LAST child is
/// offered any minimum height left over from the incoming constraints.
///
/// Use it as a card body inside an equal-height row: the card is measured at
/// its natural height first, then re-laid out with a larger minimum height,
/// which this widget hands to its last child (e.g. an [M3FillRows]). Works
/// with unbounded max height (no Expanded needed, no intrinsic pass).
class M3FillColumn extends MultiChildRenderObjectWidget {
  const M3FillColumn({super.key, required super.children});

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderFillColumn();
}

/// List of rows that shows at least [minRows] rows and, when its parent
/// offers a larger minimum height, as many further rows as fit completely.
/// Rows that do not fit are neither painted, hit-tested nor exposed to
/// semantics. Its natural height is that of the first [minRows] rows.
class M3FillRows extends MultiChildRenderObjectWidget {
  const M3FillRows({super.key, required this.minRows, required super.children})
    : assert(minRows >= 0);

  final int minRows;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      RenderM3FillRows(minRows: minRows);

  @override
  void updateRenderObject(BuildContext context, RenderM3FillRows renderObject) {
    renderObject.minRows = minRows;
  }
}

class _FillParentData extends ContainerBoxParentData<RenderBox> {
  bool visible = true;
}

mixin _FillChildren
    on RenderBox, ContainerRenderObjectMixin<RenderBox, _FillParentData> {
  List<RenderBox> get kids {
    final out = <RenderBox>[];
    var c = firstChild;
    while (c != null) {
      out.add(c);
      c = childAfter(c);
    }
    return out;
  }

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _FillParentData) {
      child.parentData = _FillParentData();
    }
  }

  @override
  double computeMinIntrinsicWidth(double height) => 0.0;

  @override
  double computeMaxIntrinsicWidth(double height) => 0.0;

  @override
  void paint(PaintingContext context, Offset offset) {
    for (final c in kids) {
      final pd = c.parentData! as _FillParentData;
      if (pd.visible) context.paintChild(c, offset + pd.offset);
    }
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    for (final c in kids.reversed) {
      final pd = c.parentData! as _FillParentData;
      if (!pd.visible) continue;
      final hit = result.addWithPaintOffset(
        offset: pd.offset,
        position: position,
        hitTest: (r, p) => c.hitTest(r, position: p),
      );
      if (hit) return true;
    }
    return false;
  }

  @override
  void visitChildrenForSemantics(RenderObjectVisitor visitor) {
    for (final c in kids) {
      if ((c.parentData! as _FillParentData).visible) visitor(c);
    }
  }
}

class _RenderFillColumn extends RenderBox
    with ContainerRenderObjectMixin<RenderBox, _FillParentData>, _FillChildren {
  @override
  double computeMinIntrinsicHeight(double width) =>
      kids.fold(0.0, (h, c) => h + c.getMinIntrinsicHeight(width));

  @override
  double computeMaxIntrinsicHeight(double width) =>
      kids.fold(0.0, (h, c) => h + c.getMaxIntrinsicHeight(width));

  @override
  void performLayout() {
    final width = constraints.maxWidth;
    final list = kids;
    var y = 0.0;
    for (var i = 0; i < list.length; i++) {
      final c = list[i];
      final last = i == list.length - 1;
      final minH = last ? math.max(0.0, constraints.minHeight - y) : 0.0;
      c.layout(
        BoxConstraints(minWidth: width, maxWidth: width, minHeight: minH),
        parentUsesSize: true,
      );
      (c.parentData! as _FillParentData).offset = Offset(0, y);
      y += c.size.height;
    }
    size = constraints.constrain(Size(width, y));
  }
}

class RenderM3FillRows extends RenderBox
    with ContainerRenderObjectMixin<RenderBox, _FillParentData>, _FillChildren {
  RenderM3FillRows({required int minRows}) : _minRows = minRows;

  int _minRows;
  set minRows(int v) {
    if (v == _minRows) return;
    _minRows = v;
    markNeedsLayout();
  }

  /// Rows currently shown (for tests / diagnostics).
  int get visibleCount =>
      kids.where((c) => (c.parentData! as _FillParentData).visible).length;

  double _sum(double Function(RenderBox) h) {
    var total = 0.0;
    final list = kids;
    for (var i = 0; i < math.min(_minRows, list.length); i++) {
      total += h(list[i]);
    }
    return total;
  }

  @override
  double computeMinIntrinsicHeight(double width) =>
      _sum((c) => c.getMinIntrinsicHeight(width));

  @override
  double computeMaxIntrinsicHeight(double width) =>
      _sum((c) => c.getMaxIntrinsicHeight(width));

  @override
  void performLayout() {
    final width = constraints.maxWidth;
    final target = constraints.minHeight;
    var y = 0.0;
    var i = 0;
    var full = false;
    for (final c in kids) {
      c.layout(
        BoxConstraints(minWidth: width, maxWidth: width),
        parentUsesSize: true,
      );
      final pd = c.parentData! as _FillParentData;
      final show = i < _minRows || (!full && y + c.size.height <= target);
      if (!show) full = true;
      pd.visible = show;
      pd.offset = Offset(0, y);
      if (show) y += c.size.height;
      i++;
    }
    size = constraints.constrain(Size(width, y));
  }
}
