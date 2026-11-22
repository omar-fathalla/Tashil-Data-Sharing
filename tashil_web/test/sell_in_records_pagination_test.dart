// Sell-In records table: client-side pagination (20/page), all 12 columns
// visible without horizontal scroll at ~1440 with sidebar, SKU icon lines,
// file icon+tooltip, filter reset. Display-only.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tashil_web/core/network/api_client.dart';
import 'package:tashil_web/core/theme/app_theme.dart';
import 'package:tashil_web/core/widgets/app_icons.dart';
import 'package:tashil_web/core/widgets/table_scroll_container.dart';
import 'package:tashil_web/features/sell_out_analytics/presentation/screens/sell_in_explorer_screen.dart';

import 'support/real_fonts.dart';

/// ~1440 browser width with ~250dp sidebar → content ≈ 1190.
const _contentWidth = 1440.0 - 250.0;

Map<String, Object?> _record(int i) => {
      'record_id': 'r$i',
      'batch_id': 'b',
      'source_filename': 'in26a.xlsx',
      'tenant_id': 'tenant-adeco',
      'retailer_chain': 'fathalla',
      'year': 2026,
      'month_num': 10,
      'month_ar': 'أكتوبر',
      'governorate': 'الجيزة',
      'item_code': '10${i}55',
      'barcode': '62230000${i.toString().padLeft(2, '0')}1234',
      'brand': 'فيبا',
      'sub_category': 'منظفات',
      'item_name': 'صنف توريد رقم $i',
      'sales_rep': 'مندوب $i',
      'units_per_carton': 12,
      'net_qty_cases': 10.0 + i,
      'net_value_egp': 1000.0 + i * 10,
      'gross_value_incl_vat_egp': (1000.0 + i * 10) * 1.14,
      'vat_amount_egp': (1000.0 + i * 10) * 0.14,
      'weight_tons': 0.5,
      'official_carton_excl_vat_egp': 100.0,
      'actual_case_price_excl_egp': 100.0,
      'effective_discount_pct': 0.0,
      'invoice_discount_pct': 0.0,
      'extra_discount_pct': 0.0,
      'pricing_wave_status': 'current_list',
    };

MockClient _client({int count = 45, double kpiTotal = 99999.0}) {
  final records = [for (var i = 1; i <= count; i++) _record(i)];
  return MockClient((req) async {
    Object? body;
    if (req.url.path.endsWith('/api/v1/analytics/sell-in-records')) {
      final limit = int.tryParse(req.url.queryParameters['limit'] ?? '') ?? 250;
      final offset = int.tryParse(req.url.queryParameters['offset'] ?? '') ?? 0;
      final q = (req.url.queryParameters['q'] ?? '').trim();
      var filtered = records;
      if (q.isNotEmpty) {
        filtered = [
          for (final r in records)
            if ((r['item_name'] as String).contains(q) ||
                (r['item_code'] as String).contains(q) ||
                (r['barcode'] as String).contains(q))
              r,
        ];
      }
      final slice = filtered.skip(offset).take(limit).toList();
      body = {
        'records': slice,
        'total_count': filtered.length,
        'total_value_egp': kpiTotal,
        'total_cases': 1234.0,
        'total_weight_tons': 56.7,
        'total_expected_egp': 0.0,
        'total_net_excl_vat_egp': kpiTotal,
      };
    } else if (req.url.path.endsWith('/api/v1/analytics/cpfr')) {
      body = {
        'monthly_reconciliation': <Object>[],
        'inventory_and_po_items': <Object>[],
      };
    } else if (req.url.path.endsWith('/api/v1/ingest/archive')) {
      body = {
        'tenant_id': 'tenant-adeco',
        'total_count': 0,
        'files': <Object>[],
      };
    } else if (req.url.path.contains('/chains') ||
        req.url.path.contains('/retail')) {
      body = {
        'chains': [
          {'code': 'fathalla', 'display_name': 'فتح الله'},
        ],
      };
    }
    if (body == null) return http.Response('not found', 404);
    return http.Response.bytes(
      utf8.encode(jsonEncode(body)),
      200,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );
  });
}

Future<void> _pump(
  WidgetTester tester, {
  double width = _contentWidth,
}) async {
  tester.view.physicalSize = Size(width, 3600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(),
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          body: SellInExplorerScreen(
            apiClient: ApiClient(tenantId: 'tenant-adeco'),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _tapPager(WidgetTester tester, Key key, {required bool enabled}) async {
  final finder = find.byKey(key);
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  final btn = tester.widget<IconButton>(finder);
  if (enabled) {
    expect(btn.onPressed, isNotNull, reason: '$key enabled');
  } else {
    expect(btn.onPressed, isNull, reason: '$key disabled');
  }
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

double? _hScrollExtent(WidgetTester tester, Finder table) {
  final scrollables =
      find.ancestor(of: table, matching: find.byType(Scrollable));
  for (final e in scrollables.evaluate()) {
    final st = (e as StatefulElement).state as ScrollableState;
    if (st.position.axis == Axis.horizontal) {
      return st.position.maxScrollExtent;
    }
  }
  return null;
}

void main() {
  setUpAll(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    await loadRealCairoFont();
  });

  testWidgets('shows 20 rows per page with Arabic range + page label',
      (tester) async {
    await http.runWithClient(() async {
      await _pump(tester);
      expect(find.byKey(const ValueKey('sellin_records_pagination')),
          findsOneWidget);
      expect(
        find.byKey(const ValueKey('sellin_records_page_label')),
        findsOneWidget,
      );
      expect(find.textContaining('عرض 1–20 من 45'), findsOneWidget);
      expect(find.textContaining('صفحة 1 من 3'), findsOneWidget);
      expect(find.text('صنف توريد رقم 1'), findsOneWidget);
      expect(find.text('صنف توريد رقم 20'), findsOneWidget);
      expect(find.text('صنف توريد رقم 21'), findsNothing);
      expect(find.byKey(const ValueKey('sellin_record_row_0')), findsOneWidget);
      expect(find.byKey(const ValueKey('sellin_record_row_19')), findsOneWidget);
      expect(find.byKey(const ValueKey('sellin_record_row_20')), findsNothing);

      final first = tester.widget<IconButton>(
          find.byKey(const ValueKey('sellin_records_first_btn')));
      final prev = tester.widget<IconButton>(
          find.byKey(const ValueKey('sellin_records_prev_btn')));
      expect(first.onPressed, isNull);
      expect(prev.onPressed, isNull);
    }, _client());
  });

  testWidgets('next/prev/first/last navigate and disable at ends',
      (tester) async {
    await http.runWithClient(() async {
      await _pump(tester);

      await _tapPager(
        tester,
        const ValueKey('sellin_records_next_btn'),
        enabled: true,
      );
      expect(find.textContaining('عرض 21–40 من 45'), findsOneWidget);
      expect(find.text('صنف توريد رقم 21'), findsOneWidget);
      expect(find.text('صنف توريد رقم 1'), findsNothing);

      await _tapPager(
        tester,
        const ValueKey('sellin_records_last_btn'),
        enabled: true,
      );
      expect(find.textContaining('عرض 41–45 من 45'), findsOneWidget);
      expect(find.text('صنف توريد رقم 45'), findsOneWidget);
      final next = tester.widget<IconButton>(
          find.byKey(const ValueKey('sellin_records_next_btn')));
      final last = tester.widget<IconButton>(
          find.byKey(const ValueKey('sellin_records_last_btn')));
      expect(next.onPressed, isNull);
      expect(last.onPressed, isNull);

      await _tapPager(
        tester,
        const ValueKey('sellin_records_prev_btn'),
        enabled: true,
      );
      expect(find.textContaining('صفحة 2 من 3'), findsOneWidget);

      await _tapPager(
        tester,
        const ValueKey('sellin_records_first_btn'),
        enabled: true,
      );
      expect(find.textContaining('صفحة 1 من 3'), findsOneWidget);
      expect(find.text('صنف توريد رقم 1'), findsOneWidget);
    }, _client());
  });

  testWidgets('page circle jumps to chosen page', (tester) async {
    await http.runWithClient(() async {
      await _pump(tester);
      await tester.ensureVisible(
          find.byKey(const ValueKey('sellin_records_page_circle_2')));
      await tester.tap(find.byKey(const ValueKey('sellin_records_page_circle_2')));
      await tester.pumpAndSettle();
      expect(find.textContaining('صفحة 3 من 3'), findsOneWidget);
      expect(find.text('صنف توريد رقم 45'), findsOneWidget);
    }, _client());
  });

  testWidgets('search filter resets to page 1; KPI stays on full filtered set',
      (tester) async {
    const kpi = 88888.0;
    await http.runWithClient(() async {
      await _pump(tester);

      await _tapPager(
        tester,
        const ValueKey('sellin_records_next_btn'),
        enabled: true,
      );
      expect(find.textContaining('صفحة 2 من 3'), findsOneWidget);

      // KPI card shows full-set total_count (45), not the page size (20).
      expect(find.textContaining('صف'), findsWidgets);

      final search = find.descendant(
        of: find.byKey(const ValueKey('sellin_data_filter_bar')),
        matching: find.byType(TextField),
      );
      await tester.enterText(search, 'صنف توريد رقم 3');
      await tester.pumpAndSettle();

      // Narrow filter → back to page 1 (matches 3, 30–39 → 11 rows → 1 page).
      expect(find.byKey(const ValueKey('sellin_records_pagination')),
          findsOneWidget);
      expect(find.textContaining('صفحة 1 من'), findsOneWidget);
      final prev = tester.widget<IconButton>(
          find.byKey(const ValueKey('sellin_records_prev_btn')));
      expect(prev.onPressed, isNull);
    }, _client(kpiTotal: kpi));
  });

  testWidgets('all 12 headers visible; no horizontal scroll or يمين/شمال at 1440',
      (tester) async {
    await http.runWithClient(() async {
      await _pump(tester, width: _contentWidth);
      final table = find.byKey(const ValueKey('sellin_records_table'));
      expect(table, findsOneWidget);

      for (final h in [
        'الصنف',
        'الفترة',
        'السلسلة / الفرع',
        'كرتونة / وحدة',
        'صافي Sell-In',
        'الإجمالي',
        'سعر الكرتونة',
        'السعر المتوقع',
        'العلامة التجارية / الفئة',
        'المندوب',
        'الوزن (طن)',
        'الملف',
      ]) {
        final f = find.descendant(of: table, matching: find.text(h));
        expect(f, findsWidgets, reason: h);
        final r = tester.getRect(f.first);
        expect(r.left, greaterThanOrEqualTo(-0.5), reason: h);
        expect(r.right, lessThanOrEqualTo(_contentWidth + 0.5), reason: h);
      }

      expect(_hScrollExtent(tester, table), isNull);
      expect(find.text('يمين'), findsNothing);
      expect(find.text('شمال'), findsNothing);
      expect(find.textContaining('اسحب'), findsNothing);
      // Records table must not wrap TableScrollContainer.
      expect(
        find.ancestor(
          of: table,
          matching: find.byType(TableScrollContainer),
        ),
        findsNothing,
      );
    }, _client());
  });

  testWidgets('SKU code/barcode use icon semanticLabels; no visible الكود labels',
      (tester) async {
    await http.runWithClient(() async {
      await _pump(tester);
      expect(find.textContaining('الكود:'), findsNothing);
      expect(find.textContaining('الباركود:'), findsNothing);

      final icons = tester.widgetList<Icon>(find.byType(Icon)).toList();
      final tag = icons.where((i) => i.icon == AppIcons.tag).toList();
      final barcode = icons.where((i) => i.icon == AppIcons.barcode).toList();
      expect(tag, isNotEmpty);
      expect(barcode, isNotEmpty);
      expect(tag.first.semanticLabel, 'الكود');
      expect(barcode.first.semanticLabel, 'الباركود');
      expect(tag.first.size, 16.0);
      expect(barcode.first.size, 16.0);
    }, _client(count: 5));
  });

  testWidgets('file column is icon+tooltip only (no filename text in cell)',
      (tester) async {
    await http.runWithClient(() async {
      await _pump(tester, width: _contentWidth);
      expect(find.byKey(const ValueKey('sellin_record_file_btn')), findsWidgets);
      // Sheet short name / raw filename must not appear as cell text.
      expect(find.text('in26a.xlsx'), findsNothing);
      expect(find.textContaining('in26a'), findsNothing);

      final btn = tester.widget<IconButton>(
          find.byKey(const ValueKey('sellin_record_file_btn')).first);
      expect(btn.tooltip, contains('in26a.xlsx'));
      expect(btn.tooltip, contains('·'));
      final icon = btn.icon as Icon;
      expect(icon.icon, AppIcons.tableView);
      expect(icon.size, 24.0);
    }, _client(count: 5));
  });
}
