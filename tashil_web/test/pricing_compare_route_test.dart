// Regression: from Pricing location, Compare sidebar destination must change
// the shell page and must not bounce back (live v188 / #186 widget tap passed
// but production Chrome still stayed on Pricing).
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tashil_web/core/theme/app_theme.dart';
import 'package:tashil_web/core/testing/test_semantics.dart';
import 'package:tashil_web/features/competitor_comparison/presentation/screens/competitor_comparison_screen.dart';
import 'package:tashil_web/features/navigation/app_page_route.dart';
import 'package:tashil_web/features/navigation/presentation/app_shell.dart';
import 'package:tashil_web/features/navigation/presentation/desktop_sidebar.dart';
import 'package:tashil_web/features/pricing_compliance/presentation/screens/pricing_compliance_screen.dart';
import 'package:tashil_web/core/testing/web_automation_semantics.dart';

import 'pricing_m3_support.dart' as pricing_support;
import 'support/product_master_m3_support.dart' show ignoreGoogleFontLoadErrors;
import 'support/real_fonts.dart';

const _pricingIndex = 6;
const _compareIndex = 7;

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

void main() {
  ignoreGoogleFontLoadErrors();
  setUpAll(() async {
    await loadRealCairoFont();
    await pricing_support.loadPricingFonts();
  });

  test('AppPageRoute: pricing and compare are distinct slugs/indexes', () {
    expect(AppPageRoute.indexForSlug('pricing'), _pricingIndex);
    expect(AppPageRoute.indexForSlug('compare'), _compareIndex);
    expect(AppPageRoute.slugForIndex(_pricingIndex), 'pricing');
    expect(AppPageRoute.slugForIndex(_compareIndex), 'compare');
    expect(AppPageRoute.pathFor('adeco', 'pricing'), '/adeco/pricing');
    expect(AppPageRoute.pathFor('adeco', 'compare'), '/adeco/compare');
    expect(
      AppPageRoute.pathFor('adeco', 'compare'),
      isNot(AppPageRoute.pathFor('adeco', 'pricing')),
    );
    expect(TestIds.navIdForIndex(_pricingIndex), TestIds.navPricing);
    expect(TestIds.navIdForIndex(_compareIndex), TestIds.navCompare);
  });

  test('webAutomationSemanticsRequested is opt-in via query only', () {
    // VM / non-web: never force the glass pane.
    expect(webAutomationSemanticsRequested(), isFalse);
  });

  testWidgets(
      'from Pricing location, Compare sidebar destination changes page and stays',
      (tester) async {
    await _pumpShell(tester);

    // Same callback path the sidebar InkWell / Semantics onTap uses — not a
    // Finder.tap on a label (that only exercises canvas hit-testing).
    final select = tester
        .widget<DesktopSidebar>(find.byType(DesktopSidebar))
        .onDestinationSelected;

    select(_pricingIndex);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.byType(PricingComplianceScreen), findsOneWidget);
    expect(find.byType(CompetitorComparisonScreen), findsNothing);

    // Re-read callback after rebuild (fresh closure over AppShell state).
    tester
        .widget<DesktopSidebar>(find.byType(DesktopSidebar))
        .onDestinationSelected(_compareIndex);
    await tester.pump();
    // Settle fade-through + extra frames that would reveal a redirect bounce.
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump(const Duration(seconds: 1));

    expect(
      find.byType(CompetitorComparisonScreen),
      findsOneWidget,
      reason: 'Pricing → Compare destination must show Compare',
    );
    expect(
      find.byType(PricingComplianceScreen),
      findsNothing,
      reason: 'must not bounce back to Pricing after Compare select',
    );
    expect(
      AppPageRoute.pathFor('adeco', AppPageRoute.slugForIndex(_compareIndex)),
      '/adeco/compare',
    );
  });
}
