// Sell-In v2: Arabic row labels (no raw 'Barcode' / 'current_list'), Arabic
// semantics labels, semantic status chips in the shared 8dp chip shape,
// Sell-Out v1 table density, and wide tables whose main columns fit 1030dp
// (1280 minus the sidebar) with a pinned key column.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tashil_web/core/network/api_client.dart';
import 'package:tashil_web/core/theme/app_theme.dart';
import 'package:tashil_web/core/widgets/m3_chip_surface.dart';
import 'package:tashil_web/features/sell_out_analytics/presentation/screens/sell_in_explorer_screen.dart';

import 'support/real_fonts.dart';

const _viewport = 1280.0 - 250.0;

final _records = [
  for (var i = 0; i < 4; i++)
    {
      'record_id': 'r$i',
      'batch_id': 'b',
      'source_filename': 'in26a.xlsx',
      'tenant_id': 'tenant-adeco',
      'retailer_chain': 'fathalla',
      'year': 2026,
      'month_num': 10,
      'month_ar': 'أكتوبر',
      'governorate': 'الإسكندرية',
      'item_code': '10${i}55',
      'barcode': '62230000${i}1234',
      'brand': 'فيبا',
      'sub_category': 'منظفات',
      'item_name': i == 0
          ? 'فيبا 4 كجم منظف متعدد الأغراض ليمون برائحة منعشة جدا للأرضيات والمطابخ'
          : 'كلوريل $i كجم',
      'sales_rep': 'مندوب',
      'units_per_carton': 12,
      'net_qty_cases': 120.0 + i,
      'net_value_egp': 182500.0 + i * 41230,
      'gross_value_incl_vat_egp': (182500.0 + i * 41230) * 1.14,
      'vat_amount_egp': (182500.0 + i * 41230) * 0.14,
      'weight_tons': 1.25,
      'official_carton_excl_vat_egp': 1650.0,
      'actual_case_price_excl_egp': 1650.0,
      'effective_discount_pct': 0.0,
      'pricing_wave_status': i == 3 ? 'some_internal_key' : 'current_list',
    },
];

final _cpfr = {
  'monthly_reconciliation': [
    for (var m = 1; m <= 10; m++)
      {
        'year': 2026,
        'month_num': m,
        'has_actual_sell_out': true,
        'sell_in_units': 140000 + m * 913,
        'sell_out_units': 130000 + m * 791,
      },
  ],
  'inventory_and_po_items': [
    for (var i = 0; i < 3; i++)
      {
        'barcode': 'b$i',
        'item_code': 'I$i',
        'sku_name': i == 0
            ? 'فيبا 4 كجم منظف متعدد الأغراض ليمون برائحة منعشة جدا للأرضيات'
            : 'كلوريل $i',
        'sell_in_units': 40000 - i * 2500,
        'sell_out_units': 30000 - i * 1500,
        'estimated_stock_units': 9000 - i * 500,
        'stock_status': ['urgent_replenishment', 'overstock', 'optimal'][i],
        'stock_status_ar': ['طلب توريد عاجل', 'تكدس مخزني', 'رصيد آمن'][i],
      },
  ],
};

MockClient _client() => MockClient((req) async {
      Object? body;
      if (req.url.path.endsWith('/api/v1/analytics/sell-in-records')) {
        body = {
          'records': _records,
          'total_count': _records.length,
          'total_value_egp': 1.0,
          'total_cases': 1.0,
          'total_weight_tons': 1.0,
          'total_expected_egp': 0.0,
        };
      } else if (req.url.path.endsWith('/api/v1/analytics/cpfr')) {
        body = _cpfr;
      } else if (req.url.path.endsWith('/api/v1/ingest/archive')) {
        body = {'tenant_id': 'tenant-adeco', 'total_count': 0, 'files': []};
      }
      if (body == null) return http.Response('not found', 404);
      return http.Response.bytes(utf8.encode(jsonEncode(body)), 200,
          headers: {'content-type': 'application/json; charset=utf-8'});
    });

Future<void> _pump(WidgetTester tester,
    {int tab = 0, double width = _viewport}) async {
  tester.view.physicalSize = Size(width, 3600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(MaterialApp(
    theme: AppTheme.light(),
    home: Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
          body: SellInExplorerScreen(
              apiClient: ApiClient(tenantId: 'tenant-adeco'))),
    ),
  ));
  await tester.pumpAndSettle();
  if (tab == 1) {
    await tester
        .tap(find.textContaining(RegExp('^المخزون وإعادة الطلب')).first);
    await tester.pumpAndSettle();
  }
}

Iterable<String> _texts(WidgetTester t) =>
    find.byType(Text).evaluate().map((e) =>
        (e.widget as Text).data ??
        (e.widget as Text).textSpan?.toPlainText() ??
        '');

void _expectInViewport(WidgetTester tester, Finder f, String what) {
  expect(f, findsWidgets, reason: what);
  final r = tester.getRect(f.first);
  expect(r.left, greaterThanOrEqualTo(-0.5), reason: '$what $r');
  expect(r.right, lessThanOrEqualTo(_viewport + 0.5), reason: '$what $r');
}

void main() {
  setUpAll(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    await loadRealCairoFont();
  });

  testWidgets('1. data rows: Arabic barcode label, no raw internal keys',
      (tester) async {
    await http.runWithClient(() async {
      await _pump(tester);
      final texts = _texts(tester).toList();
      expect(texts.where((t) => t.contains('Barcode')), isEmpty);
      expect(
          texts.where((t) =>
              t.contains('current_list') || t.contains('some_internal_key')),
          isEmpty);
      // Spec: no visible «الباركود» text label — icon semanticLabel instead.
      expect(texts.where((t) => t.startsWith('الباركود: ')), isEmpty);
      expect(
        tester.widgetList<Icon>(find.byType(Icon)).any(
          (i) => i.icon == Icons.qr_code_2_rounded && i.semanticLabel == 'الباركود'),
        isTrue,
      );
      expect(find.text('سعر القائمة الحالي'), findsWidgets);
    }, _client);
  });

  test('2. accessibility labels on Sell-In / Sell-Out buttons are Arabic', () {
    for (final f in [
      'lib/features/sell_out_analytics/presentation/screens/sell_in_explorer_screen.dart',
      'lib/features/sell_out_analytics/presentation/screens/sell_out_explorer_screen.dart',
    ]) {
      final src = File(f).readAsStringSync();
      final english = RegExp(r"\blabel: '([A-Za-z][A-Za-z ]+)'")
          .allMatches(src)
          .map((m) => m[1])
          .toList();
      expect(english, isEmpty, reason: '$f: $english');
    }
  });

  testWidgets('2b. upload button semantics label is Arabic', (tester) async {
    final handle = tester.ensureSemantics();
    await http.runWithClient(() async {
      await _pump(tester);
      await tester.tap(find.textContaining(RegExp('^الملفات المرفوعة')).first);
      await tester.pumpAndSettle();
      expect(find.bySemanticsLabel(RegExp('رفع ملف Sell-In')), findsWidgets);
      expect(find.bySemanticsLabel(RegExp('Upload Sell-In')), findsNothing);
    }, _client);
    handle.dispose();
  });

  testWidgets(
      '3. reorder status = shared 8dp chip with semantic container colours',
      (tester) async {
    await http.runWithClient(() async {
      await _pump(tester, tab: 1);
      final cs = Theme.of(tester.element(find.byType(SellInExplorerScreen)))
          .colorScheme;
      final chips = find.byKey(const ValueKey('sellin_sku_status'));
      expect(chips, findsNWidgets(3));
      final colors =
          tester.widgetList<M3ChipSurface>(chips).map((c) => c.color).toList();
      expect(colors,
          [cs.errorContainer, cs.tertiaryContainer, cs.surfaceContainerHigh]);
      for (final e in chips.evaluate()) {
        expect(tester.getSize(find.byWidget(e.widget)).height, 32.0);
      }
      // Monthly status uses the same chip.
      expect(find.byKey(const ValueKey('sellin_monthly_status')), findsWidgets);
      for (final c in tester.widgetList<M3ChipSurface>(
          find.byKey(const ValueKey('sellin_monthly_status')))) {
        expect(
            [cs.errorContainer, cs.tertiaryContainer, cs.surfaceContainerHigh],
            contains(c.color));
      }
    }, _client);
  });

  testWidgets(
      '4. density: titleSmall name + icon code/barcode lines, ~64dp rows',
      (tester) async {
    await http.runWithClient(() async {
      await _pump(tester);
      final cs = Theme.of(tester.element(find.byType(SellInExplorerScreen)))
          .colorScheme;
      final names = find.byKey(const ValueKey('sellin_record_item_name'));
      // Client page shows 20 rows; assert a sample of visible names.
      expect(names.evaluate().length, greaterThanOrEqualTo(4));
      for (final e in names.evaluate().take(4)) {
        final t = e.widget as Text;
        expect(t.maxLines, 1);
        final style = DefaultTextStyle.of(e).style.merge(t.style);
        expect(style.fontSize, 14.0); // titleSmall
        final tip =
            find.ancestor(of: find.byWidget(t), matching: find.byType(Tooltip));
        expect(tester.widget<Tooltip>(tip.first).message, t.data);
      }
      final barcodeIcons = tester
          .widgetList<Icon>(find.byType(Icon))
          .where((i) =>
              i.icon == Icons.qr_code_2_rounded && i.semanticLabel == 'الباركود')
          .toList();
      expect(barcodeIcons, isNotEmpty);
      expect(barcodeIcons.first.size, 16.0);
      expect(barcodeIcons.first.color, cs.onSurfaceVariant);
      expect(
          tester
              .getSize(find.byKey(const ValueKey('sellin_record_row_0')))
              .height,
          greaterThanOrEqualTo(64.0));
      await tester
          .tap(find.textContaining(RegExp('^المخزون وإعادة الطلب')).first);
      await tester.pumpAndSettle();
      final sku = find.byKey(const ValueKey('sellin_sku_name'));
      expect(sku, findsNWidgets(3));
      for (final e in sku.evaluate()) {
        final t = e.widget as Text;
        expect(t.maxLines, 3);
        expect(DefaultTextStyle.of(e).style.merge(t.style).fontSize, 14.0);
      }
    }, _client);
  });

  testWidgets('5a. records: pinned item column + main columns fit 1030dp',
      (tester) async {
    await http.runWithClient(() async {
      await _pump(tester);
      _expectInViewport(
          tester,
          find.byKey(const ValueKey('sellin_records_pinned_item')),
          'pinned item');
      for (final h in [
        'الفترة',
        'السلسلة / الفرع',
        'كرتونة / وحدة',
        'صافي Sell-In',
        'الإجمالي'
      ]) {
        _expectInViewport(tester, find.text(h), h);
      }
      // Compact money with the exact value in a tooltip.
      final net = tester
          .widget<Text>(find.byKey(const ValueKey('sellin_record_net')).first);
      expect(net.data, contains('K'));
      // Item cell tops sit inside the row (8dp vertical cell padding).
      for (var i = 0; i < 4; i++) {
        final a = tester.getRect(find.byKey(ValueKey('sellin_record_item_$i')));
        final b = tester.getRect(find.byKey(ValueKey('sellin_record_row_$i')));
        expect(a.top, greaterThanOrEqualTo(b.top - 0.5));
        expect(a.top - b.top, lessThan(12.0));
      }
    }, _client);
  });

  testWidgets(
      '5b. stock tab: monthly table fits, SKU key column pinned, main columns fit',
      (tester) async {
    await http.runWithClient(() async {
      await _pump(tester, tab: 1);
      for (final h in [
        'الشهر / السنة',
        'رصيد أول الشهر',
        'رصيد آخر الشهر',
        'نسبة التصريف',
        'الحالة'
      ]) {
        _expectInViewport(tester, find.text(h), h);
      }
      _expectInViewport(tester,
          find.byKey(const ValueKey('sellin_sku_pinned_column')), 'sku pinned');
      for (final h in ['Sell-In', 'Sell-Out', 'المخزون', 'أيام التغطية']) {
        _expectInViewport(
            tester,
            find.descendant(
                of: find.byKey(const ValueKey('sellin_sku_table')),
                matching: find.text(h)),
            h);
      }
      _expectInViewport(
          tester, find.byKey(const ValueKey('sellin_sku_status')), 'status');
      // Pinned SKU rows align with the table rows.
      final names =
          find.byKey(const ValueKey('sellin_sku_name')).evaluate().toList();
      final chips =
          find.byKey(const ValueKey('sellin_sku_status')).evaluate().toList();
      for (var i = 0; i < names.length; i++) {
        final ny = tester.getCenter(find.byWidget(names[i].widget)).dy;
        final cy = tester.getCenter(find.byWidget(chips[i].widget)).dy;
        expect((ny - cy).abs(), lessThan(12.0), reason: 'row $i');
      }
    }, _client);
  });
}
