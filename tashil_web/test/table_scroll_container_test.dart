import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tashil_web/core/widgets/table_scroll_container.dart';

void main() {
  testWidgets(
      'TableScrollContainer renders navigation buttons and scrolls in RTL',
      (tester) async {
    final controller = ScrollController();

    await tester.pumpWidget(
      MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(
            body: Center(
              child: SizedBox(
                width: 600,
                // 400 was too short once the compact header (<640) stacked
                // the title above the RTL nav and the 13dp scrollbar gutter
                // was reserved under the last row.
                height: 480,
                child: TableScrollContainer(
                  controller: controller,
                  title: 'جدول تجريبي',
                  showSwipeHint: true,
                  child: SizedBox(
                    width: 1500,
                    height: 300,
                    child: Row(
                      children: List.generate(
                        10,
                        (index) => Container(
                          width: 150,
                          color: index.isEven ? Colors.blue : Colors.amber,
                          child: Center(child: Text('عمود $index')),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    // Verify title and hint
    expect(find.text('جدول تجريبي'), findsOneWidget);
    expect(find.text('اسحب أو تحرك:'), findsOneWidget);
    expect(find.text('يمين'), findsOneWidget);
    expect(find.text('شمال'), findsOneWidget);

    // Verify Scrollbar exists
    expect(find.byType(Scrollbar), findsOneWidget);

    // In RTL, initial offset is 0.0. Tapping "شمال" scrolls towards remaining columns (positive offset).
    final initialOffset = controller.offset;
    await tester.tap(find.text('شمال'));
    await tester.pumpAndSettle();
    expect(controller.offset, greaterThan(initialOffset));

    // Tapping "يمين" scrolls back towards starting columns (smaller offset).
    await tester.tap(find.text('يمين'));
    await tester.pumpAndSettle();
    expect(controller.offset, lessThanOrEqualTo(initialOffset + 10));

    controller.dispose();
  });

  testWidgets(
      'TableScrollContainer handles narrow mobile width without overflow',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(
            body: Center(
              child: SizedBox(
                width: 320,
                height: 400,
                child: TableScrollContainer(
                  title: 'جدول شاشة صغيرة',
                  showSwipeHint: true,
                  child: SizedBox(
                    width: 1000,
                    height: 200,
                    child: Container(color: Colors.red),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('جدول شاشة صغيرة'), findsOneWidget);
    expect(find.text('يمين'), findsOneWidget);
    expect(find.text('شمال'), findsOneWidget);
    expect(find.byType(Scrollbar), findsOneWidget);
  });
}
