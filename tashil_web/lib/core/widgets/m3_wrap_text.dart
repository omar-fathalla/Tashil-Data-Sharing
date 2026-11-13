import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// Table / card text that wraps up to [maxLines] (default 3) before it is
/// ellipsized, and shows its full text in a tooltip only when it is still
/// clipped after wrapping. Safe inside a DataTable (no LayoutBuilder, so
/// intrinsic column sizing works).
class M3WrapText extends StatefulWidget {
  const M3WrapText(
    this.text, {
    super.key,
    this.style,
    this.maxLines = 3,
    this.textAlign,
  });

  final String text;
  final TextStyle? style;
  final int maxLines;
  final TextAlign? textAlign;

  @override
  State<M3WrapText> createState() => _M3WrapTextState();
}

class _M3WrapTextState extends State<M3WrapText> {
  bool _clipped = false;

  void _report(bool clipped) {
    if (clipped == _clipped) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _clipped != clipped) setState(() => _clipped = clipped);
    });
  }

  @override
  Widget build(BuildContext context) {
    final text = _ClipProbe(
      onLayout: _report,
      child: Text(
        widget.text,
        maxLines: widget.maxLines,
        overflow: TextOverflow.ellipsis,
        softWrap: true,
        textAlign: widget.textAlign,
        style: widget.style,
      ),
    );
    return _clipped ? Tooltip(message: widget.text, child: text) : text;
  }
}

class _ClipProbe extends SingleChildRenderObjectWidget {
  const _ClipProbe({required this.onLayout, required super.child});

  final ValueChanged<bool> onLayout;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderClipProbe(onLayout);

  @override
  void updateRenderObject(BuildContext context, _RenderClipProbe ro) =>
      ro.onLayout = onLayout;
}

class _RenderClipProbe extends RenderProxyBox {
  _RenderClipProbe(this.onLayout);

  ValueChanged<bool> onLayout;

  @override
  void performLayout() {
    super.performLayout();
    RenderObject? r = child;
    while (r != null && r is! RenderParagraph) {
      r = r is RenderObjectWithChildMixin<RenderBox> ? r.child : null;
    }
    if (r is RenderParagraph) onLayout(r.didExceedMaxLines);
  }
}
