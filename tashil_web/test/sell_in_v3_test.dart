// Sell-In v3 (secondary text readable, wraps, pinned rows aligned to the end).
// Based on the v2 fixture: Sell-In v2: Arabic row labels (no raw 'Barcode' / 'current_list'), Arabic
// semantics labels, semantic status chips in the shared 8dp chip shape,
// Sell-Out v1 table density, and wide tables whose main columns fit 1030dp
// (1280 minus the sidebar) with a pinned key column.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tashil_web/core/network/api_client.dart';
import 'package:tashil_web/core/theme/app_theme.dart';
import 'package:tashil_web/core/widgets/m3_chip_surface.dart';
import 'package:tashil_web/core/widgets/table_scroll_container.dart';
import 'package:tashil_web/features/sell_out_analytics/presentation/screens/sell_in_explorer_screen.dart';

import 'support/real_fonts.dart';

const _viewport = 1280.0 - 250.0;

final _records = [
  for (var i = 0; i < 40; i++)
    {
      'record_id': 'r$i',
      'batch_id': 'b',
      'source_filename': 'in26a.xlsx',
      'tenant_id': 'tenant-adeco',
      'retailer_chain': 'fathalla',
      'year': 2026,
      'month_num': 10,
      'month_ar': 'أكتوبر',
      'governorate': 'مدينة السادس من أكتوبر - الحي المتميز الجديد',
      'item_code': '10${i}55',
      'barcode': '62230000${i}1234',
      'brand': 'فيبا',
      'sub_category': 'منظفات الأرضيات والأسطح متعددة الاستخدام',
      'item_name': i == 0
          ? 'فيبا 4 كجم منظف متعدد الأغراض ليمون برائحة منعشة جدا للأرضيات والمطابخ والحمامات عبوة توفير'
          : 'كلوريل $i كجم',
      'sales_rep': 'مندوب المبيعات محمد عبد الرحمن',
      'units_per_carton': 12,
      'net_qty_cases': 120.0 + i,
      'net_value_egp': 182500.0 + i * 41230,
      'gross_value_incl_vat_egp': (182500.0 + i * 41230) * 1.14,
      'vat_amount_egp': (182500.0 + i * 41230) * 0.14,
      'weight_tons': 1.25,
      'official_carton_excl_vat_egp': 1651234.5,
      'actual_case_price_excl_egp': 1520987.25,
      'effective_discount_pct': i.isEven ? 0.0 : 7.9,
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
        'brand': 'فيبا',
        'governorate': 'مدينة السادس من أكتوبر - الحي المتميز الجديد',
        'official_carton_excl_vat_egp': 1651234.5,
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

/// Every text in the Sell-In tables is >= 12px, secondary text may wrap to 2
/// lines, and anything still clipped has a tooltip with the full text.
List<String> _textIssues(WidgetTester tester, Finder scope) {
  final out = <String>[];
  for (final e
      in find.descendant(of: scope, matching: find.byType(Text)).evaluate()) {
    final t = e.widget as Text;
    final data = t.data ?? t.textSpan?.toPlainText() ?? '';
    final style = DefaultTextStyle.of(e).style.merge(t.style);
    final size = style.fontSize ?? 14.0;
    if (size < 12.0) out.add('font $size "$data"');
    final inChip = find
        .ancestor(of: find.byWidget(t), matching: find.byType(M3ChipSurface))
        .evaluate()
        .isNotEmpty;
    // Secondary text (12-13px) wraps to 2 lines instead of a 1-line '…'.
    if (!inChip && size < 14.0 && t.maxLines == 1) {
      out.add('1-line secondary "$data"');
    }
    final rich =
        find.descendant(of: find.byWidget(t), matching: find.byType(RichText));
    if (rich.evaluate().isEmpty) continue;
    final p = tester.renderObject<RenderParagraph>(rich.first);
    if (p.didExceedMaxLines) {
      final tip =
          find.ancestor(of: find.byWidget(t), matching: find.byType(Tooltip));
      if (tip.evaluate().isEmpty) out.add('clipped without tooltip "$data"');
    }
  }
  return out;
}

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

  testWidgets(
      'A1. records: secondary text >= 12px, wraps, tooltip if clipped; main columns fit',
      (tester) async {
    await http.runWithClient(() async {
      await _pump(tester);
      expect(tester.takeException(), isNull);
      final issues = <String>{
        ..._textIssues(
            tester, find.byKey(const ValueKey('sellin_records_table'))),
        ..._textIssues(
            tester, find.byKey(const ValueKey('sellin_records_pinned_item'))),
      }.toList()
        ..sort();
      expect(issues, isEmpty, reason: issues.join('\n'));
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
    }, _client);
  });

  testWidgets(
      'A2. records: item cell stays aligned with its row on each page',
      (tester) async {
    await http.runWithClient(() async {
      await _pump(tester);
      // Page 1: first 20 rows.
      for (final i in [0, 5, 19]) {
        final a = tester.getRect(find.byKey(ValueKey('sellin_record_item_$i')));
        final b = tester.getRect(find.byKey(ValueKey('sellin_record_row_$i')));
        expect((a.top - b.top).abs(), lessThan(1.0), reason: 'page1 row $i');
      }
      // Jump to last page (rows 20–39 with 40 fixtures / 20 per page).
      await tester.ensureVisible(
          find.byKey(const ValueKey('sellin_records_last_btn')));
      await tester.tap(find.byKey(const ValueKey('sellin_records_last_btn')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('sellin_record_row_39')), findsOneWidget);
      final a =
          tester.getRect(find.byKey(const ValueKey('sellin_record_item_39')));
      final b =
          tester.getRect(find.byKey(const ValueKey('sellin_record_row_39')));
      expect((a.top - b.top).abs(), lessThan(1.0), reason: '$a vs $b');
    }, _client);
  });

  testWidgets(
      'A3. stock SKU table: secondary text readable and wrapped; main columns fit',
      (tester) async {
    await http.runWithClient(() async {
      await _pump(tester, tab: 1);
      expect(tester.takeException(), isNull);
      final issues = <String>{
        ..._textIssues(tester, find.byKey(const ValueKey('sellin_sku_table'))),
        ..._textIssues(
            tester, find.byKey(const ValueKey('sellin_sku_pinned_column'))),
        ..._textIssues(
            tester, find.byKey(const ValueKey('sellin_monthly_table'))),
      }.toList()
        ..sort();
      expect(issues, isEmpty, reason: issues.join('\n'));
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
    }, _client);
  });

  double innerWidth(WidgetTester tester, Finder table) {
    final c = find
        .ancestor(of: table, matching: find.byType(TableScrollContainer));
    if (c.evaluate().isNotEmpty) {
      return tester.getSize(c.first).width - 32.0;
    }
    // Records table no longer uses TableScrollContainer — compare to surface.
    final surface = find.byKey(const ValueKey('sellin_records_surface'));
    return tester.getSize(surface).width - 32.0;
  }

  for (final w in [_viewport, 2400.0]) {
    testWidgets('A4. tables fill the full width at ${w.toInt()}dp',
        (tester) async {
      await http.runWithClient(() async {
        await _pump(tester, width: w);
        final rec = find.byKey(const ValueKey('sellin_records_table'));
        expect(tester.getSize(rec).width,
            greaterThanOrEqualTo(innerWidth(tester, rec) - 12.0),
            reason: 'records');
        // No empty band after the last (file) column: in RTL it is the
        // leftmost column, so its header must sit near the table's left edge.
        final r = tester.getRect(rec);
        final lastHdr =
            find.descendant(of: rec, matching: find.text('الملف')).first;
        expect(tester.getCenter(lastHdr).dx - r.left,
            lessThan(r.width * 0.1),
            reason: 'records columns stretch to fill');
        await tester
            .tap(find.textContaining(RegExp('^المخزون وإعادة الطلب')).first);
        await tester.pumpAndSettle();
        final sku = find.byKey(const ValueKey('sellin_sku_table'));
        final skuPin = find.byKey(const ValueKey('sellin_sku_pinned_column'));
        final skuInner = find
            .ancestor(of: sku, matching: find.byType(TableScrollContainer))
            .first;
        final skuAvail = tester.getSize(skuInner).width - 32.0;
        expect(tester.getSize(sku).width + tester.getSize(skuPin).width,
            greaterThanOrEqualTo(skuAvail - 12.0),
            reason: 'sku');
        final mon = find.byKey(const ValueKey('sellin_monthly_table'));
        final monInner = find
            .ancestor(of: mon, matching: find.byType(TableScrollContainer))
            .first;
        expect(tester.getSize(mon).width,
            greaterThanOrEqualTo(tester.getSize(monInner).width - 32.0 - 12.0),
            reason: 'monthly');
      }, _client);
    });
  }

  testWidgets(
      'A5. column headers and content are centred; item names start-aligned',
      (tester) async {
    await http.runWithClient(() async {
      await _pump(tester, width: 1600.0);
      double cx(Finder f) => tester.getCenter(f.first).dx;
      final rec = find.byKey(const ValueKey('sellin_records_table'));
      final hdr = find.descendant(of: rec, matching: find.text('الفترة'));
      final cell = find.descendant(
          of: find.byKey(const ValueKey('sellin_record_row_0')),
          matching: find.text('أكتوبر 2026'));
      expect((cx(hdr) - cx(cell)).abs(), lessThan(1.5));
      // Numeric columns are end-aligned; period stays centred with its header.
      final net = find.descendant(
          of: find.byKey(const ValueKey('sellin_record_row_0')),
          matching: find.byKey(const ValueKey('sellin_record_net')));
      final netHdr =
          find.descendant(of: rec, matching: find.text('صافي Sell-In'));
      // Cell sits toward the end (left in RTL) of the header band.
      expect(tester.getRect(net).center.dx,
          lessThan(tester.getRect(netHdr).center.dx + 1.0));
      final name = tester.widget<Text>(
          find.byKey(const ValueKey('sellin_record_item_name')).first);
      expect(name.textAlign, isNot(TextAlign.center));
      await tester
          .tap(find.textContaining(RegExp('^المخزون وإعادة الطلب')).first);
      await tester.pumpAndSettle();
      final sku = find.byKey(const ValueKey('sellin_sku_table'));
      expect(
          (cx(find.descendant(of: sku, matching: find.text('الحالة'))) -
                  cx(find.byKey(const ValueKey('sellin_sku_status'))))
              .abs(),
          lessThan(1.5));
      final mon = find.byKey(const ValueKey('sellin_monthly_table'));
      expect(
          (cx(find.descendant(of: mon, matching: find.text('الحالة'))) -
                  cx(find.byKey(const ValueKey('sellin_monthly_status'))))
              .abs(),
          lessThan(1.5));
    }, _client);
  });

  testWidgets('A6. long item names wrap to 3 lines (tooltip only as fallback)',
      (tester) async {
    await http.runWithClient(() async {
      await _pump(tester);
      final name = find.byKey(const ValueKey('sellin_record_item_name')).first;
      expect(tester.widget<Text>(name).maxLines, 3);
      final p = tester.renderObject<RenderParagraph>(
          find.descendant(of: name, matching: find.byType(RichText)));
      expect(_lines(p), 3);
      await tester
          .tap(find.textContaining(RegExp('^المخزون وإعادة الطلب')).first);
      await tester.pumpAndSettle();
      final sku = find.byKey(const ValueKey('sellin_sku_name'));
      expect(tester.widget<Text>(sku.first).maxLines, 3);
      final sp = tester.renderObject<RenderParagraph>(
          find.descendant(of: sku.first, matching: find.byType(RichText)));
      expect(_lines(sp), greaterThanOrEqualTo(2));
      expect(tester.takeException(), isNull);
    }, _client);
  });
}

int _lines(RenderParagraph p) {
  final len = p.text.toPlainText().length;
  final boxes = p.getBoxesForSelection(TextSelection(baseOffset: 0, extentOffset: len));
  return boxes.map((b) => b.top.round()).toSet().length;
}
