import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tashil_web/core/utils/glue_hyphen_tokens.dart';
import 'package:tashil_web/core/widgets/hyphenated_code_text.dart';

bool _isCombiningMark(String ch) {
  if (ch.isEmpty) return false;
  final c = ch.codeUnitAt(0);
  return (c >= 0x0300 && c <= 0x036F) ||
      (c >= 0x064B && c <= 0x065F) ||
      c == 0x0670 ||
      (c >= 0x06D6 && c <= 0x06ED);
}

bool _clusterMayHaveEmptyBox(String text, int i) {
  if (_isCombiningMark(text[i])) return true;
  if (i + 1 < text.length && _isCombiningMark(text[i + 1])) return true;
  if (i > 0 && _isCombiningMark(text[i - 1])) return true;
  return false;
}

Finder findTextLoose(String expected, {Finder? scope}) {
  final pred = find.byWidgetPredicate((w) {
    if (w is! Text || w.data == null) return false;
    return stripWordJoiners(w.data!) == expected;
  });
  return scope == null ? pred : find.descendant(of: scope, matching: pred);
}

/// The DataTable heading or data cell that actually clips [para].
///
/// Walking to the table (not the paragraph or the whole table) is required:
/// a label can sit inside the table rect and still be clipped by its column,
/// which is what happened to the Pricing RRP header on live v151.
Rect cellRectForParagraph(RenderParagraph para) {
  RenderObject? n = para;
  final boxes = <RenderBox>[];
  RenderTable? table;
  while (n != null) {
    if (n is RenderTable) table = n;
    if (n is RenderBox) boxes.add(n);
    n = n.parent;
  }
  if (table != null) {
    for (final box in boxes) {
      if (box.parent is RenderTable) {
        final origin = box.localToGlobal(Offset.zero);
        return origin & box.size;
      }
    }
  }
  final origin = para.localToGlobal(Offset.zero);
  return origin & para.size;
}

RenderParagraph? _paragraphForText(WidgetTester tester, Element textEl) {
  try {
    return tester.renderObject<RenderParagraph>(
        find.byElementPredicate((x) => x == textEl));
  } catch (_) {
    return null;
  }
}

/// True when every non-space glyph of [expected] is painted inside its
/// DataTable cell (and [scope] if given) in at most 3 lines.
///
/// Uses the real [RenderParagraph] (softWrap + paint boxes). A fresh
/// [TextPainter] defaults to softWrap and would pass the live RRP header,
/// which inherited DataTable's softWrap: false and stayed on one clipped line.
bool labelFullyVisible(
  WidgetTester tester,
  String expected, {
  Finder? scope,
  int minMaxLines = 1,
}) {
  final texts = findTextLoose(expected, scope: scope);
  if (texts.evaluate().isEmpty) return false;
  final textEl = texts.evaluate().first;
  final text = textEl.widget as Text;
  final displayed = text.data ?? '';
  if (stripWordJoiners(displayed) != expected) return false;
  if ((text.maxLines ?? 99) < minMaxLines) return false;
  final para = _paragraphForText(tester, textEl);
  if (para == null) return false;
  if (!para.softWrap) return false;
  if (para.didExceedMaxLines) return false;

  // Horizontal clip is what the live review caught (RRP RTL start, name
  // tail, mid-token codes). Vertical ink often extends 2–4dp past the
  // tight paragraph box because of Cairo leading, so we test against
  // the cell / chip, not the paragraph size.
  const slop = 1.5;
  final cell = cellRectForParagraph(para);
  final scopeBox = scope != null ? tester.getRect(scope) : cell;
  final origin = para.localToGlobal(Offset.zero);

  for (var i = 0; i < displayed.length; i++) {
    if (displayed[i] == kWordJoiner || displayed[i].trim().isEmpty) continue;
    final boxes = para.getBoxesForSelection(
        TextSelection(baseOffset: i, extentOffset: i + 1));
    if (boxes.isEmpty) {
      // Arabic tanween / harakat share a cluster box with the letter.
      if (_clusterMayHaveEmptyBox(displayed, i)) continue;
      return false;
    }
    for (final b in boxes) {
      final global = b.toRect().shift(origin);
      if (global.left < cell.left - slop || global.right > cell.right + slop) {
        return false;
      }
      if (global.left < scopeBox.left - slop ||
          global.right > scopeBox.right + slop) {
        return false;
      }
    }
  }
  return true;
}

/// A short word (no spaces) must stay on a single line and stay fully visible.
bool shortWordUnsplit(WidgetTester tester, String word, {Finder? scope}) {
  final texts = findTextLoose(word, scope: scope);
  if (texts.evaluate().isEmpty) return false;
  for (final e in texts.evaluate()) {
    final data = (e.widget as Text).data;
    if (data == null || stripWordJoiners(data) != word) continue;
    final para = _paragraphForText(tester, e);
    if (para == null) return false;
    final boxes = para.getBoxesForSelection(
        TextSelection(baseOffset: 0, extentOffset: word.length));
    if (boxes.isEmpty) return false;
    final lines = boxes.map((b) => b.toRect().top.round()).toSet();
    if (lines.length > 1) return false;
    if (!labelFullyVisible(tester, word, scope: scope, minMaxLines: 1)) {
      return false;
    }
  }
  return true;
}

/// Hyphenated item codes may wrap at '-' only; tokens stay intact and the
/// full code is visible in at most 3 lines.
bool codeBreaksOnlyAtHyphens(WidgetTester tester, String code,
    {Finder? scope}) {
  final key = find.byKey(ValueKey('dq_item_code_$code'));
  final target =
      scope == null ? key : find.descendant(of: scope, matching: key);
  if (target.evaluate().isNotEmpty) {
    final widget = tester.widget<HyphenatedCodeText>(target);
    if (widget.code != code) return false;
    if (widget.maxLines < 3) return false;
    final tokens = find.descendant(of: target, matching: find.byType(Text));
    if (tokens.evaluate().isEmpty) return false;
    final parts = <String>[];
    final lines = <int>{};
    for (final e in tokens.evaluate()) {
      final text = e.widget as Text;
      final data = text.data ?? '';
      parts.add(data);
      if (text.maxLines != 1) return false;
      final para = _paragraphForText(tester, e);
      if (para == null) return false;
      if (para.didExceedMaxLines) return false;
      final boxes = para.getBoxesForSelection(
          TextSelection(baseOffset: 0, extentOffset: data.length));
      if (boxes.isEmpty) return false;
      final origin = para.localToGlobal(Offset.zero);
      final cell = cellRectForParagraph(para);
      const slop = 1.5;
      for (final b in boxes) {
        final global = b.toRect().shift(origin);
        if (global.left < cell.left - slop ||
            global.right > cell.right + slop) {
          return false;
        }
      }
      lines.add(tester.getTopLeft(find.byWidget(text)).dy.round());
    }
    if (parts.join() != code) return false;
    if (lines.length > 3) return false;
    return true;
  }

  // Fallback for a single Text (with optional word-joiners).
  if (!labelFullyVisible(tester, code, scope: scope)) return false;
  final texts = findTextLoose(code, scope: scope);
  if (texts.evaluate().isEmpty) return false;
  final e = texts.evaluate().first;
  final para = _paragraphForText(tester, e);
  if (para == null) return false;
  final displayed = (e.widget as Text).data ?? code;

  int? prevLine;
  String? prevChar;
  for (var i = 0; i < displayed.length; i++) {
    if (displayed[i] == kWordJoiner) continue;
    final boxes = para.getBoxesForSelection(
        TextSelection(baseOffset: i, extentOffset: i + 1));
    if (boxes.isEmpty) return false;
    final line = boxes.first.toRect().top.round();
    if (prevLine != null && line != prevLine) {
      if (prevChar != '-' && displayed[i] != '-') return false;
    }
    prevLine = line;
    prevChar = displayed[i];
  }
  return true;
}

/// True when [code] is painted on a single line (the live 1280 requirement).
bool codeIsSingleLine(WidgetTester tester, String code, {Finder? scope}) {
  final key = find.byKey(ValueKey('dq_item_code_$code'));
  final target =
      scope == null ? key : find.descendant(of: scope, matching: key);
  if (target.evaluate().isEmpty) return false;
  final texts = find.descendant(of: target, matching: find.byType(Text));
  if (texts.evaluate().isEmpty) return false;
  final tops = <int>{};
  for (final e in texts.evaluate()) {
    final para = _paragraphForText(tester, e);
    if (para == null) return false;
    if (para.didExceedMaxLines) return false;
    final data = (e.widget as Text).data ?? '';
    final boxes = para.getBoxesForSelection(
        TextSelection(baseOffset: 0, extentOffset: data.length));
    if (boxes.isEmpty) return false;
    for (final b in boxes) {
      tops.add(b.toRect().top.round());
    }
  }
  return tops.length == 1;
}

/// Painted line count of [code] from glyph boxes. 1 is required at the
/// live 1280+sidebar shell.
int codePaintedLineCount(WidgetTester tester, String code, {Finder? scope}) {
  final key = find.byKey(ValueKey('dq_item_code_$code'));
  final target =
      scope == null ? key : find.descendant(of: scope, matching: key);
  if (target.evaluate().isEmpty) return 0;
  final texts = find.descendant(of: target, matching: find.byType(Text));
  if (texts.evaluate().isEmpty) return 0;
  final tops = <int>{};
  for (final e in texts.evaluate()) {
    final para = _paragraphForText(tester, e);
    if (para == null) return 0;
    if (para.didExceedMaxLines) {
      return (para.maxLines ?? 0) + 1;
    }
    final data = (e.widget as Text).data ?? '';
    final boxes = para.getBoxesForSelection(
        TextSelection(baseOffset: 0, extentOffset: data.length));
    if (boxes.isEmpty) return 0;
    for (final b in boxes) {
      tops.add(b.toRect().top.round());
    }
  }
  return tops.length;
}

/// True when the code cell is at least [slack] dp wider than the one-line
/// Cairo advance of [code]. v157 used a 154.7dp measurement with almost no
/// slack, so the slightly wider live web Cairo wrapped QA-NOT-IN-MASTER-999.
bool codeColumnHasSlack(WidgetTester tester, String code,
    {double slack = 16.0, Finder? scope}) {
  final key = find.byKey(ValueKey('dq_item_code_$code'));
  final target =
      scope == null ? key : find.descendant(of: scope, matching: key);
  if (target.evaluate().isEmpty) return false;
  final width = tester.getSize(target).width;
  final texts = find.descendant(of: target, matching: find.byType(Text));
  if (texts.evaluate().isEmpty) return false;
  final first = texts.evaluate().first;
  final widget = first.widget as Text;
  final style = widget.style ?? DefaultTextStyle.of(first).style;
  final painter = TextPainter(
    text: TextSpan(text: code, style: style),
    textDirection: TextDirection.ltr,
    maxLines: 1,
  )..layout();
  return width + 0.5 >= painter.width + slack;
}
