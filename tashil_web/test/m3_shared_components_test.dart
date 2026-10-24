import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:tashil_web/core/theme/app_theme.dart';
import 'package:tashil_web/core/widgets/app_icons.dart';
import 'package:tashil_web/core/widgets/kpi_card.dart';
import 'package:tashil_web/core/widgets/m3_button.dart';
import 'package:tashil_web/core/widgets/m3_card.dart';
import 'package:tashil_web/core/widgets/m3_data_table.dart';
import 'package:tashil_web/core/widgets/m3_dropdown.dart';
import 'package:tashil_web/core/widgets/m3_filter_chip_group.dart';
import 'package:tashil_web/core/widgets/m3_states.dart';
import 'package:tashil_web/core/widgets/m3_text_field.dart';

Widget _wrap(Widget child) => MaterialApp(
      theme: AppTheme.light(),
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(body: SingleChildScrollView(child: child)),
      ),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = false;

  testWidgets('M3Button variants map to M3 button types', (tester) async {
    await tester.pumpWidget(_wrap(Column(children: [
      M3Button.primary(label: 'p', onPressed: () {}),
      M3Button.tonal(label: 't', onPressed: () {}, icon: AppIcons.refresh),
      M3Button.outlined(label: 'o', onPressed: () {}),
      M3Button.text(label: 'x', onPressed: () {}),
      M3Button.primary(label: 'l', onPressed: () {}, isLoading: true),
    ])));
    expect(find.byType(FilledButton), findsNWidgets(3));
    expect(find.byType(OutlinedButton), findsOneWidget);
    expect(find.byType(TextButton), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('M3Dropdown uses DropdownMenu and reports selection', (tester) async {
    String? picked = 'x';
    await tester.pumpWidget(_wrap(M3Dropdown<String?>(
      key: const ValueKey('dd'),
      value: null,
      options: const [
        M3DropdownOption(null, 'All'),
        M3DropdownOption('a', 'Alpha'),
      ],
      onChanged: (v) => picked = v,
    )));
    expect(find.byType(DropdownMenu<String?>), findsOneWidget);
    expect(find.byType(DropdownButton<String?>), findsNothing);
    await tester.tap(find.byKey(const ValueKey('dd')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Alpha').last);
    await tester.pumpAndSettle();
    expect(picked, 'a');
  });

  testWidgets('Text field, cards, KPI card, chips, table, states render', (tester) async {
    Set<String> sel = {'a'};
    await tester.pumpWidget(_wrap(Column(children: [
      const M3TextField(label: 'بحث', leadingIcon: AppIcons.search),
      const M3Card.filled(child: Text('filled')),
      const M3Card.outlined(child: Text('outlined')),
      const KpiCard(
        title: 'عنوان',
        titleEn: 'Title',
        value: '10',
        subtitle: 'sub',
        icon: AppIcons.money,
        growthPct: 1,
        badgeLabel: '+1%',
        isPositive: true,
      ),
      M3FilterChipGroup<String>(
        options: const [M3ChipOption('a', 'A'), M3ChipOption('b', 'B')],
        selected: sel,
        onChanged: (v) => sel = v,
      ),
      const M3DataTable(
        columns: [DataColumn(label: Text('c1'))],
        rows: [DataRow(cells: [DataCell(Text('r1'))])],
      ),
      const SizedBox(height: 200, child: M3EmptyState(title: 'لا توجد بيانات')),
      const SizedBox(height: 120, child: M3LoadingState(linear: true)),
      SizedBox(height: 220, child: M3ErrorState(title: 'خطأ', onRetry: () {})),
      M3ErrorBanner(message: 'm', onRetry: () {}),
    ])));
    expect(find.byType(TextFormField), findsOneWidget);
    expect(find.byType(Card), findsNWidgets(3));
    expect(find.byType(FilterChip), findsNWidgets(2));
    expect(find.byType(DataTable), findsOneWidget);
    expect(find.byType(MaterialBanner), findsOneWidget);
    expect(find.text('لا توجد بيانات'), findsOneWidget);
    await tester.tap(find.text('B'));
    expect(sel, {'a', 'b'});
    expect(tester.takeException(), isNull);
  });
}
