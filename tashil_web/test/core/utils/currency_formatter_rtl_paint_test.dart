import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tashil_web/core/utils/currency_formatter.dart';
import 'package:tashil_web/core/widgets/atomic_numeric_text.dart';

void main() {
  Future<void> pumpRtlAmount(
    WidgetTester tester,
    String text, {
    double width = 240,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(
            body: Center(
              child: SizedBox(
                width: width,
                child: Text(
                  text,
                  textAlign: TextAlign.center,
                  softWrap: true,
                  maxLines: 3,
                  textDirection: TextDirection.rtl,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  RenderParagraph paragraphOf(WidgetTester tester, String text) {
    final el = find
        .byWidgetPredicate((w) => w is Text && w.data == text)
        .evaluate()
        .single;
    return tester.renderObject<RenderParagraph>(
        find.byElementPredicate((x) => x == el));
  }

  void expectMinusLeftOfDigits(RenderParagraph para, String text) {
    final minusIdx = text.indexOf('\u2212');
    final digitIdx = text.indexOf(RegExp(r'\d'));
    expect(minusIdx, greaterThanOrEqualTo(0),
        reason: 'formatted text should contain U+2212: $text');
    expect(digitIdx, greaterThan(minusIdx),
        reason: 'digits should follow the minus in the string: $text');

    final minusBoxes = para.getBoxesForSelection(
      TextSelection(baseOffset: minusIdx, extentOffset: minusIdx + 1),
    );
    final digitBoxes = para.getBoxesForSelection(
      TextSelection(baseOffset: digitIdx, extentOffset: digitIdx + 1),
    );
    expect(minusBoxes, isNotEmpty, reason: 'minus glyph was not painted');
    expect(digitBoxes, isNotEmpty, reason: 'digit glyph was not painted');
    final minus = minusBoxes.first.toRect();
    final digit = digitBoxes.first.toRect();
    expect(minus.left, lessThan(digit.left),
        reason: 'minus should sit to the left of the first digit '
            '(minus=${minus.left.toStringAsFixed(1)}, '
            'digit=${digit.left.toStringAsFixed(1)}) in "$text"');
  }

  group('negative money paints minus on the left in RTL', () {
    for (final amount in [-847.0, -238.0, -118.0]) {
      testWidgets('formatCompactEGP($amount) at comfortable width',
          (tester) async {
        final text = CurrencyFormatter.formatCompactEGP(amount);
        await pumpRtlAmount(tester, text);
        expectMinusLeftOfDigits(paragraphOf(tester, text), text);
      });
    }

    testWidgets(
        'formatCompactEGP(-847) keeps minus on the left when currency wraps',
        (tester) async {
      final text = CurrencyFormatter.formatCompactEGP(-847);
      // Narrow like the Errors «التأثير» column (~42–72dp). The amount
      // wraps onto two lines ("−847" / "ج.م") but the minus must stay
      // attached to the left of 847.
      await pumpRtlAmount(tester, text, width: 48);
      expectMinusLeftOfDigits(paragraphOf(tester, text), text);
    });

    testWidgets('formatEGP(-14,500) paints minus on the left', (tester) async {
      final text = CurrencyFormatter.formatEGP(-14500);
      await pumpRtlAmount(tester, text);
      expectMinusLeftOfDigits(paragraphOf(tester, text), text);
    });

    testWidgets('formatNumber(-125,400) paints minus on the left',
        (tester) async {
      final text = CurrencyFormatter.formatNumber(-125400);
      await pumpRtlAmount(tester, text);
      expectMinusLeftOfDigits(paragraphOf(tester, text), text);
    });
  });

  testWidgets(
      'compact K/M suffix stays on the same line as the number when ج.م wraps',
      (tester) async {
    final text = CurrencyFormatter.formatCompactEGP(401000);
    expect(text.contains('401.0K'), isFalse);
    await tester.pumpWidget(MaterialApp(
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: Center(
          child: AtomicNumericText(
            text,
            maxWidth: 48,
            style: const TextStyle(fontSize: 14),
          ),
        ),
      ),
    ));
    await tester.pump();
    final (prefix, suffix) = AtomicNumericText.splitCurrency(text);
    expect(prefix.contains('401.0'), isTrue);
    expect(prefix.contains('K'), isTrue);
    expect(prefix.contains('ج.م'), isFalse);
    expect(suffix, 'ج.م');
    expect(find.text(prefix), findsOneWidget);
    expect(find.text('ج.م'), findsOneWidget);
    final para = tester.renderObject<RenderParagraph>(find.text(prefix));
    final boxes = para.getBoxesForSelection(
      TextSelection(baseOffset: 0, extentOffset: prefix.length),
    );
    expect({for (final b in boxes) b.toRect().top.round()}, hasLength(1),
        reason: 'number+K suffix must stay on one line');
    expect(find.textContaining('401.0K'), findsNothing);
  });
}
