import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tashil_web/core/network/api_client.dart';
import 'package:tashil_web/core/theme/app_theme.dart';
import 'package:tashil_web/features/navigation/presentation/app_shell.dart';
import 'package:tashil_web/features/navigation/presentation/desktop_sidebar.dart';
import 'package:tashil_web/features/navigation/presentation/narrow_sidebar.dart';

void main() {
  group('Navigation Destinations Tests', () {
    late ApiClient apiClient;

    setUp(() {
      apiClient = ApiClient();
    });

    testWidgets(
        'DesktopSidebar renders new destinations with Arabic labels and M3 icons',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1440, 1024);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      int selectedDestination = 0;

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          locale: const Locale('ar'),
          supportedLocales: const [Locale('ar'), Locale('en')],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: Scaffold(
            body: DesktopSidebar(
              selectedIndex: selectedDestination,
              onDestinationSelected: (idx) => selectedDestination = idx,
              activeTenant: 'adeco',
              onTenantChanged: (_) {},
            ),
          ),
        ),
      );

      // Verify destination labels exist
      expect(find.text('Dashboard'), findsOneWidget);
      expect(find.text('Sell-Out'), findsOneWidget);
      expect(find.text('Sell-In'), findsOneWidget);
      expect(find.text('Returns'), findsOneWidget);
      expect(find.text('OOS Monitor'), findsOneWidget);
      expect(find.text('Store Matrix'), findsOneWidget);
      expect(find.text('Pricing & Promos'), findsOneWidget);
      expect(find.text('الإدخالات'), findsOneWidget);
      expect(find.text('التسويق'), findsOneWidget);
      expect(find.text('التحليلات'), findsOneWidget);
      expect(find.text('النظام'), findsOneWidget);
      expect(find.text('Upload'), findsNothing);

      // Verify store matrix icon
      expect(find.byIcon(Icons.store_mall_directory_rounded), findsWidgets);
      // Verify price change icon
      expect(find.byIcon(Icons.price_change_rounded), findsWidgets);
      // Verify Returns icon (index 3 — المرتجعات)
      expect(find.byIcon(Icons.assignment_return_rounded), findsWidgets);

      Future<void> tapLabel(String label) async {
        final item = find.text(label);
        await tester.ensureVisible(item);
        await tester.tap(item);
      }

      // Route indexes stay stable even though the menu is grouped.
      await tapLabel('Sell-In');
      expect(selectedDestination, 2);

      await tapLabel('Returns');
      expect(selectedDestination, 3);

      await tapLabel('Store Matrix');
      expect(selectedDestination, 5);

      await tapLabel('Pricing & Promos');
      expect(selectedDestination, 6);

      await tapLabel('Compare');
      expect(selectedDestination, 7);

      await tapLabel('Trade Marketing & ROI');
      expect(selectedDestination, 8);

      await tapLabel('CPFR Replenishment');
      expect(selectedDestination, 9);

      await tapLabel('Product Master');
      expect(selectedDestination, 11);

      await tapLabel('Errors');
      expect(selectedDestination, 12);
    });

    testWidgets(
        'AppShell switches screens when destinations 4 and 5 are selected',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1440, 1024);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          locale: const Locale('ar'),
          supportedLocales: const [Locale('ar'), Locale('en')],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: AppShell(
            apiClient: apiClient,
            activeTenant: 'adeco',
            onTenantChanged: (_) {},
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Tap on 'Store Matrix'
      await tester.tap(find.text('Store Matrix'));
      await tester.pumpAndSettle();

      // Check StoreMatrixScreen is rendered
      expect(find.textContaining('Store Matrix Benchmarking'), findsOneWidget);

      // Tap on 'Pricing & Promos'
      await tester.tap(find.text('Pricing & Promos'));
      await tester.pumpAndSettle();

      // Check PricingComplianceScreen is rendered (short title matches sidebar)
      expect(find.text('Pricing & Promos'), findsWidgets);
    });

    testWidgets(
        'AppShell Medium Tablet (NavigationRail) switches between new destinations',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(800, 1024);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          locale: const Locale('ar'),
          supportedLocales: const [Locale('ar'), Locale('en')],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: AppShell(
            apiClient: apiClient,
            activeTenant: 'adeco',
            onTenantChanged: (_) {},
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Narrow sidebar (collapsed rail) should be visible.
      final rail = find.byType(NarrowSidebar);
      expect(rail, findsOneWidget);
      expect(find.byType(NavigationRail), findsNothing);
      expect(
        find.descendant(of: rail, matching: find.text('Upload')),
        findsNothing,
      );
      expect(
        find.descendant(
          of: rail,
          matching: find.byKey(const ValueKey('nav_section_divider_inputs')),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(of: rail, matching: find.text('الإدخالات')),
        findsNothing,
      );
      expect(find.text('Matrix'), findsOneWidget);
      expect(find.text('Pricing'), findsOneWidget);

      // Tap on 'Matrix' (Store Matrix)
      await tester.tap(find.text('Matrix'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Store Matrix Benchmarking'), findsOneWidget);

      // Tap on 'Pricing' (Pricing Compliance)
      await tester.tap(find.text('Pricing'));
      await tester.pumpAndSettle();
      expect(find.text('Pricing & Promos'), findsWidgets);
    });

    testWidgets(
        'AppShell Compact Mobile (Drawer) navigates to new destinations',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          locale: const Locale('ar'),
          supportedLocales: const [Locale('ar'), Locale('en')],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: AppShell(
            apiClient: apiClient,
            activeTenant: 'adeco',
            onTenantChanged: (_) {},
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Open drawer using the scaffold's leading hamburger or drawer drag
      final scaffoldState = tester.state<ScaffoldState>(find.byType(Scaffold));
      scaffoldState.openDrawer();
      await tester.pumpAndSettle();

      // Verify drawer items exist
      expect(find.text('Store Matrix'), findsOneWidget);
      expect(find.text('Pricing & Promos'), findsOneWidget);

      // Tap on 'Store Matrix'
      await tester.tap(find.text('Store Matrix'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Store Matrix Benchmarking'), findsOneWidget);
    });
  });
}
