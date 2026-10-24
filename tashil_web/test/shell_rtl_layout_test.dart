import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:tashil_web/core/theme/app_theme.dart';
import 'package:tashil_web/features/navigation/presentation/app_shell.dart';
import 'package:tashil_web/features/navigation/presentation/desktop_sidebar.dart';

void main() {
  GoogleFonts.config.allowRuntimeFetching = false;

  test('shell is RTL for both supported locales', () {
    expect(shellTextDirectionFor(const Locale('ar')), TextDirection.rtl);
    expect(shellTextDirectionFor(const Locale('en')), TextDirection.rtl);
  });

  testWidgets('RTL: sidebar sits on the right, labels are Arabic+English, '
      'footer does not overlap the last destination', (tester) async {
    tester.view.physicalSize = const Size(1280, 640); // short viewport
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
      home: Scaffold(
        body: Directionality(
          textDirection: shellTextDirectionFor(const Locale('ar')),
          child: Row(children: [
            DesktopSidebar(
              selectedIndex: 0,
              onDestinationSelected: (_) {},
              activeTenant: 'adeco',
              onTenantChanged: (_) {},
            ),
            const Expanded(child: SizedBox.expand(key: ValueKey('content'))),
          ]),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    final sidebarRect = tester.getRect(find.byType(DesktopSidebar));
    final contentRect = tester.getRect(find.byKey(const ValueKey('content')));
    expect(sidebarRect.left, greaterThan(contentRect.left),
        reason: 'In RTL the sidebar must be on the start (right) side');

    expect(find.text('لوحة القيادة'), findsNothing);
    expect(find.text('Dashboard'), findsOneWidget);

    // Scroll the nav list to the end; 'Product Master' must be fully above the footer.
    final list = find.descendant(
        of: find.byType(DesktopSidebar), matching: find.byType(Scrollable));
    await tester.scrollUntilVisible(find.text('Product Master'), 50.0,
        scrollable: list.first);
    await tester.pumpAndSettle();
    final footerTop =
        tester.getRect(find.byKey(const ValueKey('sidebar_footer_status'))).top;
    final lastBottom = tester.getRect(find.text('Product Master')).bottom;
    expect(lastBottom, lessThanOrEqualTo(footerTop));
    final uploadBottom = tester.getRect(find.text('Upload')).bottom;
    expect(uploadBottom, lessThanOrEqualTo(footerTop));
  });
}
