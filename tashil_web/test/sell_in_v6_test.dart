// Sell-In v5: long backend status labels wrap inside the monthly chip, scroll
// hints hide when a table fits, stock secondary details wrap to 3 lines.
// Based on v4: monthly table fits 1030dp with realistic (made-up) large
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
import 'package:tashil_web/features/sell_out_analytics/presentation/utils/monthly_status_text.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tashil_web/core/network/api_client.dart';
import 'package:tashil_web/core/theme/app_theme.dart';
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
        'stock_health_status': [
          'drawdown',
          'balanced',
          'accumulation',
          'awaiting_sell_out',
          'awaiting_sell_in'
        ][m % 5],
        'stock_health_label_ar': [
          'سحب عالٍ يفوق توريد الشهر (تصريف من الرصيد السابق - يحتاج تعويض)',
          'معدل تصريف صحي ورصيد متبقي آمن',
          'تراكم مخزني بالفرع (التوريد أعلى من السحب - راقب الرصيد المتبقي)',
          'توريد مضاف للمخزن (بانتظار رفع شيت كاشير السلسلة Sell-Out للشهر)',
          'سحب فعلي مسجل (بانتظار رفع شيت التوريد Sell-In للشهر)',
        ][m % 5],
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
        'sell_in_value_egp': 98765432.1,
        'sell_out_value_egp': 87654321.9,
        'retailer_margin_pct': 18.0,
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

double _hScrollExtent(WidgetTester tester, Finder table) {
  final s = find.ancestor(of: table, matching: find.byType(Scrollable));
  for (final e in s.evaluate()) {
    final st = (e as StatefulElement).state as ScrollableState;
    if (st.position.axis == Axis.horizontal) return st.position.maxScrollExtent;
  }
  return 0;
}

bool _hintIn(WidgetTester tester, Finder table) {
  final c = find
      .ancestor(of: table, matching: find.byType(TableScrollContainer))
      .first;
  return find
      .descendant(of: c, matching: find.text('يمين'))
      .evaluate()
      .isNotEmpty;
}

List<String> _clipped(WidgetTester tester, Finder scope) {
  final out = <String>[];
  for (final e in find
      .descendant(of: scope, matching: find.byType(RichText))
      .evaluate()) {
    final p = e.renderObject as RenderParagraph;
    if (p.didExceedMaxLines) out.add(p.text.toPlainText());
  }
  return out;
}

void main() {
  setUpAll(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    await loadRealCairoFont();
  });

  test('D1. every backend status maps to a short chip label + description', () {
    const statuses = [
      'drawdown',
      'balanced',
      'accumulation',
      'awaiting_sell_out',
      'awaiting_sell_in',
    ];
    for (final st in statuses) {
      final t = MonthlyStatusText.resolve(st, 'نص طويل جدا من الخادم (تفاصيل)');
      expect(t.short.split(RegExp(r'\s+')).length, lessThanOrEqualTo(2),
          reason: '$st -> ${t.short}');
      expect(t.description, isNotEmpty, reason: st);
      expect(t.short.contains('('), isFalse);
      // Latin tokens stay in the chip; the description is Arabic only so
      // 'Sell-Out' never breaks at its hyphen.
      expect(t.description.contains('-'), isFalse, reason: st);
    }
    expect(MonthlyStatusText.byStatus.keys.toSet(), statuses.toSet());
  });

  test('D2. unknown statuses still get a short chip (fallback)', () {
    final a = MonthlyStatusText.resolve('x', 'حالة جديدة طويلة بدون أقواس');
    expect(a.short, 'حالة جديدة');
    expect(a.description, 'حالة جديدة طويلة بدون أقواس');
    final b = MonthlyStatusText.resolve('x', 'مغلق (تفاصيل الشهر)');
    expect(b.short, 'مغلق');
    expect(b.description, 'تفاصيل الشهر');
    final c = MonthlyStatusText.resolve('x', 'تصريف صحي');
    expect(c.short, 'تصريف صحي');
    expect(c.description, isEmpty);
  });

  testWidgets(
      'D3. monthly chips are short labels with the description under them',
      (tester) async {
    await http.runWithClient(() async {
      await _pump(tester, tab: 1);
      expect(tester.takeException(), isNull);
      final mon = find.byKey(const ValueKey('sellin_monthly_table'));
      final chips = find.byKey(const ValueKey('sellin_monthly_status'));
      final n = chips.evaluate().length;
      expect(n, greaterThanOrEqualTo(5));
      for (final e in chips.evaluate()) {
        final txt = find.descendant(
            of: find.byWidget(e.widget), matching: find.byType(Text));
        final data = tester.widget<Text>(txt.first).data!;
        expect(data.split(RegExp(r'\s+')).length, lessThanOrEqualTo(2),
            reason: 'chip "$data" should be a short label');
        expect(data.contains('('), isFalse);
      }
      // Every row (including the "balanced" one without brackets) shows a
      // grey description under the chip, wrapping up to 3 centred lines.
      final details =
          find.byKey(const ValueKey('sellin_monthly_status_detail'));
      expect(details.evaluate().length, n);
      for (final e in details.evaluate()) {
        final t = e.widget as Text;
        expect(t.maxLines, 3);
        expect(t.textAlign, TextAlign.center);
      }
      expect(find.text('تصريف صحي'), findsWidgets);
      expect(find.text('معدل تصريف صحي ورصيد متبقي آمن'), findsWidgets);
      expect(_hScrollExtent(tester, mon), lessThanOrEqualTo(0.5));
      expect(_hintIn(tester, mon), isFalse);
      final mc = _clipped(tester, mon);
      expect(mc, isEmpty, reason: mc.join('\n'));
    }, _client);
  });
}
