import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tashil_web/core/widgets/table_scroll_container.dart';

void main() {
  testWidgets('TableScrollContainer renders navigation buttons and scrolls in RTL', (tester) async {
    final controller = ScrollController();

    await tester.pumpWidget(
      MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(
            body: Center(
              child: SizedBox(
                width: 600,
                height: 400,
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

  testWidgets('TableScrollContainer handles narrow mobile width without overflow', (tester) async {
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
    expect(tester.takeException(), isNull);
  });

  testWidgets('wide RTL table keeps viewport width and can scroll to trailing Net column',
      (tester) async {
    final controller = ScrollController();
    const tableWidth = 1600.0;
    const viewportWidth = 720.0;

    await tester.pumpWidget(
      MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(
            body: Center(
              child: SizedBox(
                width: viewportWidth,
                height: 360,
                child: TableScrollContainer(
                  key: const ValueKey('sell_in_like_scroll'),
                  controller: controller,
                  showSwipeHint: true,
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.black12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: SizedBox(
                    width: tableWidth,
                    height: 240,
                    child: const Row(
                      children: [
                        SizedBox(width: 200, child: Text('الفترة')),
                        SizedBox(width: 280, child: Text('السلسلة')),
                        SizedBox(width: 320, child: Text('الصنف')),
                        SizedBox(width: 200, child: Text('سعر الكرتونة')),
                        SizedBox(
                          width: 200,
                          child: Text('صافي Sell-In', key: ValueKey('net_column')),
                        ),
                        SizedBox(width: 200, child: Text('الإجمالي')),
                        SizedBox(width: 200, child: Text('الملف')),
                      ],
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

    expect(controller.hasClients, isTrue);
    // Scrollbar track may shave a couple of px off the viewport.
    expect(controller.position.viewportDimension, lessThanOrEqualTo(viewportWidth));
    expect(controller.position.viewportDimension, greaterThan(viewportWidth - 24));
    expect(controller.position.maxScrollExtent, greaterThan(tableWidth - viewportWidth - 24));

    // Net starts off-screen; scrolling to max extent brings trailing columns into view.
    expect(find.byKey(const ValueKey('net_column')).hitTestable(), findsNothing);

    // jumpTo avoids BouncingScrollPhysics settle hangs under AlwaysScrollable.
    controller.jumpTo(controller.position.maxScrollExtent);
    await tester.pump();

    expect(controller.offset, greaterThan(0));
    expect(find.byKey(const ValueKey('net_column')).hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);

    controller.dispose();
  });

  testWidgets('Pricing-like DataTable scrolls horizontally inside a bounded card', (tester) async {
    final controller = ScrollController();
    const viewportWidth = 640.0;

    await tester.pumpWidget(
      MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(
            body: Center(
              child: SizedBox(
                width: viewportWidth,
                height: 420,
                child: Card(
                  clipBehavior: Clip.antiAlias,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: TableScrollContainer(
                      key: const ValueKey('pricing_like_scroll'),
                      controller: controller,
                      showSwipeHint: true,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(minWidth: viewportWidth),
                        child: DataTable(
                          columns: const [
                            DataColumn(label: Text('الصنف والباركود')),
                            DataColumn(label: Text('السلسلة والفرع')),
                            DataColumn(label: Text('السعر الفعلي')),
                            DataColumn(label: Text('السعر الموصى به (RRP)')),
                            DataColumn(label: Text('الفارق السعري (Delta)')),
                            DataColumn(label: Text('حالة العرض والأثر البيعي')),
                          ],
                          rows: List.generate(
                            3,
                            (i) => DataRow(
                              cells: [
                                DataCell(Text('SKU-$i • GTIN 62240000000$i')),
                                DataCell(Text('فرع رقم $i — فتح الله')),
                                DataCell(Text('${20 + i}.50 ج.م')),
                                DataCell(Text('${22 + i}.00 ج.م')),
                                DataCell(Text('-${1 + i}.5%')),
                                DataCell(Text('عرض -$i')),
                              ],
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
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('اسحب أو تحرك:'), findsOneWidget);
    expect(controller.hasClients, isTrue);
    expect(controller.position.viewportDimension, lessThanOrEqualTo(viewportWidth));
    expect(controller.position.maxScrollExtent, greaterThan(0));
    expect(tester.takeException(), isNull);

    final before = controller.offset;
    await tester.tap(find.text('شمال'));
    await tester.pumpAndSettle();
    expect(controller.offset, greaterThan(before));

    controller.dispose();
  });

  testWidgets('scroll viewport does not expand page width past parent constraint', (tester) async {
    final controller = ScrollController();

    await tester.pumpWidget(
      MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(
            body: SingleChildScrollView(
              child: Center(
                child: SizedBox(
                  width: 500,
                  child: TableScrollContainer(
                    controller: controller,
                    child: SizedBox(
                      width: 1400,
                      height: 120,
                      child: Row(
                        children: List.generate(
                          8,
                          (i) => SizedBox(width: 175, child: Text('col-$i')),
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

    final scrollableSize = tester.getSize(find.byType(SingleChildScrollView).first);
    // Outer vertical page scroll view should stay at the scaffold width, not 1400.
    expect(scrollableSize.width, lessThan(900));
    expect(controller.position.viewportDimension, lessThanOrEqualTo(500));
    expect(controller.position.viewportDimension, greaterThan(476));
    expect(controller.position.maxScrollExtent, greaterThan(800));
    expect(tester.takeException(), isNull);

    controller.dispose();
  });
}
