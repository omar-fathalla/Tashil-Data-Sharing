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
import 'package:tashil_web/core/theme/m3_status_colors.dart';
import 'package:tashil_web/core/widgets/m3_feedback.dart';
import 'package:tashil_web/core/widgets/kpi_card.dart';
import 'package:tashil_web/core/widgets/m3_status_tag.dart';
import 'package:tashil_web/core/widgets/m3_tonal_surface.dart';
import 'package:tashil_web/features/executive_dashboard/presentation/screens/executive_screen.dart';
import 'package:tashil_web/features/executive_dashboard/presentation/widgets/market_share_section.dart';
import 'package:tashil_web/features/executive_dashboard/presentation/widgets/sellout_trend_chart.dart';

/// M3 compliance checks for the Executive Overview (/adeco): control sizes,
/// tap targets, contrast of competitor shades and the error snackbar.

final _cpfrFixture = {
  'monthly_reconciliation': [
    {
      'year': 2026,
      'month_num': 1,
      'month_en': 'January',
      'has_actual_sell_out': true,
      'sell_in_units': 5200,
      'sell_out_units': 4100,
    },
  ],
  'inventory_and_po_items': [
    for (final (i, st)
        in ['optimal', 'overstock', 'urgent_replenishment'].indexed)
      {
        'barcode': '$i',
        'item_code': 'A$i',
        'sku_name': 'Test SKU $i',
        'sell_in_units': 900,
        'sell_out_units': 820,
        'estimated_stock_units': 80,
        'sell_through_pct': 91.1,
        'stock_status': st,
      },
  ],
};

MockClient _client() => MockClient((req) async {
      if (req.url.path.endsWith('/api/v1/analytics/cpfr')) {
        return http.Response(jsonEncode(_cpfrFixture), 200,
            headers: {'content-type': 'application/json; charset=utf-8'});
      }
      return http.Response('not found', 404);
    });

Future<void> _pump(WidgetTester tester, Size size, {bool rtl = false}) =>
    http.runWithClient(() async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light(),
        // The portal runs in Arabic (RTL); v2 layout checks opt in.
        builder: rtl
            ? (context, child) => Directionality(
                textDirection: TextDirection.rtl, child: child!)
            : null,
        home: Scaffold(
          body: ExecutiveScreen(apiClient: ApiClient(tenantId: 'tenant-adeco')),
        ),
      ));
      await tester.pumpAndSettle();
    }, _client);

double _contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final hi = la > lb ? la : lb;
  final lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

void main() {
  GoogleFonts.config.allowRuntimeFetching = false;

  for (final size in const [Size(1440, 900), Size(390, 844)]) {
    testWidgets(
        'Executive header controls are ≥ 40dp with 48dp targets at '
        '${size.width.toInt()}px', (tester) async {
      await _pump(tester, size);
      expect(tester.takeException(), isNull);
      for (final k in const [
        'executive_period_segmented',
        'executive_year_dropdown',
        'executive_chain_dropdown',
        'executive_month_dropdown',
      ]) {
        final finder = find.byKey(ValueKey(k));
        expect(finder, findsOneWidget, reason: k);
        expect(tester.getSize(finder).height, greaterThanOrEqualTo(40.0),
            reason: k);
      }
      // Chain/Month triggers are real M3 buttons (focusable, state layers).
      for (final k in const [
        'executive_chain_dropdown',
        'executive_month_dropdown'
      ]) {
        final w = tester.widget(find.byKey(ValueKey(k)));
        expect(w is OutlinedButton || w is FilledButton, isTrue, reason: k);
      }
      if (size.width >= 600) {
        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      }
    });
  }

  testWidgets('Quarter segmented is ≥ 40dp', (tester) async {
    await _pump(tester, const Size(1440, 900));
    await tester.tap(find.text('ربع سنوي'));
    await tester.pumpAndSettle();
    final q = find.byKey(const ValueKey('executive_quarter_segmented'));
    expect(q, findsOneWidget);
    expect(tester.getSize(q).height, greaterThanOrEqualTo(40.0));
  });

  testWidgets('Active chain/month filter turns the trigger tonal',
      (tester) async {
    await _pump(tester, const Size(1440, 900));
    expect(
        tester.widget(find.byKey(const ValueKey('executive_month_dropdown'))),
        isA<OutlinedButton>());
    await tester.tap(find.byKey(const ValueKey('executive_month_dropdown')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('فبراير').last);
    await tester.pumpAndSettle();
    expect(find.text('الشهر: فبراير'), findsOneWidget);
    expect(
        tester.widget(find.byKey(const ValueKey('executive_month_dropdown'))),
        isA<FilledButton>());
  });

  test(
      'Segmented selection uses secondaryContainer; primary is not legacy blue',
      () {
    final theme = AppTheme.light();
    final bg = theme.segmentedButtonTheme.style?.backgroundColor
        ?.resolve({WidgetState.selected});
    expect(bg, theme.colorScheme.secondaryContainer);
    expect(theme.colorScheme.primary.toARGB32() & 0xFFFFFF, isNot(0x1565C0));
  });

  test('Competitor shades are ≥ 3:1 on surface', () {
    final cs = AppTheme.light().colorScheme;
    const acc = M3AccentRoles.light;
    for (final c in [acc.competitorStrong, acc.competitor, cs.outline]) {
      expect(_contrast(c, cs.surface), greaterThanOrEqualTo(3.0),
          reason: c.toString());
    }
  });

  testWidgets('Error snackbar is theme inverseSurface with a ≥ 3:1 icon',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => M3Feedback.showError(context, 'x'),
            child: const Text('go'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('go'));
    await tester.pump();
    final bar = tester.widget<SnackBar>(find.byType(SnackBar));
    expect(bar.backgroundColor, isNull);
    final cs = AppTheme.light().colorScheme;
    final icon = tester.widget<Icon>(find.descendant(
        of: find.byType(SnackBar), matching: find.byType(Icon)));
    expect(
        _contrast(icon.color!, cs.inverseSurface), greaterThanOrEqualTo(3.0));
  });

  testWidgets('Inventory status tags meet text contrast', (tester) async {
    await _pump(tester, const Size(1440, 1400));
    expect(find.byType(MarketShareSection), findsOneWidget);
    final tags = find.descendant(
        of: find.descendant(
            of: find.byKey(const ValueKey('stock_per_sku_table')),
            matching: find.byType(Table)),
        matching: find.byType(M3StatusTag));
    expect(tags, findsNWidgets(3));
    for (final label in ['Healthy', 'Overstock', 'Replenish']) {
      expect(find.text(label), findsOneWidget);
    }
    // Pixel-sampling textContrastGuideline is unreliable with test fonts, so
    // check the resolved role pairs used by each tag directly.
    final ctx = tester.element(tags.first);
    final status = M3StatusColors.of(ctx);
    final cs = Theme.of(ctx).colorScheme;
    for (final (bg, fg) in [
      (status.successContainer, status.onSuccessContainer),
      (status.warningContainer, status.onWarningContainer),
      (cs.errorContainer, cs.onErrorContainer),
    ]) {
      expect(_contrast(fg, bg), greaterThanOrEqualTo(4.5));
    }
    for (final t in tester.widgetList<Text>(
        find.descendant(of: tags, matching: find.byType(Text)))) {
      expect(t.style?.color, isNotNull);
    }
  });

  // ---------------------------------------------------------------- v2 ----
  for (final size in const [Size(1440, 900), Size(1024, 768), Size(390, 844)]) {
    testWidgets(
        'v2 header @${size.width.toInt()}: 40dp controls, single-line equal '
        'segments, no overflow', (tester) async {
      await _pump(tester, size, rtl: true);
      expect(tester.takeException(), isNull);
      for (final k in const [
        'executive_period_segmented',
        'executive_month_dropdown',
        'executive_year_dropdown',
        'executive_chain_dropdown',
      ]) {
        expect(tester.getSize(find.byKey(ValueKey(k))).height,
            greaterThanOrEqualTo(40.0),
            reason: '$k@$size');
      }
      // One line (labelLarge line height 20).
      expect(tester.getSize(find.text('ربع سنوي')).height,
          lessThanOrEqualTo(20.0 + 0.5));
      final segs = find.descendant(
          of: find.byKey(const ValueKey('executive_period_segmented')),
          matching: find.byType(TextButton));
      expect(segs, findsNWidgets(3));
      final widths = [
        for (final e in segs.evaluate()) (e.renderObject! as RenderBox).size.width
      ];
      for (final w in widths) {
        expect(w, closeTo(widths.first, 0.5));
        expect(w, greaterThanOrEqualTo(112.0));
      }
      if (size.width >= 600) {
        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      }
    });
  }

  testWidgets('v2 header: Arabic labels, one button family, 8dp gaps',
      (tester) async {
    await _pump(tester, const Size(1440, 900), rtl: true);
    expect(find.text('الشهر: الكل'), findsOneWidget);
    expect(find.textContaining(RegExp(r'^السنة: \d{4}$')), findsOneWidget);
    expect(find.text('السلسلة: الكل'), findsOneWidget);
    expect(find.textContaining(RegExp(r'^(Chain|Month): ')), findsNothing);
    expect(find.byKey(const ValueKey('executive_year_segmented')), findsNothing);
    // Year at its default → outlined, like the other filters.
    expect(tester.widget(find.byKey(const ValueKey('executive_year_dropdown'))),
        isA<OutlinedButton>());
    final month =
        tester.getRect(find.byKey(const ValueKey('executive_month_dropdown')));
    final year =
        tester.getRect(find.byKey(const ValueKey('executive_year_dropdown')));
    final chain =
        tester.getRect(find.byKey(const ValueKey('executive_chain_dropdown')));
    // RTL: month is right of year, year right of chain; 8dp apart.
    expect(month.left - year.right, closeTo(8.0, 0.5));
    expect(year.left - chain.right, closeTo(8.0, 0.5));
    // 1440: title on top, the controls one full row below it.
    expect(month.top, closeTo(chain.top, 0.5));
    final seg = tester
        .getRect(find.byKey(const ValueKey('executive_period_segmented')));
    expect(seg.center.dy, closeTo(month.center.dy, 1.0));
    expect(seg.top,
        greaterThan(tester.getRect(find.text('أداء المبيعات في سلاسل التجزئة')).bottom));
    final ctx =
        tester.element(find.byKey(const ValueKey('executive_chain_dropdown')));
    final cs = Theme.of(ctx).colorScheme;
    final theme = Theme.of(ctx);
    // Outlined border = outline (≥ 3:1); focus ring = 3dp secondary.
    final side = theme.outlinedButtonTheme.style!.side!;
    expect(side.resolve(<WidgetState>{})!.color, cs.outline);
    final ring = side.resolve({WidgetState.focused})!;
    expect(ring.width, 3.0);
    expect(ring.color, cs.secondary);
    expect(_contrast(cs.secondary, cs.surface), greaterThanOrEqualTo(3.0));
    expect(_contrast(cs.outline, cs.surface), greaterThanOrEqualTo(3.0));
    final segRing = theme.segmentedButtonTheme.style!.side!
        .resolve({WidgetState.focused})!;
    expect(segRing.width, 3.0);
  });

  testWidgets('v2 layout: row A = SKU + stock, row B = category + monthly',
      (tester) async {
    await _pump(tester, const Size(1440, 1400), rtl: true);
    Rect r(String k) => tester.getRect(find.byKey(ValueKey(k)));
    expect(r('share_per_sku_card').top, closeTo(r('stock_per_sku_table').top, 1));
    expect(r('share_per_sku_card').height,
        closeTo(r('stock_per_sku_table').height, 1));
    expect(r('share_per_category_card').top,
        closeTo(r('sell_in_vs_out_chart').top, 1));
    expect(r('share_per_category_card').top,
        greaterThan(r('share_per_sku_card').bottom));
    // RTL: the SKU / category cards sit at the start (right).
    expect(r('share_per_sku_card').left,
        greaterThan(r('stock_per_sku_table').right - 1));
    // Tiles full width between the rows.
    expect(r('sell_in_vs_out_section').top,
        greaterThanOrEqualTo(r('stock_per_sku_table').bottom));
    expect(r('share_per_category_card').top,
        greaterThanOrEqualTo(r('sell_in_vs_out_section').bottom));
    // SKU name titleSmall 14 / w500 / onSurface; category bodySmall 12.
    final ctx = tester.element(find.byKey(const ValueKey('stock_per_sku_table')));
    final cs = Theme.of(ctx).colorScheme;
    final name = tester.widget<Text>(find.text('Test SKU 0'));
    expect(name.style?.fontSize, 14.0);
    expect(name.style?.fontWeight, FontWeight.w500);
    expect(name.style?.color, cs.onSurface);
    expect(name.maxLines, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('v2 trend chart: axis labels are one line with a space',
      (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(
        body: SingleChildScrollView(
          child: SelloutTrendChart(trends: [
            for (var m = 1; m <= 6; m++)
              DailyTrendItem(
                date: '2026-${m.toString().padLeft(2, '0')}-01',
                monthKey: '2026-${m.toString().padLeft(2, '0')}',
                revenue: 12.0e6 + m * 1.2e6,
                units: 1000,
                storeCount: 3,
              ),
          ]),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('الاتجاه الشهري (\u2068Sell-Out\u2069)'), findsOneWidget);
    final labels = find.descendant(
        of: find.byType(SelloutTrendChart),
        matching: find.textContaining('مليون ج.م'));
    expect(labels, findsWidgets);
    for (final e in labels.evaluate()) {
      final t = e.widget as Text;
      expect(t.maxLines, 1);
      expect(t.softWrap, isFalse);
      expect(t.data, contains(' مليون'));
      expect(t.data, isNot(contains(RegExp(r'\dمليون'))));
      final rp = tester.renderObject<RenderParagraph>(
          find.descendant(of: find.byWidget(t), matching: find.byType(RichText)));
      expect(rp.size.height, lessThanOrEqualTo(16.0 + 0.5));
    }
  });

  testWidgets('v2 M3TonalSurface(onTap): button semantics, 48dp, focus ring',
      (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(
        body: Center(
          child: M3TonalSurface(
            key: const ValueKey('ts'),
            color: Colors.white,
            onTap: () {},
            child: const Text('صف'),
          ),
        ),
      ),
    ));
    expect(tester.getSize(find.byKey(const ValueKey('ts'))).height,
        greaterThanOrEqualTo(48.0));
    expect(
        tester.getSemantics(find.text('صف')),
        isSemantics(isButton: true, hasTapAction: true, isFocusable: true,
            label: 'صف'));
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    final deco = tester
        .widgetList<DecoratedBox>(find.descendant(
            of: find.byKey(const ValueKey('ts')),
            matching: find.byType(DecoratedBox)))
        .map((d) => d.decoration)
        .whereType<ShapeDecoration>()
        .first;
    final shape = deco.shape as OutlinedBorder;
    final cs = AppTheme.light().colorScheme;
    expect(shape.side.width, 3.0);
    expect(shape.side.color, cs.secondary);
    handle.dispose();
  });

  testWidgets('v2 KpiCard: no bold, icon + title row, neutral tags',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light(),
      home: const Scaffold(
        body: KpiCard(
          title: 'إجمالي Sell-Out',
          value: '127.14M ج.م',
          subtitle: 's',
          icon: Icons.payments_rounded,
          growthPct: 1,
          badgeLabel: '+21.8% مقارنة بالشهر السابق',
          secondaryBadgeLabel: '0% مقارنة بالعام السابق',
          isPositive: true,
        ),
      ),
    ));
    final cs = AppTheme.light().colorScheme;
    for (final t in tester.widgetList<Text>(find.byType(Text))) {
      expect(t.style?.fontWeight, isNot(anyOf(FontWeight.w700, FontWeight.w800,
          FontWeight.w900)), reason: t.data);
    }
    final value = tester.widget<Text>(find.text('127.14M ج.م'));
    expect(value.style?.fontWeight, FontWeight.w400);
    final tags = tester.widgetList<M3StatusTag>(find.byType(M3StatusTag));
    expect(tags.length, 2);
    expect(tags.every((t) => t.tone == M3StatusTone.neutral), isTrue);
    expect(_contrast(cs.onSurfaceVariant, cs.surfaceContainerLowest),
        greaterThanOrEqualTo(4.5));
  });

  test('v2 tonalSpot scheme from #35A211', () {
    final cs = AppTheme.light().colorScheme;
    expect(cs.primary, const Color(0xFF426834));
    expect(cs.secondaryContainer, const Color(0xFFD8E7CC));
    expect(cs.surface, const Color(0xFFF8FAF0));
    expect(_contrast(cs.onPrimary, cs.primary), greaterThanOrEqualTo(4.5));
    expect(_contrast(cs.onSecondaryContainer, cs.secondaryContainer),
        greaterThanOrEqualTo(4.5));
    expect(_contrast(cs.onTertiaryContainer, cs.tertiaryContainer),
        greaterThanOrEqualTo(4.5));
  });
}
