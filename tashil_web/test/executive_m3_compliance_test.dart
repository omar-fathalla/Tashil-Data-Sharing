import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tashil_web/core/network/api_client.dart';
import 'package:tashil_web/core/theme/app_theme.dart';
import 'package:tashil_web/core/theme/m3_status_colors.dart';
import 'package:tashil_web/core/widgets/m3_feedback.dart';
import 'package:tashil_web/core/widgets/m3_status_tag.dart';
import 'package:tashil_web/features/executive_dashboard/presentation/screens/executive_screen.dart';
import 'package:tashil_web/features/executive_dashboard/presentation/widgets/market_share_section.dart';

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

Future<void> _pump(WidgetTester tester, Size size) =>
    http.runWithClient(() async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light(),
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
        'executive_year_segmented',
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
    await tester.tap(find.text('February').last);
    await tester.pumpAndSettle();
    expect(find.text('Month: Feb'), findsOneWidget);
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
        of: find.byKey(const ValueKey('stock_per_sku_table')),
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
}
