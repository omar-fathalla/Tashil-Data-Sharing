// Header geometry measured with the real Cairo font (not the 1em-square
// test font), so widths match what users see on the live dashboard.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tashil_web/core/network/api_client.dart';
import 'package:tashil_web/core/theme/app_theme.dart';
import 'package:tashil_web/features/executive_dashboard/presentation/screens/executive_screen.dart';
import 'package:tashil_web/features/navigation/presentation/desktop_sidebar.dart';

import 'support/real_fonts.dart';

/// Test-only CPFR rows (no real data) so the inventory table renders.
final _inventoryRows = [
  for (var i = 0; i < 3; i++)
    {
      'barcode': 'b$i',
      'item_code': 'T$i',
      'sku_name': 'صنف تجريبي رقم $i بعبوة كبيرة',
      'sell_in_units': 1000 + i,
      'sell_out_units': 900 + i,
      'estimated_stock_units': 100,
      'sell_through_pct': 90.0,
      'stock_status': ['optimal', 'overstock', 'urgent_replenishment'][i],
    },
];

MockClient _client({bool inventory = false}) => MockClient((req) async {
      if (req.url.path.endsWith('/api/v1/analytics/cpfr')) {
        return http.Response(
            jsonEncode({
              'monthly_reconciliation': <Object>[],
              'inventory_and_po_items': inventory ? _inventoryRows : <Object>[],
            }),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'});
      }
      return http.Response('not found', 404);
    });

/// RTL dashboard; with [sidebar] the full desktop sidebar sits beside it, as
/// in the shell on desktop widths.
Future<void> _pump(WidgetTester tester, Size size,
        {bool sidebar = false, bool inventory = false}) =>
    http.runWithClient(() async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light(),
        builder: (context, child) =>
            Directionality(textDirection: TextDirection.rtl, child: child!),
        home: Scaffold(
          body: Row(children: [
            if (sidebar)
              DesktopSidebar(
                selectedIndex: 0,
                onDestinationSelected: (_) {},
                activeTenant: 'adeco',
                onTenantChanged: (_) {},
              ),
            Expanded(
              child: ExecutiveScreen(
                  apiClient: ApiClient(tenantId: 'tenant-adeco')),
            ),
          ]),
        ),
      ));
      await tester.pumpAndSettle();
    }, () => _client(inventory: inventory));

void main() {
  GoogleFonts.config.allowRuntimeFetching = false;
  setUpAll(loadRealCairoFont);

  testWidgets('real Cairo font is in use (not the 1em-square test font)',
      (tester) async {
    await _pump(tester, const Size(1440, 900));
    // 4 glyphs at 14px would be 56dp wide with the test font.
    final p = tester.renderObject<RenderParagraph>(find.text('شهري'));
    expect(p.getMaxIntrinsicWidth(double.infinity), lessThan(48.0));
  });

  for (final size in const [Size(1440, 900), Size(1019, 900)]) {
    testWidgets(
        'period segments are equal, single-line and ≥ 112dp with Cairo '
        '@${size.width.toInt()}', (tester) async {
      await _pump(tester, size, sidebar: true);
      expect(tester.takeException(), isNull);
      final segs = find.descendant(
          of: find.byKey(const ValueKey('executive_period_segmented')),
          matching: find.byType(TextButton));
      expect(segs, findsNWidgets(3));
      final widths = [
        for (final e in segs.evaluate())
          (e.renderObject! as RenderBox).size.width
      ];
      for (final w in widths) {
        expect(w, closeTo(widths.first, 0.5));
        expect(w, greaterThanOrEqualTo(112.0),
            reason: 'segment widths $widths');
      }
      for (final label in const ['شهري', 'ربع سنوي', 'سنوي']) {
        expect(tester.getSize(find.text(label)).height, lessThanOrEqualTo(24.0),
            reason: '$label on one line');
      }
      expect(
          tester
              .getSize(find.byKey(const ValueKey('executive_period_segmented')))
              .height,
          greaterThanOrEqualTo(40.0));
    });
  }

  testWidgets('@1019 with the sidebar: the three filters stay on one line',
      (tester) async {
    await _pump(tester, const Size(1019, 900), sidebar: true);
    expect(tester.takeException(), isNull);
    final month =
        tester.getRect(find.byKey(const ValueKey('executive_month_dropdown')));
    final year =
        tester.getRect(find.byKey(const ValueKey('executive_year_dropdown')));
    final chain =
        tester.getRect(find.byKey(const ValueKey('executive_chain_dropdown')));
    expect(year.top, closeTo(month.top, 0.5));
    expect(chain.top, closeTo(month.top, 0.5));
    // At most two lines: period control (48dp target) + filter group.
    final period = tester
        .getRect(find.byKey(const ValueKey('executive_period_segmented')));
    expect(month.top - period.top, lessThanOrEqualTo(48.0 + 8.0 + 0.5));
  });

  double dividerWidth(WidgetTester tester) => tester
      .getSize(find.byKey(const ValueKey('m3_divided_controls_divider')))
      .width;

  testWidgets('@1920 with the sidebar: controls are one row under the title',
      (tester) async {
    await _pump(tester, const Size(1920, 1000), sidebar: true);
    expect(tester.takeException(), isNull);
    final title = tester.getRect(find.text('أداء المبيعات في سلاسل التجزئة'));
    final period = tester
        .getRect(find.byKey(const ValueKey('executive_period_segmented')));
    final chain =
        tester.getRect(find.byKey(const ValueKey('executive_chain_dropdown')));
    final month =
        tester.getRect(find.byKey(const ValueKey('executive_month_dropdown')));
    expect(period.top, greaterThan(title.bottom), reason: 'own row');
    expect(chain.center.dy, closeTo(period.center.dy, 4.0));
    expect(month.center.dy, closeTo(period.center.dy, 4.0));
    // Divider shown, between the period control and the filters (RTL).
    expect(dividerWidth(tester), 16.0);
    final div = tester
        .getRect(find.byKey(const ValueKey('m3_divided_controls_divider')));
    expect(div.right, lessThanOrEqualTo(period.left + 0.5));
    expect(div.left, greaterThanOrEqualTo(month.right - 0.5));
  });

  testWidgets('@1440 the controls sit on one line under the title',
      (tester) async {
    await _pump(tester, const Size(1440, 900), sidebar: true);
    final title = tester.getRect(find.text('أداء المبيعات في سلاسل التجزئة'));
    final period = tester
        .getRect(find.byKey(const ValueKey('executive_period_segmented')));
    final chain =
        tester.getRect(find.byKey(const ValueKey('executive_chain_dropdown')));
    expect(period.top, greaterThan(title.bottom));
    expect(chain.center.dy, closeTo(period.center.dy, 4.0));
    expect(dividerWidth(tester), 16.0);
  });

  testWidgets('@1019 stacked: no dangling divider', (tester) async {
    await _pump(tester, const Size(1019, 900), sidebar: true);
    final period = tester
        .getRect(find.byKey(const ValueKey('executive_period_segmented')));
    final month =
        tester.getRect(find.byKey(const ValueKey('executive_month_dropdown')));
    expect(month.top, greaterThan(period.bottom - 0.5));
    expect(dividerWidth(tester), 0.0);
  });

  testWidgets(
      '@1440 with the sidebar: "نسبة التصريف" heading wraps on whole words',
      (tester) async {
    await _pump(tester, const Size(1440, 1400), sidebar: true, inventory: true);
    expect(tester.takeException(), isNull);
    final table = find.byKey(const ValueKey('stock_per_sku_table'));
    expect(table, findsOneWidget);
    final rp = tester.renderObject<RenderParagraph>(
        find.descendant(of: table, matching: find.text('نسبة التصريف')));
    expect(rp.didExceedMaxLines, isFalse);
    // Longest word ("التصريف") must fit the column, or it breaks mid-word.
    expect(rp.getMinIntrinsicWidth(double.infinity),
        lessThanOrEqualTo(rp.size.width + 0.5));
    // Short status chips + descriptions are not truncated mid-word.
    // urgent_replenishment keeps description only (no «تموين» chip).
    for (final label in const [
      'سليم',
      'زائد',
      'مخزون زائد',
      'يحتاج إعادة توريد',
    ]) {
      final tag = tester.renderObject<RenderParagraph>(
          find.descendant(of: table, matching: find.text(label)));
      expect(tag.didExceedMaxLines, isFalse, reason: label);
    }
    expect(find.descendant(of: table, matching: find.text('تموين')),
        findsNothing);
  });

  testWidgets(
      '@1440 quarterly mode: no overflow, divider shown or cleanly hidden',
      (tester) async {
    await _pump(tester, const Size(1440, 900), sidebar: true);
    await tester.tap(find.text('ربع سنوي'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byKey(const ValueKey('executive_quarter_segmented')),
        findsOneWidget);
    final w = dividerWidth(tester);
    expect(w == 16.0 || w == 0.0, isTrue, reason: 'divider width $w');
    final period = tester
        .getRect(find.byKey(const ValueKey('executive_period_segmented')));
    final month =
        tester.getRect(find.byKey(const ValueKey('executive_month_dropdown')));
    if (w == 0.0) {
      expect(month.top, greaterThan(period.bottom - 0.5));
    } else {
      expect(month.center.dy, closeTo(period.center.dy, 4.0));
    }
  });

  for (final size in const [Size(1440, 900), Size(1019, 900)]) {
    testWidgets(
        'focus order @${size.width.toInt()}: period → month → year → chain',
        (tester) async {
      await _pump(tester, size, sidebar: true);
      const names = {
        'executive_period_segmented': 'period',
        'executive_month_dropdown': 'month',
        'executive_year_dropdown': 'year',
        'executive_chain_dropdown': 'chain',
      };
      String? focused() {
        final ctx = FocusManager.instance.primaryFocus?.context;
        if (ctx == null) return null;
        String? hit;
        void check(Element e) {
          final k = e.widget.key;
          if (k is ValueKey<String>) hit ??= names[k.value];
        }

        check(ctx as Element);
        ctx.visitAncestorElements((e) {
          check(e);
          return hit == null;
        });
        return hit;
      }

      Focus.of(tester.element(find.text('شهري'))).requestFocus();
      await tester.pump();
      final order = <String>[];
      for (var i = 0; i < 10 && !order.contains('chain'); i++) {
        final f = focused();
        if (f != null && (order.isEmpty || order.last != f)) order.add(f);
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
      }
      final f = focused();
      if (f != null && order.last != f) order.add(f);
      expect(order.take(4).toList(), ['period', 'month', 'year', 'chain']);
    });
  }
}
