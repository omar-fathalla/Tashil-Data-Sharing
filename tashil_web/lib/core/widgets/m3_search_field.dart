import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// Sizes a search [TextField] so its placeholder never clips.
///
/// The minimum width is measured from [hintText] (bodyLarge with M3 0.5
/// tracking, merged with [hintStyle]) plus [chrome] (48dp search icon, 12dp
/// end padding, 8dp border/caret margin). With [width] it keeps that fixed
/// size, grown to the minimum when needed; without it (e.g. inside
/// [M3FlexWrapFill]) it fills what its parent gives, never below the minimum.
class M3SearchFieldWidth extends StatelessWidget {
  const M3SearchFieldWidth({
    super.key,
    required this.hintText,
    required this.child,
    this.hintStyle,
    this.width,
    this.chrome = defaultChrome,
  });

  final String hintText;
  final TextStyle? hintStyle;
  final double? width;
  final double chrome;
  final Widget child;

  static const double defaultChrome = 48.0 + 12.0 + 8.0;

  /// Width that shows [hint] in full in a search field with [chrome].
  static double minWidthFor(BuildContext context, String hint,
      {TextStyle? hintStyle, double chrome = defaultChrome}) {
    final theme = Theme.of(context);
    final base = theme.textTheme.bodyLarge;
    var style = base?.copyWith(letterSpacing: base.letterSpacing ?? 0.5);
    if (hintStyle != null) style = style?.merge(hintStyle) ?? hintStyle;
    final tp = TextPainter(
      text: TextSpan(text: hint, style: style),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: 1,
    )..layout();
    final w = tp.width;
    tp.dispose();
    return (w + chrome).ceilToDouble();
  }

  @override
  Widget build(BuildContext context) {
    final minW =
        minWidthFor(context, hintText, hintStyle: hintStyle, chrome: chrome);
    final sized = width == null
        ? child
        : SizedBox(width: math.max(width!, minW), child: child);
    return ConstrainedBox(
      constraints: BoxConstraints(minWidth: minW),
      child: sized,
    );
  }
}

/// Marks the [M3FlexWrap] child that fills the rest of its row.
class M3FlexWrapFill extends ParentDataWidget<M3FlexWrapParentData> {
  const M3FlexWrapFill({super.key, required super.child});

  @override
  void applyParentData(RenderObject renderObject) {
    final data = renderObject.parentData! as M3FlexWrapParentData;
    if (!data.fill) {
      data.fill = true;
      renderObject.parent?.markNeedsLayout();
    }
  }

  @override
  Type get debugTypicalAncestorWidgetClass => M3FlexWrap;
}

/// A [Wrap] (start-aligned, cross-axis centred) whose [M3FlexWrapFill]
/// child takes the remaining width of its run, never less than its minimum
/// intrinsic width. When it can't fit, it starts a new run and fills it.
class M3FlexWrap extends MultiChildRenderObjectWidget {
  const M3FlexWrap({
    super.key,
    this.spacing = 8.0,
    this.runSpacing = 8.0,
    this.textDirection,
    required super.children,
  });

  final double spacing;
  final double runSpacing;
  final TextDirection? textDirection;

  @override
  RenderObject createRenderObject(BuildContext context) => RenderM3FlexWrap(
        spacing: spacing,
        runSpacing: runSpacing,
        textDirection: textDirection ?? Directionality.of(context),
      );

  @override
  void updateRenderObject(BuildContext context, RenderM3FlexWrap renderObject) {
    renderObject
      ..spacing = spacing
      ..runSpacing = runSpacing
      ..textDirection = textDirection ?? Directionality.of(context);
  }
}

class M3FlexWrapParentData extends ContainerBoxParentData<RenderBox> {
  bool fill = false;
}

class RenderM3FlexWrap extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, M3FlexWrapParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, M3FlexWrapParentData> {
  RenderM3FlexWrap({
    required double spacing,
    required double runSpacing,
    required TextDirection textDirection,
  })  : _spacing = spacing,
        _runSpacing = runSpacing,
        _textDirection = textDirection;

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

  TextDirection _textDirection;
  set textDirection(TextDirection v) {
    if (v == _textDirection) return;
    _textDirection = v;
    markNeedsLayout();
  }

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! M3FlexWrapParentData) {
      child.parentData = M3FlexWrapParentData();
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

  bool _isFill(RenderBox c) => (c.parentData! as M3FlexWrapParentData).fill;

  /// Lays out (or dry-lays out) the children; returns sizes, offsets, size.
  (List<Size>, List<Offset>, Size) _compute(BoxConstraints constraints,
      Size Function(RenderBox, BoxConstraints) layoutChild) {
    final kids = _kids;
    final maxW = constraints.maxWidth;
    final loose = BoxConstraints(maxWidth: maxW);
    final sizes = List<Size>.filled(kids.length, Size.zero);
    final widths = <double>[];
    for (var i = 0; i < kids.length; i++) {
      if (_isFill(kids[i])) {
        widths
            .add(math.min(kids[i].getMinIntrinsicWidth(double.infinity), maxW));
      } else {
        sizes[i] = layoutChild(kids[i], loose);
        widths.add(sizes[i].width);
      }
    }
    // Break into runs.
    final runs = <List<int>>[];
    var run = <int>[];
    var used = 0.0;
    for (var i = 0; i < kids.length; i++) {
      final add = run.isEmpty ? widths[i] : used + _spacing + widths[i];
      if (run.isNotEmpty && add > maxW + 0.01) {
        runs.add(run);
        run = [i];
        used = widths[i];
      } else {
        run.add(i);
        used = add;
      }
    }
    if (run.isNotEmpty) runs.add(run);
    // Fill children take the rest of their run.
    for (final r in runs) {
      final fills = r.where((i) => _isFill(kids[i])).toList();
      if (fills.isEmpty) continue;
      var others = 0.0;
      for (final i in r) {
        if (!_isFill(kids[i])) others += widths[i];
      }
      final free =
          (maxW.isFinite ? maxW : others) - others - _spacing * (r.length - 1);
      for (final i in fills) {
        final w = maxW.isFinite
            ? math.max(widths[i], free / fills.length)
            : widths[i];
        sizes[i] = layoutChild(kids[i], BoxConstraints.tightFor(width: w));
        widths[i] = w;
      }
    }
    // Position.
    final offsets = List<Offset>.filled(kids.length, Offset.zero);
    var y = 0.0;
    var maxRunW = 0.0;
    for (final r in runs) {
      var h = 0.0;
      var rw = 0.0;
      for (final i in r) {
        h = math.max(h, sizes[i].height);
      }
      var x = 0.0;
      for (final i in r) {
        offsets[i] = Offset(x, y + (h - sizes[i].height) / 2);
        x += sizes[i].width + _spacing;
      }
      rw = x - _spacing;
      maxRunW = math.max(maxRunW, rw);
      y += h + _runSpacing;
    }
    final totalH = runs.isEmpty ? 0.0 : y - _runSpacing;
    final hasFill = kids.any(_isFill);
    final width = hasFill && maxW.isFinite ? maxW : maxRunW;
    final size = constraints.constrain(Size(width, totalH));
    if (_textDirection == TextDirection.rtl) {
      for (var i = 0; i < kids.length; i++) {
        offsets[i] =
            Offset(size.width - offsets[i].dx - sizes[i].width, offsets[i].dy);
      }
    }
    return (sizes, offsets, size);
  }

  @override
  Size computeDryLayout(BoxConstraints constraints) =>
      _compute(constraints, (c, bc) => c.getDryLayout(bc)).$3;

  @override
  void performLayout() {
    final (_, offsets, s) = _compute(constraints, (c, bc) {
      c.layout(bc, parentUsesSize: true);
      return c.size;
    });
    final kids = _kids;
    for (var i = 0; i < kids.length; i++) {
      (kids[i].parentData! as M3FlexWrapParentData).offset = offsets[i];
    }
    size = s;
  }

  @override
  double computeMinIntrinsicWidth(double height) {
    var w = 0.0;
    for (final c in _kids) {
      w = math.max(w, c.getMinIntrinsicWidth(height));
    }
    return w;
  }

  @override
  double computeMaxIntrinsicWidth(double height) {
    var w = 0.0;
    final kids = _kids;
    for (final c in kids) {
      w += c.getMaxIntrinsicWidth(height);
    }
    return w + _spacing * math.max(0, kids.length - 1);
  }

  @override
  double computeMinIntrinsicHeight(double width) =>
      computeDryLayout(BoxConstraints(maxWidth: width)).height;

  @override
  double computeMaxIntrinsicHeight(double width) =>
      computeMinIntrinsicHeight(width);

  @override
  void paint(PaintingContext context, Offset offset) =>
      defaultPaint(context, offset);

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      defaultHitTestChildren(result, position: position);
}
