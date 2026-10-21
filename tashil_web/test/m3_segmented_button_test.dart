import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tashil_web/core/theme/app_theme.dart';
import 'package:tashil_web/core/widgets/m3_segmented_button_group.dart';

void main() {
  testWidgets('M3SegmentedButtonGroup renders segments and emits changes', (WidgetTester tester) async {
    String selectedValue = 'MTD';

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              return M3SegmentedButtonGroup<String>(
                segments: const [
                  M3SegmentItem(value: 'TODAY', label: 'اليوم'),
                  M3SegmentItem(value: 'WEEKLY', label: 'أسبوعي'),
                  M3SegmentItem(value: 'MTD', label: 'الشهر الحالي'),
                ],
                selectedValue: selectedValue,
                onSelectionChanged: (val) {
                  setState(() => selectedValue = val);
                },
              );
            },
          ),
        ),
      ),
    );

    // Verify all 3 segments are rendered
    expect(find.text('اليوم'), findsOneWidget);
    expect(find.text('أسبوعي'), findsOneWidget);
    expect(find.text('الشهر الحالي'), findsOneWidget);

    // Tap 'أسبوعي'
    await tester.tap(find.text('أسبوعي'));
    await tester.pumpAndSettle();

    expect(selectedValue, 'WEEKLY');
  });
}
