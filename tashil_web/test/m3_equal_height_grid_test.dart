import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tashil_web/core/widgets/m3_equal_height_grid.dart';

void main() {
  Future<StateSetter> pump(WidgetTester tester, ValueNotifier<double> tall,
      {TextDirection dir = TextDirection.rtl, int columns = 2}) async {
    late StateSetter set;
    await tester.pumpWidget(Directionality(
      textDirection: dir,
      child: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: 424,
          child: StatefulBuilder(builder: (context, s) {
            set = s;
            return M3EqualHeightGrid(
              columns: columns,
              spacing: 24,
              runSpacing: 16,
              children: [
                const SizedBox(key: ValueKey('a'), height: 50),
                SizedBox(key: const ValueKey('b'), height: tall.value),
                if (columns == 2)
                  const SizedBox(key: ValueKey('c'), height: 10),
              ],
            );
          }),
        ),
      ),
    ));
    return set;
  }

  testWidgets('children share the tallest height; RTL start = right',
      (tester) async {
    final tall = ValueNotifier<double>(120);
    await pump(tester, tall);
    final a = tester.getRect(find.byKey(const ValueKey('a')));
    final b = tester.getRect(find.byKey(const ValueKey('b')));
    final c = tester.getRect(find.byKey(const ValueKey('c')));
    expect(a.height, 120);
    expect(b.height, 120);
    expect(c.height, 120);
    expect(a.width, 200);
    expect(a.left, 224); // first child on the right in RTL
    expect(b.left, 0);
    expect(c.top, 136); // second row: 120 + 16
  });

  testWidgets('re-measures when a child shrinks or grows', (tester) async {
    final tall = ValueNotifier<double>(120);
    final set = await pump(tester, tall, columns: 2);
    set(() => tall.value = 70);
    await tester.pump();
    expect(tester.getSize(find.byKey(const ValueKey('a'))).height, 70);
    set(() => tall.value = 300);
    await tester.pump();
    expect(tester.getSize(find.byKey(const ValueKey('a'))).height, 300);
  });

  testWidgets('flex splits widths (LTR)', (tester) async {
    await tester.pumpWidget(const Directionality(
      textDirection: TextDirection.ltr,
      child: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: 624,
          child: M3EqualHeightGrid(
            columns: 2,
            spacing: 24,
            flex: [5, 7],
            children: [
              SizedBox(key: ValueKey('x'), height: 10),
              SizedBox(key: ValueKey('y'), height: 40),
            ],
          ),
        ),
      ),
    ));
    final x = tester.getRect(find.byKey(const ValueKey('x')));
    final y = tester.getRect(find.byKey(const ValueKey('y')));
    expect(x.width, 250);
    expect(y.width, 350);
    expect(x.left, 0);
    expect(y.left, 274);
    expect(x.height, 40);
  });

  testWidgets('incomplete last row stretches to full width (3+2)',
      (tester) async {
    await tester.pumpWidget(const Directionality(
      textDirection: TextDirection.ltr,
      child: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: 624,
          child: M3EqualHeightGrid(
            columns: 3,
            spacing: 24,
            children: [
              SizedBox(key: ValueKey('a'), height: 40),
              SizedBox(key: ValueKey('b'), height: 40),
              SizedBox(key: ValueKey('c'), height: 40),
              SizedBox(key: ValueKey('d'), height: 40),
              SizedBox(key: ValueKey('e'), height: 40),
            ],
          ),
        ),
      ),
    ));
    final a = tester.getRect(find.byKey(const ValueKey('a')));
    final d = tester.getRect(find.byKey(const ValueKey('d')));
    final e = tester.getRect(find.byKey(const ValueKey('e')));
    // Full row: (624 - 2×24) / 3 = 192.
    expect(a.width, closeTo(192.0, 0.5));
    // Stretched last row: (624 - 24) / 2 = 300 — no empty third slot.
    expect(d.width, closeTo(300.0, 0.5));
    expect(e.width, closeTo(300.0, 0.5));
    expect(d.left, 0);
    expect(e.left, closeTo(324.0, 0.5));
    expect(d.top, closeTo(a.bottom + 0, 0.5)); // runSpacing default 0
  });
}
