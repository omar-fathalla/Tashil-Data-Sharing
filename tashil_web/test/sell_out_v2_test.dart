// Sell-Out M3 follow-up (v2): leftovers from the live review of v113.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tashil_web/core/widgets/m3_toolbar_button.dart';
import 'package:tashil_web/core/network/api_client.dart';
import 'package:tashil_web/core/theme/app_theme.dart';
import 'package:tashil_web/core/widgets/archive_actions_group.dart';
import 'package:tashil_web/core/widgets/m3_chip_surface.dart';
import 'package:tashil_web/core/theme/m3_spacing.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:tashil_web/features/sell_out_analytics/presentation/screens/sell_out_explorer_screen.dart';

import 'support/real_fonts.dart';

const _tabs = [
  'بيانات المبيعات',
  'أداء الفروع',
  'المستهدفات',
  'الملفات المرفوعة'
];

Future<void> _pump(WidgetTester tester, {double width = 1440}) async {
  tester.view.physicalSize = Size(width, 4000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(MaterialApp(
    theme: AppTheme.light(),
    home: Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(body: SellOutExplorerScreen(apiClient: ApiClient())),
    ),
  ));
  await tester.pumpAndSettle();
}

Future<void> _openTab(WidgetTester tester, int i) async {
  final f = find.textContaining(RegExp('^${_tabs[i]}'));
  await tester.tap(f.first);
  await tester.pumpAndSettle();
}

ColorScheme _cs(WidgetTester t) =>
    Theme.of(t.element(find.byType(SellOutExplorerScreen))).colorScheme;

BoxDecoration _deco(WidgetTester t, String key) =>
    (t.widget<Container>(find.byKey(ValueKey(key))).decoration
        as BoxDecoration);

Finder _keyPrefix(String p) => find.byWidgetPredicate((w) =>
    w.key is ValueKey<String> &&
    (w.key as ValueKey<String>).value.startsWith(p));

const _screenSrc =
    'lib/features/sell_out_analytics/presentation/screens/sell_out_explorer_screen.dart';

void main() {
  setUpAll(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    await loadRealCairoFont();
  });

  testWidgets('1. archive actions: Arabic, full-round (F1), 18dp icons',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: ArchiveActionsGroup(
                onEdit: () {}, onDownload: () {}, onDelete: () {}))));
    for (final l in ['تعديل', 'تحميل', 'حذف']) {
      expect(find.text(l), findsOneWidget);
    }
    for (final l in ['Edit', 'Download', 'Delete']) {
      expect(find.text(l), findsNothing);
    }
    final clip = tester.widget<ClipRRect>(find.descendant(
        of: find.byType(ArchiveActionsGroup),
        matching: find.byType(ClipRRect)));
    expect(clip.borderRadius, M3ToolbarButton.radius);
    for (final i in tester.widgetList<Icon>(find.descendant(
        of: find.byType(ArchiveActionsGroup), matching: find.byType(Icon)))) {
      expect(i.size, 18.0);
    }
  });

  testWidgets('1. uploaded-files actions are on screen at 1280 (no scroll)',
      (tester) async {
    // 1280dp window minus the 250dp desktop sidebar.
    const w = 1280.0 - 250.0;
    await _pump(tester, width: w);
    await _openTab(tester, 3);
    final groups = find.byType(ArchiveActionsGroup);
    expect(groups, findsWidgets);
    for (final e in groups.evaluate()) {
      final r = tester.getRect(find.byWidget(e.widget));
      expect(r.left, greaterThanOrEqualTo(0.0), reason: '$r');
      expect(r.right, lessThanOrEqualTo(w), reason: '$r');
    }
    // The pinned column lines up with the table rows.
    final table =
        tester.getRect(find.byKey(const ValueKey('uploaded_files_table')));
    final n = groups.evaluate().length;
    // Rows are 72dp so the upload date/time (and last import) can wrap.
    expect(table.height, closeTo(48.0 + 72.0 * n, 1.0));
    var i = 0;
    for (final e in groups.evaluate()) {
      final c = tester.getRect(find.byWidget(e.widget)).center.dy;
      expect(c, closeTo(table.top + 48.0 + 72.0 * i + 36.0, 1.5));
      i++;
    }
  });

  testWidgets('2. growth strip + new-branch chip use neutral roles',
      (tester) async {
    await _pump(tester);
    await _openTab(tester, 1);
    final cs = _cs(tester);
    final badges = _keyPrefix('insight_badge_');
    expect(badges, findsWidgets);
    for (final e in badges.evaluate()) {
      final d = (e.widget as Container).decoration as BoxDecoration;
      expect(
          [cs.surfaceContainerLow, cs.surfaceContainerHigh], contains(d.color));
    }
    for (final c in tester.widgetList<M3ChipSurface>(
        find.descendant(of: badges, matching: find.byType(M3ChipSurface)))) {
      expect(c.color, cs.surfaceContainerHighest);
    }
    final src = File(_screenSrc).readAsStringSync();
    expect(src.contains('tertiaryContainer.withOpacity(0.7)'), isFalse);
    expect(src.contains('primaryContainer.withOpacity(0.42)'), isFalse);
  });

  testWidgets('3/9. Targets tab: Arabic only, proper empty state',
      (tester) async {
    await _pump(tester);
    await _openTab(tester, 2);
    for (final s in const [
      'Variance',
      'Overall Achievement',
      'Actual Sell-Out',
      'Sell-Out Target',
      'Above target',
      'Below target',
      'Near target',
      'Actual Units',
      'Target Units',
    ]) {
      expect(find.textContaining(s), findsNothing, reason: s);
    }
    expect(find.text('فوق المستهدف'), findsNothing);
    expect(find.text('أقل من المستهدف'), findsNothing);
    expect(find.textContaining('لا توجد مستهدفات بعد'), findsWidgets);
  });

  testWidgets('4. text KPI values: 2 lines + tooltip, equal card heights',
      (tester) async {
    await _pump(tester, width: 1280);
    await _openTab(tester, 1);
    final values = _keyPrefix('kpi_value_');
    expect(values, findsWidgets);
    for (final e in values.evaluate()) {
      final t = e.widget as Text;
      expect(t.maxLines, 2);
      expect(
          find.ancestor(of: find.byWidget(t), matching: find.byType(Tooltip)),
          findsWidgets);
    }
    final hs = _keyPrefix('kpi_card_')
        .evaluate()
        .map((e) => tester.getSize(find.byWidget(e.widget)).height)
        .toSet();
    expect(hs.length, 1, reason: '$hs');
  });

  testWidgets('5. Targets year = سنة البيانات, filter bars share one style',
      (tester) async {
    await _pump(tester);
    await _openTab(tester, 1);
    final perf = _deco(tester, 'perf_filter_bar');
    final perfPad = tester
        .widget<Container>(find.byKey(const ValueKey('perf_filter_bar')))
        .padding;
    await _openTab(tester, 2);
    expect(find.text('سنة البيانات'), findsWidgets);
    expect(find.text('السنة'), findsNothing);
    final tgt = _deco(tester, 'targets_filter_bar');
    final tgtPad = tester
        .widget<Container>(find.byKey(const ValueKey('targets_filter_bar')))
        .padding;
    expect(tgt.color, perf.color);
    expect(tgt.borderRadius, perf.borderRadius);
    expect(tgtPad, M3Spacing.pSm);
    expect(perfPad, M3Spacing.pSm);
  });

  for (final w in [1440.0, 900.0]) {
    testWidgets('6. Targets KPI cards equal height at ${w.toInt()}',
        (tester) async {
      await _pump(tester, width: w);
      await _openTab(tester, 2);
      final cards = _keyPrefix('targets_kpi_card_');
      expect(cards.evaluate().length, 4);
      final hs = cards
          .evaluate()
          .map((e) => tester.getSize(find.byWidget(e.widget)).height)
          .toSet();
      expect(hs.length, 1, reason: '$hs');
    });
  }

  testWidgets('7. one table surface role on every tab', (tester) async {
    await _pump(tester);
    final want = _cs(tester).surfaceContainerLow;
    await _openTab(tester, 1);
    expect(_deco(tester, 'branch_velocity_section').color, want);
    expect(_deco(tester, 'branch_growth_matrix_section').color, want);
    await _openTab(tester, 2);
    expect(_deco(tester, 'targets_chain_table_section').color, want);
    await _openTab(tester, 3);
    expect(_deco(tester, 'uploaded_files_section').color, want);
    final src = File(_screenSrc).readAsStringSync();
    expect(
        src.contains(
            "key: const ValueKey('price_matrix_section'),\n      elevation: 0,\n      color: M3TableSurface.color(colorScheme),"),
        isTrue);
    final tgt = File(
            'lib/features/sell_out_analytics/presentation/widgets/target_management_panel.dart')
        .readAsStringSync();
    expect(tgt.contains('surfaceContainerLowest'), isFalse);
  });

  testWidgets('8. rank badges are 8dp chips, not circles', (tester) async {
    await _pump(tester);
    await _openTab(tester, 1);
    final badges = find.byKey(const ValueKey('branch_rank_badge'));
    expect(badges, findsWidgets);
    expect(
        find.descendant(
            of: find.byKey(const ValueKey('branch_velocity_section')),
            matching: find.byType(CircleAvatar)),
        findsNothing);
    for (final c in tester.widgetList<M3ChipSurface>(
        find.descendant(of: badges, matching: find.byType(M3ChipSurface)))) {
      expect(c.borderWidth, greaterThanOrEqualTo(0.0));
    }
  });
}
