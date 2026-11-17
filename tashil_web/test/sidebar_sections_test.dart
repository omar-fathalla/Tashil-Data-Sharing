import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tashil_web/core/network/api_client.dart';
import 'package:tashil_web/core/theme/app_theme.dart';
import 'package:tashil_web/features/data_ingestion/presentation/screens/upload_portal_screen.dart';
import 'package:tashil_web/features/navigation/app_page_route.dart';
import 'package:tashil_web/features/navigation/nav_catalog.dart';
import 'package:tashil_web/features/navigation/presentation/app_shell.dart';
import 'package:tashil_web/features/navigation/presentation/desktop_sidebar.dart';
import 'package:tashil_web/features/navigation/presentation/narrow_sidebar.dart';

import 'support/product_master_m3_support.dart' show ignoreGoogleFontLoadErrors;
import 'support/real_fonts.dart';

void main() {
  setUpAll(() async {
    ignoreGoogleFontLoadErrors();
    await loadRealCairoFont();
    final iconPath =
        '${Platform.environment['FLUTTER_ROOT'] ?? '/opt/flutter'}/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf';
    final iconFile = File(iconPath);
    if (iconFile.existsSync()) {
      final iconBytes = iconFile.readAsBytesSync();
      final iconData = ByteData.view(Uint8List.fromList(iconBytes).buffer);
      await (FontLoader('MaterialIcons')..addFont(Future.value(iconData)))
          .load();
    }
  });

  test('catalog groups pages and keeps the upload route out of the menu', () {
    expect(AppPageRoute.pageSlugs[10], 'upload');
    expect(AppPageRoute.indexForSlug('upload'), 10);
    expect(AppNavCatalog.byRoute(10).showInMenu, isFalse);
    expect(AppNavCatalog.menuIndexForRoute(10), isNull);
    expect(
      AppNavCatalog.menu.map((item) => item.routeIndex),
      isNot(contains(10)),
    );

    final sections = AppNavCatalog.groupedMenu();
    expect(
      sections.map((group) => group.section.titleAr),
      ['', 'الإدخالات', 'التسويق', 'التحليلات', 'النظام'],
    );
    expect(
      sections[1].items.map((item) => item.sidebarLabel),
      ['Sell-Out', 'Sell-In', 'Returns', 'Product Master'],
    );
    expect(
      sections[2].items.map((item) => item.sidebarLabel),
      ['Pricing & Promos', 'Trade Marketing & ROI'],
    );
    expect(
      sections[3].items.map((item) => item.sidebarLabel),
      ['OOS Monitor', 'Store Matrix', 'Compare', 'CPFR Replenishment'],
    );
    expect(sections[4].items.single.sidebarLabel, 'Errors');
    expect(sections.first.items.single.sidebarLabel, 'Dashboard');

    final routes = AppNavCatalog.items.map((item) => item.routeIndex).toSet();
    expect(routes, {for (var i = 0; i < AppPageRoute.pageSlugs.length; i++) i});
  });

  testWidgets('wide sidebar shows thin Arabic section headers and hides Upload',
      (tester) async {
    await _pumpWide(tester);

    expect(find.text('Upload'), findsNothing);
    expect(find.text('الإدخالات'), findsOneWidget);
    expect(find.text('التسويق'), findsOneWidget);
    expect(find.text('التحليلات'), findsOneWidget);
    expect(find.text('النظام'), findsOneWidget);
    expect(
        find.byKey(const ValueKey('nav_section_divider_inputs')), findsNothing);

    final header = tester.widget<Text>(find.text('الإدخالات'));
    expect(header.style?.fontWeight, FontWeight.w400);
    expect(header.style?.fontSize, 11.0);

    double top(String label) => tester.getTopLeft(find.text(label)).dy;
    expect(top('Dashboard'), lessThan(top('الإدخالات')));
    expect(top('الإدخالات'), lessThan(top('Sell-Out')));
    expect(top('Product Master'), lessThan(top('التسويق')));
    expect(top('التسويق'), lessThan(top('Pricing & Promos')));
    expect(top('Trade Marketing & ROI'), lessThan(top('التحليلات')));
    expect(top('التحليلات'), lessThan(top('OOS Monitor')));
    expect(top('CPFR Replenishment'), lessThan(top('النظام')));
    expect(top('النظام'), lessThan(top('Errors')));

    final sidebar = tester.getRect(find.byType(DesktopSidebar));
    final inputs = tester.getRect(find.text('الإدخالات'));
    expect(
      inputs.right,
      closeTo(sidebar.right - 28.0, 2.0),
      reason: 'Arabic section header aligns to the RTL start edge',
    );

    expect(find.byKey(const ValueKey('sidebar-app-version')), findsOneWidget);
    expect(
      find.textContaining('Tashil • Data Sharing Platform •'),
      findsOneWidget,
    );
    expect(find.text('Adeco'), findsOneWidget);

    await _saveBoundary(tester, 'sidebar_shot', 'sidebar-sections-wide.png');
  });

  testWidgets('collapsed sidebar turns section headers into thin dividers',
      (tester) async {
    tester.view.physicalSize = const Size(400, 1040);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(_app(
      home: const Scaffold(
        body: Directionality(
          textDirection: TextDirection.rtl,
          child: Row(
            textDirection: TextDirection.ltr,
            children: [
              Expanded(child: ColoredBox(color: Color(0xFFF3F6F2))),
              RepaintBoundary(
                key: ValueKey('sidebar_shot'),
                child: NarrowSidebar(
                  selectedRouteIndex: 0,
                  onDestinationSelected: _noop,
                  activeTenant: 'adeco',
                ),
              ),
            ],
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    final rail = find.byType(NarrowSidebar);
    expect(rail, findsOneWidget);
    expect(
        find.descendant(of: rail, matching: find.text('Upload')), findsNothing);
    expect(find.descendant(of: rail, matching: find.text('الإدخالات')),
        findsNothing);
    expect(find.descendant(of: rail, matching: find.text('التسويق')),
        findsNothing);
    expect(find.text('Master'), findsOneWidget);
    expect(find.text('Promo ROI'), findsOneWidget);

    for (final id in ['inputs', 'marketing', 'analytics', 'system']) {
      final key = find.byKey(ValueKey('nav_section_divider_$id'));
      expect(key, findsOneWidget, reason: id);
      final divider = tester.widget<Divider>(
        find.descendant(of: key, matching: find.byType(Divider)),
      );
      expect(divider.thickness, 1.0);
      expect(divider.height, 1.0);
    }

    final inputsDivider = tester
        .getRect(find.byKey(const ValueKey('nav_section_divider_inputs')));
    final sellOut = tester.getRect(find.text('Sell-Out'));
    final pricing = tester.getRect(find.text('Pricing'));
    expect(inputsDivider.bottom, lessThanOrEqualTo(sellOut.top));
    expect(
      tester
          .getRect(find.byKey(const ValueKey('nav_section_divider_marketing')))
          .top,
      greaterThan(tester.getRect(find.text('Master')).bottom - 1),
    );
    expect(pricing.top, greaterThan(sellOut.bottom));

    await _saveBoundary(
        tester, 'sidebar_shot', 'sidebar-sections-collapsed.png');
  });

  testWidgets('upload deep link still opens the page with no menu entry',
      (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(_app(
      home: AppShell(
        apiClient: ApiClient(),
        activeTenant: 'adeco',
        onTenantChanged: (_) {},
        initialPageIndex: 10,
      ),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byType(UploadPortalScreen), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(DesktopSidebar),
        matching: find.text('Upload'),
      ),
      findsNothing,
    );
    expect(find.text('الإدخالات'), findsOneWidget);
  });

  testWidgets('drawer and More sheet use the same sections and omit Upload',
      (tester) async {
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(_app(
      home: AppShell(
        apiClient: ApiClient(),
        activeTenant: 'adeco',
        onTenantChanged: (_) {},
      ),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    final scaffoldState = tester.state<ScaffoldState>(find.byType(Scaffold));
    scaffoldState.openDrawer();
    await tester.pumpAndSettle();

    final drawer = find.byType(NavigationDrawer);
    expect(drawer, findsOneWidget);
    expect(
      find.descendant(of: drawer, matching: find.text('الإدخالات')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: drawer, matching: find.text('التسويق')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: drawer, matching: find.text('Smart Upload')),
      findsNothing,
    );

    scaffoldState.closeDrawer();
    await tester.pumpAndSettle();

    await tester.tap(find.text('More'));
    await tester.pumpAndSettle();
    expect(find.text('الإدخالات'), findsOneWidget);
    expect(find.text('النظام'), findsOneWidget);
    expect(find.text('Smart Upload'), findsNothing);
    expect(find.text('Sell-In & Targets'), findsOneWidget);
  });
}

void _noop(int _) {}

Widget _app({required Widget home}) {
  return MaterialApp(
    theme: AppTheme.light(),
    locale: const Locale('ar'),
    supportedLocales: const [Locale('ar'), Locale('en')],
    localizationsDelegates: const [
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    home: home,
  );
}

Future<void> _pumpWide(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1440, 1040);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(_app(
    home: Scaffold(
      body: Directionality(
        textDirection: TextDirection.rtl,
        child: Row(
          textDirection: TextDirection.ltr,
          children: [
            const Expanded(child: ColoredBox(color: Color(0xFFF3F6F2))),
            RepaintBoundary(
              key: const ValueKey('sidebar_shot'),
              child: DesktopSidebar(
                selectedIndex: 0,
                onDestinationSelected: _noop,
                activeTenant: 'adeco',
                onTenantChanged: (_) {},
              ),
            ),
          ],
        ),
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

Future<void> _saveBoundary(
  WidgetTester tester,
  String key,
  String name,
) async {
  final dir = Directory('/opt/cursor/artifacts');
  if (!dir.existsSync()) dir.createSync(recursive: true);
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(ValueKey(key)),
  );
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 2);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    File('${dir.path}/$name').writeAsBytesSync(bytes!.buffer.asUint8List());
  });
}
