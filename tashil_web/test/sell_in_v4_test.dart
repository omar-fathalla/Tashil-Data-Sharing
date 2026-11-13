// Sell-In v4: monthly table fits 1030dp with realistic (made-up) large
// numbers, stock table main columns fit, and the uploaded-files 'الإجراءات'
// header is centred over the pinned actions column (Sell-In + Sell-Out).
// Fixture helpers copied from the v3 test.
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
import 'package:tashil_web/features/sell_out_analytics/presentation/screens/sell_out_explorer_screen.dart';

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
        'opening_stock_cases': 123456.0 + m,
        'opening_stock_value_egp': 187654321.5 + m * 1000,
        'sell_in_cases': 65432.0 + m,
        'sell_in_value_egp': 98765432.1 + m * 1000,
        'sell_in_gross_incl_vat_egp': 112592592.6 + m * 1000,
        'sell_out_est_cases': 54321.0 + m,
        'sell_out_value_egp': 87654321.9 + m * 1000,
        'sell_out_factory_cost_excl_vat_egp': 71234567.8,
        'sell_out_factory_cost_incl_vat_egp': 81207407.3,
        'chain_gross_margin_egp': 12345678.9,
        'chain_gross_margin_pct': 14.1,
        'prev_year_sell_out_value_egp': 70000000.0,
        'yoy_sell_out_growth_pct': m.isEven ? -12.3 : 25.4,
        'closing_stock_cases': 134567.0 + m,
        'closing_stock_value_egp': 198765432.1 + m * 1000,
        'sell_through_rate_pct': 47.3,
        'stock_health_status': ['overstock', 'urgent_replenishment', 'optimal'][m % 3],
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
        'suggested_po_cases': 12345 - i,
        'suggested_po_value_egp': 23456789.5,
        'suggested_po_gross_incl_vat_egp': 26740740.0,
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
        body = {
          'tenant_id': 'tenant-adeco',
          'total_count': 2,
          'files': [
            for (final f in ['in26a.xlsx', 'in26b.xlsx'])
              {
                'id': 'arch_$f',
                'file_type': 'sell_in',
                'file_name': f,
                'retail_chain': 'fathalla',
                'target_year': '2026',
                'rows_ingested': 4321,
                'total_cases': 6543.0,
                'total_weight_tons': 123.4,
                'total_revenue': 9876543.2,
                'uploaded_at': '2026-11-13T10:00:00Z',
              },
          ],
        };
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

double _hScrollExtent(WidgetTester tester, Finder table) {
  final s = find.ancestor(of: table, matching: find.byType(Scrollable));
  for (final e in s.evaluate()) {
    final st = (e as StatefulElement).state as ScrollableState;
    if (st.position.axis == Axis.horizontal) return st.position.maxScrollExtent;
  }
  return 0;
}

void _expectCentredOver(WidgetTester tester, Finder header, Finder column) {
  final h = tester.getCenter(header.first).dx;
  final c = tester.getCenter(column.first).dx;
  expect((h - c).abs(), lessThan(1.5), reason: 'header $h vs column $c');
}

const _monthlyHeaders = [
  'الشهر / السنة',
  'رصيد أول الشهر',
  '+ Sell-In',
  '− Sell-Out',
  'هامش السلسلة',
  'النمو السنوي',
  'رصيد آخر الشهر',
  'نسبة التصريف',
  'الحالة',
];

void main() {
  setUpAll(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    await loadRealCairoFont();
  });

  testWidgets('B1. monthly table: every column fits 1030dp, no horizontal scroll', (tester) async {
    await http.runWithClient(() async {
      await _pump(tester, tab: 1);
      expect(tester.takeException(), isNull);
      final mon = find.byKey(const ValueKey('sellin_monthly_table'));
      for (final h in _monthlyHeaders) {
        _expectInViewport(tester, find.descendant(of: mon, matching: find.text(h)), h);
      }
      for (final e in find.byKey(const ValueKey('sellin_monthly_status')).evaluate()) {
        final r = tester.getRect(find.byWidget(e.widget).first);
        expect(r.left, greaterThanOrEqualTo(-0.5), reason: 'status $r');
      }
      expect(_hScrollExtent(tester, mon), lessThanOrEqualTo(0.5));
      final issues = _textIssues(tester, mon)..sort();
      expect(issues, isEmpty, reason: issues.join('\n'));
    }, _client);
  });

  testWidgets('B2. monthly table fills wider screens', (tester) async {
    await http.runWithClient(() async {
      await _pump(tester, tab: 1, width: 2000);
      final mon = find.byKey(const ValueKey('sellin_monthly_table'));
      final c = find.ancestor(of: mon, matching: find.byType(TableScrollContainer)).first;
      expect(tester.getSize(mon).width, greaterThanOrEqualTo(tester.getSize(c).width - 32 - 12));
    }, _client);
  });

  testWidgets('B3. stock table: main columns and suggested order fit 1030dp', (tester) async {
    await http.runWithClient(() async {
      await _pump(tester, tab: 1);
      final sku = find.byKey(const ValueKey('sellin_sku_table'));
      for (final h in ['العلامة التجارية', 'Sell-In', 'Sell-Out', 'المخزون', 'أيام التغطية', 'الحالة', 'أمر الشراء المقترح']) {
        _expectInViewport(tester, find.descendant(of: sku, matching: find.textContaining(RegExp('^$h'))), h);
      }
      _expectInViewport(tester, find.byKey(const ValueKey('sellin_sku_pinned_column')), 'sku pinned');
      final issues = _textIssues(tester, sku)..sort();
      expect(issues, isEmpty, reason: issues.join('\n'));
    }, _client);
  });

  testWidgets('B4. records table: main columns not clipped at 1030dp', (tester) async {
    await http.runWithClient(() async {
      await _pump(tester);
      final rec = find.byKey(const ValueKey('sellin_records_table'));
      for (final h in ['الفترة', 'السلسلة / الفرع', 'كرتونة / وحدة', 'صافي Sell-In', 'الإجمالي']) {
        _expectInViewport(tester, find.descendant(of: rec, matching: find.text(h)), h);
      }
      _expectInViewport(tester, find.byKey(const ValueKey('sellin_records_pinned_item')), 'pinned item');
    }, _client);
  });

  testWidgets('B5. Sell-In files: الإجراءات header centred over the actions column', (tester) async {
    await http.runWithClient(() async {
      await _pump(tester);
      await tester.tap(find.textContaining(RegExp('^الملفات المرفوعة')).first);
      await tester.pumpAndSettle();
      final col = find.byKey(const ValueKey('sellin_uploaded_files_actions_column'));
      expect(col, findsOneWidget);
      _expectCentredOver(tester, find.descendant(of: col, matching: find.text('الإجراءات')), col);
    }, _client);
  });

  testWidgets('B6. Sell-Out files: الإجراءات header centred over the actions column', (tester) async {
    await http.runWithClient(() async {
      tester.view.physicalSize = const Size(1440, 3600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light(),
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(body: SellOutExplorerScreen(apiClient: ApiClient(tenantId: 'tenant-adeco'))),
        ),
      ));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining(RegExp('^الملفات المرفوعة')).first);
      await tester.pumpAndSettle();
      final col = find.byKey(const ValueKey('uploaded_files_actions_column'));
      expect(col, findsOneWidget);
      _expectCentredOver(tester, find.descendant(of: col, matching: find.text('الإجراءات')), col);
    }, () => MockClient((req) async {
          if (req.url.path.endsWith('/api/v1/ingest/archive')) {
            return http.Response.bytes(
                utf8.encode(jsonEncode({
                  'tenant_id': 'tenant-adeco',
                  'total_count': 1,
                  'files': [
                    {
                      'id': 'arch_1',
                      'file_type': 'sell_out',
                      'file_name': 'out26.xlsx',
                      'retail_chain': 'fathalla',
                      'rows_ingested': 4321,
                      'total_units': 65432,
                      'uploaded_at': '2026-11-13T10:00:00Z',
                    }
                  ],
                })),
                200,
                headers: {'content-type': 'application/json; charset=utf-8'});
          }
          return http.Response.bytes(utf8.encode(jsonEncode({'records': [], 'total_count': 0})), 200,
              headers: {'content-type': 'application/json'});
        }));
  });
}
