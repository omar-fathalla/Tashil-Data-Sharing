// Sell-Out «نمو الفروع»: one matched-month window for sales / diff / %, a
// grouped rank + branch cell, full-width centred columns and full-width KPI chips.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tashil_web/core/network/api_client.dart';
import 'package:tashil_web/core/theme/app_theme.dart';
import 'package:tashil_web/core/utils/currency_formatter.dart';
import 'package:tashil_web/features/sell_out_analytics/presentation/screens/sell_out_explorer_screen.dart';

import 'support/real_fonts.dart';

Map<String, Object> _store(String id, String name, double rev) => {
      'store_id': id,
      'store_name': name,
      'retailer_chain': 'fathalla',
      'region': 'القاهرة الكبرى',
      'tier': 'Tier A',
      'total_revenue': rev,
      'total_units': 100,
      'velocity_units_per_day': 1.0,
      'rank': 1,
    };

MockClient _client() => MockClient((req) async {
      final p = req.url.path;
      final q = req.url.queryParameters;
      Object body = {'records': [], 'total_count': 0};
      if (p.endsWith('/store-matrix/matched-months')) {
        body = {
          'year': 2026,
          'comp_year': 2025,
          'months': [1, 2, 3, 4],
        };
      } else if (p.endsWith('/store-matrix')) {
        if (q['year'] == '2025') {
          // Last year trimmed to the months present in 2026 (Jan–Apr).
          body = [_store('rahab', 'مدينة الرحاب', 5512604)];
        } else if (q['same_months_as'] == '2025') {
          // 2026 trimmed to the months present in 2025 (Jan–Apr).
          body = [
            _store('rahab', 'مدينة الرحاب', 6332304),
            _store('dm', 'دمياط الجديدة', 1730000),
          ];
        } else {
          // Full 2026 (Jan–Oct): what the 2026 column used to show.
          body = [
            _store('rahab', 'مدينة الرحاب', 18604715),
            _store('dm', 'دمياط الجديدة', 5429124),
          ];
        }
      }
      return http.Response(jsonEncode(body), 200,
          headers: {'content-type': 'application/json; charset=utf-8'});
    });

Future<void> _openGrowth(WidgetTester tester, double width) async {
  tester.view.physicalSize = Size(width, 3000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(MaterialApp(
    theme: AppTheme.light(),
    home: Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        body: SellOutExplorerScreen(
            apiClient: ApiClient(tenantId: 'tenant-adeco')),
      ),
    ),
  ));
  await tester.pumpAndSettle();
  await tester.tap(find.textContaining(RegExp('^أداء الفروع')).first);
  await tester.pumpAndSettle();
}

String _text(WidgetTester t, Key k) => t.widget<Text>(find.byKey(k)).data!;

void main() {
  setUpAll(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    await loadRealCairoFont();
  });

  testWidgets('sales columns, diff and % share the matched-month window',
      (tester) async {
    await http.runWithClient(() async {
      await _openGrowth(tester, 1440);

      expect(_text(tester, const ValueKey('branch_growth_subtitle')),
          contains('مقارنة نفس الشهور: يناير–أبريل'));

      final cur = _text(tester, const ValueKey('branch_growth_cur_rahab'));
      final prev = _text(tester, const ValueKey('branch_growth_prev_rahab'));
      final diff = _text(tester, const ValueKey('branch_growth_diff_rahab'));
      expect(cur, CurrencyFormatter.formatEGP(6332304));
      expect(prev, CurrencyFormatter.formatEGP(5512604));
      expect(diff, '+${CurrencyFormatter.formatCompactEGP(6332304 - 5512604)}');
      expect(
          find.descendant(
              of: find.byKey(const ValueKey('branch_growth_table')),
              matching: find.textContaining('18,604,715')),
          findsNothing,
          reason: 'the full Jan–Oct total must not sit next to a Jan–Apr 2025');

      // Branch without 2025 data: «—» for 2025 and «جديد (2026)» instead of %.
      expect(_text(tester, const ValueKey('branch_growth_prev_dm')), '—');
      expect(find.text('جديد (2026)'), findsOneWidget);
      expect(find.textContaining('+14.9%'), findsWidgets);
    }, _client);
  });

  for (final width in const [1280.0, 1440.0]) {
    testWidgets(
        'layout at $width: grouped rank+branch, centred full-width columns, equal KPI chips',
        (tester) async {
      await http.runWithClient(() async {
        await _openGrowth(tester, width);

        // Rank and branch name are one tight unit (< 12dp between them).
        final rank = tester
            .getRect(find.byKey(const ValueKey('branch_growth_rank_rahab')));
        final name = tester
            .getRect(find.byKey(const ValueKey('branch_growth_name_rahab')));
        final gap =
            (rank.left - name.right).abs() < (rank.right - name.left).abs()
                ? rank.left - name.right
                : name.left - rank.right;
        expect(gap.abs(), lessThan(12.0), reason: 'rank/name gap $gap');

        // Header «#» / «الفرع والمنطقة» sit exactly over the rank / branch cell.
        final rankHead = tester.getRect(find.text('#'));
        expect(rankHead.center.dx, closeTo(rank.center.dx, 1.5));
        final nameHead = tester.getRect(find.text('الفرع والمنطقة'));
        expect(nameHead.right, closeTo(name.right, 1.5));

        // The table fills the section width.
        final table =
            tester.getRect(find.byKey(const ValueKey('branch_growth_table')));
        final dt = tester.getRect(find.descendant(
            of: find.byKey(const ValueKey('branch_growth_table')),
            matching: find.byType(DataTable)));
        expect(dt.width, greaterThanOrEqualTo(table.width - 24.0 - 1.0));

        // Header centre == cell centre for each centred column.
        double cx(Finder f) => tester.getRect(f).center.dx;
        expect(
            cx(find.text('مبيعات 2026 (ج.م)')),
            closeTo(cx(find.byKey(const ValueKey('branch_growth_cur_rahab'))),
                3.0));
        expect(
            cx(find.text('مبيعات 2025 (ج.م)')),
            closeTo(cx(find.byKey(const ValueKey('branch_growth_prev_rahab'))),
                3.0));
        expect(
            cx(find.text('الفرق')),
            closeTo(cx(find.byKey(const ValueKey('branch_growth_diff_rahab'))),
                3.0));

        // 4 KPI chips: equal size, no ellipsis / clipped text.
        const labels = [
          'نمو السلسلة (2026 مقابل 2025)',
          'أسرع فرع نمواً',
          'الفروع الصاعدة',
          'تحتاج تنشيط',
        ];
        final rects = [
          for (final l in labels)
            tester.getRect(find.byKey(ValueKey('insight_badge_$l'))),
        ];
        for (final r in rects) {
          expect(r.height, closeTo(rects.first.height, 0.5));
          expect(r.width, closeTo(rects.first.width, 1.0));
        }
        for (final l in labels) {
          final badge = find.byKey(ValueKey('insight_badge_$l'));
          for (final e in find
              .descendant(of: badge, matching: find.byType(RichText))
              .evaluate()) {
            final ro = e.renderObject as RenderParagraph;
            expect(ro.didExceedMaxLines, isFalse, reason: l);
            expect(ro.text.toPlainText().contains('…'), isFalse, reason: l);
          }
          final b = tester.getRect(badge);
          for (final t in find
              .descendant(of: badge, matching: find.byType(Text))
              .evaluate()) {
            final tr = tester.getRect(find.byWidget(t.widget));
            expect(tr.left, greaterThanOrEqualTo(b.left - 0.5), reason: l);
            expect(tr.right, lessThanOrEqualTo(b.right + 0.5), reason: l);
          }
        }
        expect(tester.takeException(), isNull);
      }, _client);
    });
  }
}
