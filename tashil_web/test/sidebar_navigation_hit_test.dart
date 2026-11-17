// Live v187: Pricing → Compare sidebar mouse click must navigate at 1280×800.
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tashil_web/core/theme/app_theme.dart';
import 'package:tashil_web/features/competitor_comparison/presentation/screens/competitor_comparison_screen.dart';
import 'package:tashil_web/features/navigation/presentation/app_shell.dart';
import 'package:tashil_web/features/navigation/presentation/desktop_sidebar.dart';
import 'package:tashil_web/features/oos_monitor/presentation/screens/oos_dashboard_screen.dart';
import 'package:tashil_web/features/pricing_compliance/presentation/screens/pricing_compliance_screen.dart';

import 'pricing_m3_support.dart' as pricing_support;
import 'support/product_master_m3_support.dart' show ignoreGoogleFontLoadErrors;
import 'support/real_fonts.dart';

Future<void> _pumpShell(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1280, 800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(MaterialApp(
    theme: AppTheme.light(),
    locale: const Locale('ar'),
    supportedLocales: const [Locale('ar'), Locale('en')],
    localizationsDelegates: const [
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    home: AppShell(
      apiClient: pricing_support.PricingShotApiClient(),
      activeTenant: 'adeco',
      onTenantChanged: (_) {},
    ),
  ));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
}

Finder _sidebarLabel(String label) => find.descendant(
      of: find.byType(DesktopSidebar),
      matching: find.text(label),
    );

Finder _sidebarNav(String label) => find.byKey(ValueKey('sidebar_nav_$label'));

Future<void> _mouseTap(WidgetTester tester, Finder finder) async {
  expect(finder, findsOneWidget);
  final list = find.descendant(
    of: find.byType(DesktopSidebar),
    matching: find.byType(Scrollable),
  );
  await tester.scrollUntilVisible(finder, 48.0, scrollable: list.first);
  await tester.pump();
  final center = tester.getCenter(finder);
  final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
  await gesture.addPointer(location: center);
  await tester.pump();
  await gesture.down(center);
  await tester.pump();
  await gesture.up();
  await gesture.removePointer();
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
}

void main() {
  ignoreGoogleFontLoadErrors();
  setUpAll(() async {
    await loadRealCairoFont();
    await pricing_support.loadPricingFonts();
  });

  testWidgets(
      'AppShell 1280x800: mouse tap sidebar Compare from Pricing navigates',
      (tester) async {
    await _pumpShell(tester);

    await _mouseTap(tester, _sidebarLabel('Pricing & Promos'));
    expect(find.byType(PricingComplianceScreen), findsOneWidget);
    expect(_sidebarNav('Pricing & Promos'), findsOneWidget);

    // Control: OOS from Pricing still works (owner confirmed this path).
    await _mouseTap(tester, _sidebarLabel('OOS Monitor'));
    expect(find.byType(OOSDashboardScreen), findsOneWidget);

    await _mouseTap(tester, _sidebarLabel('Pricing & Promos'));
    expect(find.byType(PricingComplianceScreen), findsOneWidget);

    // Failure path: Compare from Pricing stayed on Pricing in live v187.
    await _mouseTap(tester, _sidebarNav('Compare'));
    expect(
      find.byType(CompetitorComparisonScreen),
      findsOneWidget,
      reason: 'Pricing → Compare sidebar mouse tap must change route',
    );
    expect(find.byType(PricingComplianceScreen), findsNothing);
  });

  testWidgets(
      'AppShell 1280x800: Compare sidebar item owns button semantics onTap',
      (tester) async {
    await _pumpShell(tester);
    await _mouseTap(tester, _sidebarLabel('Pricing & Promos'));
    expect(find.byType(PricingComplianceScreen), findsOneWidget);

    final compare = _sidebarNav('Compare');
    expect(compare, findsOneWidget);
    final sem = tester.getSemantics(compare);
    expect(
      sem,
      matchesSemantics(
        label: 'Compare',
        isButton: true,
        hasTapAction: true,
      ),
    );

    // Invoke the semantics action (web flt-semantics click path).
    final owner = tester.binding.pipelineOwner.semanticsOwner;
    expect(owner, isNotNull);
    owner!.performAction(sem.id, SemanticsAction.tap);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(CompetitorComparisonScreen), findsOneWidget);
  });
}
