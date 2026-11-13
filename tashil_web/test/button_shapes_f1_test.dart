import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tashil_web/core/network/api_client.dart';
import 'package:tashil_web/core/theme/app_theme.dart';
import 'package:tashil_web/core/widgets/archive_actions_group.dart';
import 'package:tashil_web/core/widgets/m3_chip_surface.dart';
import 'package:tashil_web/core/widgets/m3_toolbar_button.dart';
import 'package:tashil_web/features/cpfr_replenishment/presentation/screens/cpfr_dashboard_screen.dart';
import 'package:tashil_web/features/executive_dashboard/presentation/screens/executive_screen.dart';
import 'package:tashil_web/features/pricing_compliance/presentation/screens/pricing_compliance_screen.dart';
import 'package:tashil_web/features/sell_out_analytics/presentation/screens/sell_in_explorer_screen.dart';
import 'package:tashil_web/features/sell_out_analytics/presentation/screens/sell_out_explorer_screen.dart';
import 'package:tashil_web/features/trade_marketing/presentation/screens/trade_marketing_roi_screen.dart';

import 'trade_marketing_roi_test.dart' show FakeTradeMarketingRepository;

// F1 (owner decision): every 40dp control — filter buttons, toolbar buttons,
// segmented buttons — is full-round on every page; chips keep 8dp corners.

bool _isFullRound(ShapeBorder? s, double height) {
  if (s is StadiumBorder || s is CircleBorder) return true;
  if (s is RoundedRectangleBorder) {
    final r = s.borderRadius.resolve(TextDirection.ltr);
    return [r.topLeft, r.topRight, r.bottomLeft, r.bottomRight]
        .every((c) => c.x >= height / 2 - 0.5);
  }
  return false;
}

/// Every visible 36–44dp tall Filled/Outlined/Text/Elevated button or
/// segmented button whose painted shape is not full-round.
List<String> _nonRoundControls(WidgetTester tester) {
  final bad = <String>[];
  final buttons = find.byWidgetPredicate(
      (w) => w is ButtonStyleButton || w is SegmentedButton,
      skipOffstage: true);
  for (final e in buttons.evaluate()) {
    final box = e.renderObject as RenderBox?;
    if (box == null || !box.hasSize) continue;
    if (find
        .ancestor(
            of: find.byElementPredicate((x) => x == e),
            matching: find.byWidgetPredicate((w) =>
                w is IconButton ||
                w is MenuItemButton ||
                w is DropdownMenu ||
                w is MenuAnchor && w.builder == null))
        .evaluate()
        .isNotEmpty) {
      continue;
    }
    final ShapeBorder? shape;
    final double h;
    if (e.widget is SegmentedButton) {
      // Box includes the 48dp tap target; segments are the 40dp control.
      if (box.size.height < 36.0 || box.size.height > 56.0) continue;
      h = 40.0;
      shape = (e.widget as SegmentedButton).style?.shape?.resolve({}) ??
          Theme.of(e).segmentedButtonTheme.style?.shape?.resolve({});
    } else {
      // The painted Material, not the padded tap-target box.
      final matEl = find
          .descendant(
              of: find.byElementPredicate((x) => x == e),
              matching: find.byType(Material))
          .evaluate()
          .first;
      h = (matEl.renderObject! as RenderBox).size.height;
      if (h < 36.0 || h > 44.0) continue;
      shape = (matEl.widget as Material).shape;
    }
    if (!_isFullRound(shape, h)) {
      final txt = find
          .descendant(
              of: find.byElementPredicate((x) => x == e),
              matching: find.byType(Text))
          .evaluate()
          .map((t) => (t.widget as Text).data ?? '')
          .join(' ');
      bad.add(
          '${e.widget.runtimeType} "$txt" h=${h.toStringAsFixed(0)} $shape');
    }
  }
  return bad;
}

/// Every visible chip whose corners are not the 8dp chip shape.
List<String> _nonChipShapes(WidgetTester tester) {
  final bad = <String>[];
  for (final e in find.byType(RawChip, skipOffstage: true).evaluate()) {
    final chipTheme = ChipTheme.of(e);
    final s = (e.widget as RawChip).shape ?? chipTheme.shape;
    if (s is StadiumBorder) bad.add('RawChip stadium');
  }
  return bad;
}

Future<void> _pump(WidgetTester tester, Widget page) async {
  tester.view.physicalSize = const Size(1280, 1600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await http.runWithClient(() async {
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light(),
      locale: const Locale('ar'),
      supportedLocales: const [Locale('ar'), Locale('en')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      home: Scaffold(body: page),
    ));
    for (var i = 0; i < 15; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
  }, () => MockClient((_) async => http.Response('not found', 404)));
  tester.takeException();
}

void main() {
  GoogleFonts.config.allowRuntimeFetching = false;

  testWidgets('shared 40dp control shape is full-round; chips stay 8dp',
      (tester) async {
    expect(M3ToolbarButton.shape, isA<StadiumBorder>());
    expect(M3ToolbarButton.radius.topLeft.x, greaterThanOrEqualTo(20.0));
    expect(M3ChipStyle.radius.topLeft.x, 8.0);
    final t = AppTheme.light();
    for (final st in [
      t.filledButtonTheme.style,
      t.outlinedButtonTheme.style,
      t.textButtonTheme.style,
      t.segmentedButtonTheme.style,
    ]) {
      expect(st?.shape?.resolve({}), isA<StadiumBorder>());
    }
  });

  final pages = <String, Widget Function()>{
    'dashboard': () =>
        ExecutiveScreen(apiClient: ApiClient(tenantId: 'tenant-adeco')),
    'sell-out': () =>
        SellOutExplorerScreen(apiClient: ApiClient(tenantId: 'tenant-adeco')),
    'sell-in': () =>
        SellInExplorerScreen(apiClient: ApiClient(tenantId: 'tenant-adeco')),
    'cpfr': () =>
        CPFRDashboardScreen(apiClient: ApiClient(tenantId: 'tenant-adeco')),
    'pricing': () =>
        PricingComplianceScreen(apiClient: ApiClient(tenantId: 'tenant-adeco')),
    'trade-marketing': () => TradeMarketingRoiScreen(
        apiClient: ApiClient(), repository: FakeTradeMarketingRepository()),
  };
  for (final MapEntry(key: name, value: build) in pages.entries) {
    testWidgets('$name: every 40dp control is full-round, chips are not',
        (tester) async {
      await _pump(tester, build());
      expect(_nonRoundControls(tester), isEmpty);
      expect(_nonChipShapes(tester), isEmpty);
    });
  }

  testWidgets(
      'Sell-Out date-range control and file action group are full-round',
      (tester) async {
    await _pump(
        tester,
        Center(
          child: ArchiveActionsGroup(
              onEdit: () {}, onDownload: () {}, onDelete: () {}),
        ));
    final deco = tester
        .widgetList<Container>(find.descendant(
            of: find.byType(ArchiveActionsGroup),
            matching: find.byType(Container)))
        .map((c) => c.decoration)
        .whereType<BoxDecoration>()
        .first;
    final h = tester.getSize(find.byType(ArchiveActionsGroup)).height;
    expect((deco.borderRadius as BorderRadius).topLeft.x,
        greaterThanOrEqualTo(h / 2));

    await _pump(tester,
        SellOutExplorerScreen(apiClient: ApiClient(tenantId: 'tenant-adeco')));
    final chip = find.byKey(const ValueKey('sellout_date_range_chip'));
    expect(chip, findsWidgets);
    final ink = tester.widget<InkWell>(chip.first);
    expect((ink.borderRadius!).topLeft.x,
        greaterThanOrEqualTo(M3ToolbarButton.height / 2));
  });
}
