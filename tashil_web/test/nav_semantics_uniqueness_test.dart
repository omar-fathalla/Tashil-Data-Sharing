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
import 'package:tashil_web/features/navigation/presentation/narrow_sidebar.dart';

/// Counts deepest Semantics nodes that expose [id] (no descendant with the
/// same id). Material parents may copy an identifier upward; deepest nodes are
/// the real interactive targets.
int countInteractiveTargets(WidgetTester tester, String id) {
  final owner = tester.binding.pipelineOwner.semanticsOwner;
  final root = owner?.rootSemanticsNode;
  if (root == null) return 0;

  final matches = <SemanticsNode>[];
  void walk(SemanticsNode node) {
    if (node.getSemanticsData().identifier == id) {
      matches.add(node);
    }
    node.visitChildren((child) {
      walk(child);
      return true;
    });
  }

  walk(root);

  bool hasDescendantWithId(SemanticsNode node) {
    var found = false;
    void check(SemanticsNode n) {
      if (n.getSemanticsData().identifier == id) {
        found = true;
        return;
      }
      n.visitChildren((c) {
        if (!found) check(c);
        return !found;
      });
    }

    node.visitChildren((c) {
      check(c);
      return !found;
    });
    return found;
  }

  return matches.where((n) => !hasDescendantWithId(n)).length;
}

/// Sell-Out explorer overflows narrow viewports; ignore those layout reports.
void ignoreRenderFlexOverflows() {
  final previous = FlutterError.onError;
  FlutterError.onError = (details) {
    if (details.exceptionAsString().contains('A RenderFlex overflowed')) {
      return;
    }
    previous?.call(details);
  };
  addTearDown(() {
    FlutterError.onError = previous;
  });
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
      'DesktopSidebar has exactly one interactive nav-sell-out / nav-sell-in',
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

      expect(countInteractiveTargets(tester, TestIds.navSellOut), 1);
      expect(countInteractiveTargets(tester, TestIds.navSellIn), 1);

      await tester.tap(find.text('Sell-Out'));
      await tester.pumpAndSettle();
      expect(countInteractiveTargets(tester, TestIds.navSellOut), 1);
      expect(countInteractiveTargets(tester, TestIds.navSellIn), 1);
    } finally {
      handle.dispose();
    }
  });

  testWidgets(
      'Narrow sidebar has exactly one interactive target per nav id '
      '(including when Sell-Out is selected)', (tester) async {
    final handle = tester.ensureSemantics();
    ignoreRenderFlexOverflows();
    try {
      tester.view.physicalSize = const Size(800, 1024);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(_shellApp(apiClient));
      await tester.pumpAndSettle();

      expect(find.byType(NarrowSidebar), findsOneWidget);
      expect(countInteractiveTargets(tester, TestIds.navSellOut), 1);
      expect(countInteractiveTargets(tester, TestIds.navSellIn), 1);

      await tester.tap(find.text('Sell-Out'));
      await tester.pumpAndSettle();

      expect(countInteractiveTargets(tester, TestIds.navSellOut), 1);
      expect(countInteractiveTargets(tester, TestIds.navSellIn), 1);
    } finally {
      handle.dispose();
    }
  });

  testWidgets(
      'Compact bottom bar keeps exactly one nav-sell-out when Sell-Out selected',
      (tester) async {
    final handle = tester.ensureSemantics();
    ignoreRenderFlexOverflows();
    try {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(_shellApp(apiClient));
      await tester.pumpAndSettle();

      expect(find.byType(NavigationBar), findsOneWidget);
      expect(countInteractiveTargets(tester, TestIds.navSellOut), 1);

      await tester.tap(find.text('Sell-Out'));
      await tester.pumpAndSettle();

      // selectedIcon is also tagged — id must remain exactly once when selected.
      expect(countInteractiveTargets(tester, TestIds.navSellOut), 1);
    } finally {
      handle.dispose();
    }
  });

  testWidgets('Drawer exposes exactly one interactive nav-sell-in',
      (tester) async {
    final handle = tester.ensureSemantics();
    ignoreRenderFlexOverflows();
    try {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(_shellApp(apiClient));
      await tester.pumpAndSettle();

      // Bottom bar owns Sell-Out before the drawer opens.
      expect(countInteractiveTargets(tester, TestIds.navSellOut), 1);

      final scaffoldState = tester.state<ScaffoldState>(find.byType(Scaffold));
      scaffoldState.openDrawer();
      await tester.pumpAndSettle();

      expect(find.byType(NavigationDrawer), findsOneWidget);
      // Drawer adds Sell-In only (does not re-attach Sell-Out).
      expect(countInteractiveTargets(tester, TestIds.navSellIn), 1);
    } finally {
      handle.dispose();
    }
  });

  testWidgets('Compact More sheet has exactly one interactive nav-sell-in',
      (tester) async {
    final handle = tester.ensureSemantics();
    ignoreRenderFlexOverflows();
    try {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(_shellApp(apiClient));
      await tester.pumpAndSettle();

      expect(countInteractiveTargets(tester, TestIds.navSellOut), 1);

      await tester.tap(find.text('More'));
      await tester.pumpAndSettle();

      expect(find.text('Sell-In & Targets'), findsOneWidget);
      expect(countInteractiveTargets(tester, TestIds.navSellIn), 1);
    } finally {
      handle.dispose();
    }
  });
}
