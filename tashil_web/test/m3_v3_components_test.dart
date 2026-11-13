import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:tashil_web/core/theme/app_theme.dart';
import 'package:tashil_web/core/widgets/app_icons.dart';
import 'package:tashil_web/core/widgets/m3_status_tag.dart';
import 'package:tashil_web/features/navigation/presentation/desktop_sidebar.dart';

Widget _app(Widget child) => MaterialApp(
      theme: AppTheme.light(),
      home: Directionality(
          textDirection: TextDirection.rtl, child: Scaffold(body: child)),
    );

void main() {
  GoogleFonts.config.allowRuntimeFetching = false;

  testWidgets('M3StatusTag is 32dp tall (mockup chip), with or without icon',
      (tester) async {
    await tester.pumpWidget(_app(const Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        M3StatusTag(key: ValueKey('plain'), label: '6 أصناف'),
        M3StatusTag(
            key: ValueKey('icon'),
            label: 'سليم',
            tone: M3StatusTone.success,
            icon: AppIcons.success),
      ]),
    )));
    for (final k in ['plain', 'icon']) {
      expect(tester.getSize(find.byKey(ValueKey(k))).height,
          greaterThanOrEqualTo(32.0));
    }
    expect(tester.widget<Icon>(find.byIcon(AppIcons.success)).size, 18.0);
  });

  testWidgets('Sidebar: Material pill indicator + M3 Badge, no BoxDecoration',
      (tester) async {
    tester.view.physicalSize = const Size(1440, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(_app(Row(children: [
      DesktopSidebar(
        selectedIndex: 0,
        onDestinationSelected: (_) {},
        activeTenant: 'adeco',
        onTenantChanged: (_) {},
      ),
      const Expanded(child: SizedBox()),
    ])));
    await tester.pumpAndSettle();
    expect(find.byType(Badge), findsWidgets);
    final cs =
        Theme.of(tester.element(find.byType(DesktopSidebar))).colorScheme;
    final indicators = tester
        .widgetList<Material>(find.descendant(
            of: find.byType(DesktopSidebar), matching: find.byType(Material)))
        .where((m) =>
            m.shape is StadiumBorder && m.color == cs.secondaryContainer);
    expect(indicators.length, 1, reason: 'one selected nav pill');
    final navDecorations = tester
        .widgetList<Container>(find.descendant(
            of: find.byType(ListView), matching: find.byType(Container)))
        .where((c) => c.decoration is BoxDecoration);
    expect(navDecorations, isEmpty);
  });
}
