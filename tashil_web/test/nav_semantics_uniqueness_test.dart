import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:tashil_web/core/network/api_client.dart';
import 'package:tashil_web/core/testing/test_semantics.dart';
import 'package:tashil_web/core/theme/app_theme.dart';
import 'package:tashil_web/features/navigation/presentation/app_shell.dart';
import 'package:tashil_web/features/navigation/presentation/desktop_sidebar.dart';

/// Counts our instrumentation attachments (exactly one per destination).
int countNavAttachments(WidgetTester tester, String id) {
  return find
      .byWidgetPredicate(
        (w) => w is TestSemantics && w.identifier == id,
      )
      .evaluate()
      .length;
}

/// Counts engine Semantics nodes that expose [id] (findability check).
int countSemanticsIdentifiers(WidgetTester tester, String id) {
  final owner = tester.binding.pipelineOwner.semanticsOwner;
  final root = owner?.rootSemanticsNode;
  if (root == null) return 0;

  var count = 0;
  void walk(SemanticsNode node) {
    if (node.getSemanticsData().identifier == id) {
      count += 1;
    }
    node.visitChildren((child) {
      walk(child);
      return true;
    });
  }

  walk(root);
  return count;
}

Widget _shellApp(ApiClient apiClient) {
  return MaterialApp(
    theme: AppTheme.light(),
    locale: const Locale('en'),
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
      onLogout: () {},
    ),
  );
}

void main() {
  GoogleFonts.config.allowRuntimeFetching = false;

  late ApiClient apiClient;

  setUp(() {
    apiClient = ApiClient();
  });

  testWidgets(
      'DesktopSidebar attaches exactly one nav id per Sell-Out / Sell-In',
      (tester) async {
    final handle = tester.ensureSemantics();
    try {
      tester.view.physicalSize = const Size(1440, 1024);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: DesktopSidebar(
              selectedIndex: 0,
              onDestinationSelected: (_) {},
              activeTenant: 'adeco',
              onTenantChanged: (_) {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(countNavAttachments(tester, TestIds.navSellOut), 1);
      expect(countNavAttachments(tester, TestIds.navSellIn), 1);
      expect(countSemanticsIdentifiers(tester, TestIds.navSellOut), greaterThanOrEqualTo(1));
      expect(countSemanticsIdentifiers(tester, TestIds.navSellIn), greaterThanOrEqualTo(1));
    } finally {
      handle.dispose();
    }
  });

  testWidgets(
      'NavigationRail attaches exactly one interactive target per nav id',
      (tester) async {
    final handle = tester.ensureSemantics();
    try {
      tester.view.physicalSize = const Size(800, 1024);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(_shellApp(apiClient));
      await tester.pumpAndSettle();

      expect(find.byType(NavigationRail), findsOneWidget);
      expect(countNavAttachments(tester, TestIds.navSellOut), 1);
      expect(countNavAttachments(tester, TestIds.navSellIn), 1);
      expect(countSemanticsIdentifiers(tester, TestIds.navSellOut), greaterThanOrEqualTo(1));
      expect(countSemanticsIdentifiers(tester, TestIds.navSellIn), greaterThanOrEqualTo(1));
    } finally {
      handle.dispose();
    }
  });

  testWidgets(
      'Drawer exposes Sell-In id (Sell-Out stays on bottom bar only)',
      (tester) async {
    final handle = tester.ensureSemantics();
    try {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(_shellApp(apiClient));
      await tester.pumpAndSettle();

      expect(countNavAttachments(tester, TestIds.navSellOut), 1);

      final scaffoldState = tester.state<ScaffoldState>(find.byType(Scaffold));
      scaffoldState.openDrawer();
      await tester.pumpAndSettle();

      expect(find.byType(NavigationDrawer), findsOneWidget);
      // Sell-Out is not re-attached in the drawer (bottom bar owns it).
      expect(countNavAttachments(tester, TestIds.navSellOut), 1);
      expect(countNavAttachments(tester, TestIds.navSellIn), 1);
      expect(
        countSemanticsIdentifiers(tester, TestIds.navSellIn),
        greaterThanOrEqualTo(1),
      );
    } finally {
      handle.dispose();
    }
  });

  testWidgets('Compact More sheet attaches nav-sell-in once', (tester) async {
    final handle = tester.ensureSemantics();
    try {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(_shellApp(apiClient));
      await tester.pumpAndSettle();

      // Bottom bar owns Sell-Out (single attachment).
      expect(countNavAttachments(tester, TestIds.navSellOut), 1);

      await tester.tap(find.text('More'));
      await tester.pumpAndSettle();

      expect(find.text('Sell-In & Targets'), findsOneWidget);
      // Sell-In is only instrumented in the More sheet on compact layouts.
      expect(countNavAttachments(tester, TestIds.navSellIn), 1);
      expect(countSemanticsIdentifiers(tester, TestIds.navSellIn), greaterThanOrEqualTo(1));
      // Sell-Out stays only on the bottom bar (sheet does not re-attach).
      expect(countNavAttachments(tester, TestIds.navSellOut), 1);
    } finally {
      handle.dispose();
    }
  });
}
