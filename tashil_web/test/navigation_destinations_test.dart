import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tashil_web/core/network/api_client.dart';
import 'package:tashil_web/core/theme/app_theme.dart';
import 'package:tashil_web/features/navigation/presentation/app_shell.dart';
import 'package:tashil_web/features/navigation/presentation/desktop_sidebar.dart';

void main() {
  group('Navigation Destinations Tests', () {
    late ApiClient apiClient;

    setUp(() {
      apiClient = ApiClient();
    });

    testWidgets('DesktopSidebar renders new destinations with Arabic labels and M3 icons', (WidgetTester tester) async {
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
      expect(find.text('OOS Monitor'), findsOneWidget);
      expect(find.text('Store Matrix'), findsOneWidget);
      expect(find.text('Pricing & Promos'), findsOneWidget);
      expect(find.text('Upload'), findsOneWidget);

      // Verify store matrix icon
      expect(find.byIcon(Icons.store_mall_directory_outlined), findsOneWidget);
      // Verify price change icon
      expect(find.byIcon(Icons.price_change_outlined), findsOneWidget);

      // Tap on destination 2 ('Sell-In')
      await tester.tap(find.text('Sell-In'));
      expect(selectedDestination, 2);

      // Tap on destination 4 ('Store Matrix')
      await tester.tap(find.text('Store Matrix'));
      expect(selectedDestination, 4);

      // Tap on destination 5 ('Pricing & Promos')
      await tester.tap(find.text('Pricing & Promos'));
      expect(selectedDestination, 5);

      // Tap on destination 6 ('Trade Marketing & ROI')
      await tester.tap(find.text('Trade Marketing & ROI'));
      expect(selectedDestination, 6);

      // Tap on destination 8 ('Upload' at the very bottom)
      await tester.tap(find.text('Upload'));
      expect(selectedDestination, 8);
    });

    testWidgets('AppShell switches screens when destinations 4 and 5 are selected', (WidgetTester tester) async {
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

      // Check PricingComplianceScreen is rendered
      expect(find.textContaining('Pricing & Promo Compliance'), findsOneWidget);
    });

    testWidgets('AppShell Medium Tablet (NavigationRail) switches between new destinations', (WidgetTester tester) async {
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

      // NavigationRail should be visible
      expect(find.byType(NavigationRail), findsOneWidget);
      expect(find.text('Matrix'), findsOneWidget);
      expect(find.text('Pricing'), findsOneWidget);

      // Tap on 'Matrix' (Store Matrix)
      await tester.tap(find.byIcon(Icons.store_mall_directory_outlined));
      await tester.pumpAndSettle();
      expect(find.textContaining('Store Matrix Benchmarking'), findsOneWidget);

      // Tap on 'Pricing' (Pricing Compliance)
      await tester.tap(find.byIcon(Icons.price_change_outlined));
      await tester.pumpAndSettle();
      expect(find.textContaining('Pricing & Promo Compliance'), findsOneWidget);
    });

    testWidgets('AppShell Compact Mobile (Drawer) navigates to new destinations', (WidgetTester tester) async {
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
