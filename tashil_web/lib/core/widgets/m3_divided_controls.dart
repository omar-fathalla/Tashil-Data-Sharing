import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// Two control groups ([leading] | [trailing]) separated by a vertical
/// divider when both fit on one line; otherwise [trailing] drops under
/// [leading] and the divider is not shown (never a dangling divider at the
/// end of a line). Lays out from the start edge, so it follows RTL.
///
/// [trailing] must accept unbounded width (e.g. a [Wrap] or a min-size
/// [Row]); it is measured on one line before deciding.
class M3DividedControls extends MultiChildRenderObjectWidget {
  M3DividedControls({
    super.key,
    required Widget leading,
    required Widget trailing,
    this.dividerWidth = 16.0,
    this.dividerHeight = 24.0,
    this.runSpacing = 8.0,
  }) : super(children: [
          leading,
          SizedBox(
            key: const ValueKey('m3_divided_controls_divider'),
            height: dividerHeight,
            child: VerticalDivider(width: dividerWidth),
          ),
          trailing,
        ]);

  final double dividerWidth;
  final double dividerHeight;

  /// Vertical gap when [trailing] drops to the next line.
  final double runSpacing;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      RenderM3DividedControls(
        textDirection: Directionality.of(context),
        runSpacing: runSpacing,
      );

  @override
  void updateRenderObject(
      BuildContext context, RenderM3DividedControls renderObject) {
    renderObject
      ..textDirection = Directionality.of(context)
      ..runSpacing = runSpacing;
  }
}

class _ControlsParentData extends ContainerBoxParentData<RenderBox> {}

/// Render object for [M3DividedControls].
class RenderM3DividedControls extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _ControlsParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _ControlsParentData> {
  /// Creates the render object; see [M3DividedControls].
  RenderM3DividedControls({
    required TextDirection textDirection,
    required double runSpacing,
  })  : _textDirection = textDirection,
        _runSpacing = runSpacing;

  TextDirection _textDirection;
  set textDirection(TextDirection v) {
    if (v == _textDirection) return;
    _textDirection = v;
    markNeedsLayout();
  }

  double _runSpacing;
  set runSpacing(double v) {
    if (v == _runSpacing) return;
    _runSpacing = v;
    markNeedsLayout();
  }

  /// True when all three children sit on one line (divider visible).
  bool _inline = true;

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _ControlsParentData) {
      child.parentData = _ControlsParentData();
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

  @override
  void performLayout() {
    final kids = _kids;
    assert(kids.length == 3);
    final maxW = constraints.maxWidth;
    final loose = BoxConstraints(maxWidth: maxW);
    final leading = kids[0], divider = kids[1], trailing = kids[2];
    leading.layout(loose, parentUsesSize: true);
    divider.layout(loose, parentUsesSize: true);
    // Inline check: lay the trailing group out unconstrained (one line) and
    // measure it. Intrinsic widths under-report buttons/menu anchors.
    trailing.layout(const BoxConstraints(), parentUsesSize: true);
    final trailingOneLine = trailing.size.width;
    final inlineW = leading.size.width + divider.size.width + trailingOneLine;
    _inline = inlineW <= maxW;
    final rtl = _textDirection == TextDirection.rtl;
    double xFor(double start, double w, double total) =>
        rtl ? total - start - w : start;

    if (_inline) {
      final h = [leading.size.height, divider.size.height, trailing.size.height]
          .reduce((a, b) => a > b ? a : b);
      final total = constraints.constrainWidth(inlineW);
      var start = 0.0;
      for (final k in [leading, divider, trailing]) {
        (k.parentData! as _ControlsParentData).offset =
            Offset(xFor(start, k.size.width, total), (h - k.size.height) / 2);
        start += k.size.width;
      }
      size = constraints.constrain(Size(inlineW, h));
    } else {
      // Stacked: the divider takes no space and is not painted.
      divider.layout(const BoxConstraints.tightFor(width: 0, height: 0),
          parentUsesSize: true);
      trailing.layout(loose, parentUsesSize: true);
      final w = leading.size.width > trailing.size.width
          ? leading.size.width
          : trailing.size.width;
      final total = constraints.constrainWidth(w);
      (leading.parentData! as _ControlsParentData).offset =
          Offset(xFor(0, leading.size.width, total), 0);
      (divider.parentData! as _ControlsParentData).offset = Offset.zero;
      (trailing.parentData! as _ControlsParentData).offset = Offset(
          xFor(0, trailing.size.width, total),
          leading.size.height + _runSpacing);
      size = constraints.constrain(
          Size(w, leading.size.height + _runSpacing + trailing.size.height));
    }
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final kids = _kids;
    for (var i = 0; i < kids.length; i++) {
      if (i == 1 && !_inline) continue;
      final pd = kids[i].parentData! as _ControlsParentData;
      context.paintChild(kids[i], offset + pd.offset);
    }
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      defaultHitTestChildren(result, position: position);

  @override
  void visitChildrenForSemantics(RenderObjectVisitor visitor) {
    final kids = _kids;
    for (var i = 0; i < kids.length; i++) {
      if (i == 1 && !_inline) continue;
      visitor(kids[i]);
    }
  }

  @override
  double computeMinIntrinsicWidth(double height) {
    final k = _kids;
    return [
      k[0].getMinIntrinsicWidth(height),
      k[2].getMinIntrinsicWidth(height)
    ].reduce((a, b) => a > b ? a : b);
  }

  @override
  double computeMaxIntrinsicWidth(double height) {
    final k = _kids;
    return k[0].getMaxIntrinsicWidth(height) +
        k[1].getMaxIntrinsicWidth(height) +
        k[2].getMaxIntrinsicWidth(height);
  }

  @override
  Size computeDryLayout(BoxConstraints constraints) {
    // Not needed by the header (it is laid out normally); conservative.
    return constraints.constrain(Size(computeMaxIntrinsicWidth(double.infinity),
        computeMaxIntrinsicHeight(constraints.maxWidth)));
  }

  @override
  double computeMaxIntrinsicHeight(double width) {
    final k = _kids;
    return k[0].getMaxIntrinsicHeight(width) +
        _runSpacing +
        k[2].getMaxIntrinsicHeight(width);
  }

  @override
  double computeMinIntrinsicHeight(double width) =>
      computeMaxIntrinsicHeight(width);
}
