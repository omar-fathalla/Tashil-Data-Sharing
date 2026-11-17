import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tashil_web/core/config/app_version.dart';
import 'package:tashil_web/core/network/api_client.dart';
import 'package:tashil_web/core/theme/app_theme.dart';
import 'package:tashil_web/core/widgets/data_sharing_logo.dart';
import 'package:tashil_web/features/auth/presentation/widgets/user_profile_dialog.dart';
import 'package:tashil_web/features/navigation/presentation/app_shell.dart';
import 'package:tashil_web/features/navigation/presentation/desktop_sidebar.dart';
import 'package:tashil_web/features/navigation/presentation/narrow_sidebar.dart';
import 'package:tashil_web/features/navigation/presentation/tenant_logo_slot.dart';

import 'support/product_master_m3_support.dart' show ignoreGoogleFontLoadErrors;
import 'support/real_fonts.dart';

/// 32×32 blue disc with a white ring. Stands in for an uploaded tenant logo.
final _logoPng = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAEAAAABACAYAAACqaXHeAAAB50lEQVR4nO1b2XXDMAyj/bpCuk6zTDpUs0y6TjNE+lPluYpuAaIsC5+JTRIgJMuHFmmE0+X2yDn+fj0vrFq2oCXJJRwDSxB4UDRxG2ghYMHYxG2ghKgO0pq4jVohik/WJm6jVIi15KTeyIuU15QtQI/kDUpqS7ZNz8RdSB0SSQ7YG3mR9JqjAuyRvEFK7UWT4EgICrDn7hvEOHgFGIG8QYiLU4CRyBv4OB1+Dni5VrK7//P1Efz//fObmf5lffBGzfaHGGnfsWwxRKwhwOh+DnnkuT7YHGkOQBVv4rDc8HQAsvuMziFjbrnCrwIM8szYqwiu+0zy6ByG8+HXATABWnSfkQsiQEvy6JzriOv+VJwut8ecA2oDaNgfmXs6QLsAbUwBtAvQxhRAuwBtTAFqA7R4bMXMPR3Q6musHnG/nheIAzSGASonbAi0FAGZa84BIrhPzlq4AJXDcIY7gCkCI/ZTAOTVgFEoMuaWK+3NkCm49qEFe1j9GwKMNUENAQZ5lbfDWyLar8dtODs+6pNil8PnOsD144j3Bz5OXgeMJEKIS3AIjCBCjMOcA2IH7NkFKbUnOWCPIqTWnE2s9zVCbrOy54Ce3VBSW9Ek2KMIpTXNbXOoQg67cdLGYbfO2jjs5mkfet0+/wsiqtN6O35EGwAAAABJRU5ErkJggg==',
);

void main() {
  setUp(AppVersion.debugReset);
  setUpAll(() async {
    ignoreGoogleFontLoadErrors();
    await loadRealCairoFont();
    final cairo = File('test/fonts/Cairo-Variable.ttf').readAsBytesSync();
    final cairoData = ByteData.view(Uint8List.fromList(cairo).buffer);
    const aliases = [
      'Cairo-Regular',
      'Cairo-Medium',
      'Cairo-SemiBold',
      'Cairo-Bold',
      'Cairo-Light',
    ];
    for (final family in aliases) {
      await (FontLoader(family)..addFont(Future.value(cairoData))).load();
    }
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

  test('tenant profile logo_url is optional and round-trips', () {
    final missing = TenantProfileModel.fromJson(const {});
    expect(missing.logoUrl, isEmpty);

    final parsed = TenantProfileModel.fromJson(const {
      'slug': 'adeco',
      'logo_url': 'https://cdn.example/adeco.png',
    });
    expect(parsed.logoUrl, 'https://cdn.example/adeco.png');
    expect(parsed.toJson()['logo_url'], 'https://cdn.example/adeco.png');
  });

  test('logo slot uses a URL when present and a letter when it is not', () {
    expect(
      TenantLogoSlot.resolveLogoUrl(tenantSlug: 'adeco', logoUrl: null),
      isNull,
      reason: 'Adeco has no catalog logo, so the letter avatar is used',
    );
    expect(
      TenantLogoSlot.resolveLogoUrl(tenantSlug: 'adeco', logoUrl: '  '),
      isNull,
    );
    expect(
      TenantLogoSlot.resolveLogoUrl(
        tenantSlug: 'adeco',
        logoUrl: 'https://cdn.example/adeco.png',
      ),
      'https://cdn.example/adeco.png',
    );
    expect(TenantLogoSlot.letterForSlug('adeco'), 'A');
    expect(TenantLogoSlot.letterForSlug('unilever'), 'U');

    final image = TenantLogoSlot.resolveImage(
      tenantSlug: 'adeco',
      logoUrl: 'https://cdn.example/adeco.png',
    );
    expect(image, isA<NetworkImage>());
    expect((image! as NetworkImage).url, 'https://cdn.example/adeco.png');
    expect(
      TenantLogoSlot.resolveImage(tenantSlug: 'adeco', logoUrl: ''),
      isNull,
    );
  });

  testWidgets(
      'desktop sidebar shows the tenant brand on the left and Tashil in the footer',
      (tester) async {
    AppVersion.applyDeployedAppVersion('212');
    var profileTaps = 0;
    await _pumpSidebar(
      tester,
      onOpenProfile: () => profileTaps++,
    );

    expect(find.text('Tashil Portal'), findsNothing);
    expect(find.text('Data Sharing Platform'), findsNothing);
    expect(find.byType(DataSharingLogo), findsNothing);
    expect(find.text('Adeco Admin'), findsNothing);
    expect(find.textContaining('Vendor'), findsNothing);
    expect(
      find.descendant(
        of: find.byType(DesktopSidebar),
        matching: find.byIcon(Icons.manage_accounts_rounded),
      ),
      findsNothing,
    );
    expect(find.byType(TenantLogoSlot), findsOneWidget);
    expect(find.text('Adeco'), findsOneWidget);
    expect(find.text('A'), findsOneWidget);
    expect(find.text('Smart Ingestion Active'), findsOneWidget);
    expect(find.byIcon(Icons.bolt_rounded), findsOneWidget);
    expect(
      find.text('Tashil • Data Sharing Platform • v212'),
      findsOneWidget,
    );

    final brand = tester.widget<Text>(
      find.byKey(const ValueKey('sidebar-app-version')),
    );
    expect(brand.style?.fontWeight, FontWeight.w300);
    expect(brand.textAlign, TextAlign.left);
    expect(brand.textDirection, TextDirection.ltr);

    final sidebar = tester.getRect(find.byType(DesktopSidebar));
    final logo =
        tester.getRect(find.byKey(const ValueKey('sidebar_tenant_logo')));
    final name =
        tester.getRect(find.byKey(const ValueKey('sidebar_tenant_name')));
    expect(logo.left, lessThan(name.left),
        reason: 'English tenant name stays to the right of its logo');
    expect(logo.left, closeTo(sidebar.left + 16.0, 1.0),
        reason: 'header hugs the left edge even though the shell is RTL');
    expect(name.left, lessThan(sidebar.center.dx));

    final status =
        tester.getRect(find.byKey(const ValueKey('sidebar_footer_status')));
    final credit =
        tester.getRect(find.byKey(const ValueKey('sidebar-app-version')));
    expect(credit.top, greaterThanOrEqualTo(status.bottom - 0.5));
    expect(credit.left, greaterThanOrEqualTo(sidebar.left));
    expect(credit.right, lessThanOrEqualTo(sidebar.right + 0.5));
    expect(sidebar.bottom - credit.bottom, lessThanOrEqualTo(16.0));

    await tester.tap(find.byKey(const ValueKey('sidebar_tenant_header')));
    await tester.pump();
    expect(profileTaps, 1);

    await _saveShot(tester, 'sidebar-tenant-header.png');

    AppVersion.applyDeployedAppVersion('213');
    await tester.pump();
    expect(find.text('Tashil • Data Sharing Platform • v213'), findsOneWidget);
    expect(find.textContaining('v212'), findsNothing);
  });

  testWidgets(
      'uploaded logo replaces the letter and still leaves a single mark',
      (tester) async {
    final logo = MemoryImage(_logoPng);
    await _pumpSidebar(
      tester,
      tenantLogoImage: logo,
    );
    await tester.runAsync(() async {
      await precacheImage(logo, tester.element(find.byType(DesktopSidebar)));
    });
    await tester.pump();
    expect(find.byType(Image), findsOneWidget);
    expect(find.text('A'), findsNothing);
    expect(find.text('Adeco'), findsOneWidget);
    expect(find.byType(TenantLogoSlot), findsOneWidget);
    expect(find.byType(DataSharingLogo), findsNothing);
    await _saveShot(tester, 'sidebar-tenant-logo-image.png');
  });

  testWidgets('tapping the tenant header opens profile, including sign out',
      (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(_localizedApp(
      home: AppShell(
        apiClient: ApiClient(),
        activeTenant: 'adeco',
        onTenantChanged: (_) {},
        onLogout: () {},
      ),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Tashil Portal'), findsNothing);
    expect(
      find.descendant(
        of: find.byType(DesktopSidebar),
        matching: find.byIcon(Icons.manage_accounts_rounded),
      ),
      findsNothing,
    );

    await tester.tap(find.byKey(const ValueKey('sidebar_tenant_header')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byType(UserProfileDialog), findsOneWidget);
    expect(find.text('Sign Out'), findsOneWidget);
  });

  testWidgets('narrow rail keeps the tenant mark and account actions',
      (tester) async {
    tester.view.physicalSize = const Size(800, 1100);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    var loggedOut = false;
    await tester.pumpWidget(_localizedApp(
      home: AppShell(
        apiClient: ApiClient(),
        activeTenant: 'adeco',
        onTenantChanged: (_) {},
        onLogout: () => loggedOut = true,
      ),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byType(NarrowSidebar), findsOneWidget);
    expect(find.byType(NavigationRail), findsNothing);
    expect(find.byType(DesktopSidebar), findsNothing);
    expect(find.byType(DataSharingLogo), findsNothing);
    expect(find.byType(TenantLogoSlot), findsOneWidget);
    final rail = find.byType(NarrowSidebar);
    expect(find.descendant(of: rail, matching: find.text('Adeco')),
        findsOneWidget);
    expect(
      find.descendant(
          of: rail, matching: find.byIcon(Icons.manage_accounts_rounded)),
      findsOneWidget,
    );
    expect(
      find.descendant(of: rail, matching: find.byIcon(Icons.logout_rounded)),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('rail_tenant_header')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(UserProfileDialog), findsOneWidget);
    expect(find.text('Sign Out'), findsOneWidget);

    Navigator.of(tester.element(find.byType(UserProfileDialog))).pop();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(UserProfileDialog), findsNothing);

    await tester.tap(find.byTooltip('Log Out'));
    await tester.pump();
    expect(loggedOut, isTrue);

    await _saveLargestShot(tester, 'sidebar-rail-tenant.png');
  });
}

Widget _localizedApp({required Widget home}) {
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

Future<void> _pumpSidebar(
  WidgetTester tester, {
  VoidCallback? onOpenProfile,
  ImageProvider<Object>? tenantLogoImage,
  String? tenantLogoUrl,
}) async {
  tester.view.physicalSize = const Size(1280, 800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(_localizedApp(
    home: Scaffold(
      body: Directionality(
        textDirection: TextDirection.rtl,
        child: Row(
          textDirection: TextDirection.ltr,
          children: [
            const Expanded(
              child: ColoredBox(
                color: Color(0xFFF3F6F2),
                child: SizedBox.expand(),
              ),
            ),
            RepaintBoundary(
              key: const ValueKey('sidebar_shot'),
              child: DesktopSidebar(
                selectedIndex: 0,
                onDestinationSelected: (_) {},
                activeTenant: 'adeco',
                onTenantChanged: (_) {},
                onOpenProfile: onOpenProfile,
                tenantLogoUrl: tenantLogoUrl,
                tenantLogoImage: tenantLogoImage,
              ),
            ),
          ],
        ),
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

Future<void> _saveShot(WidgetTester tester, String name) async {
  final dir = Directory('/opt/cursor/artifacts');
  if (!dir.existsSync()) return;
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(const ValueKey('sidebar_shot')),
  );
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 2);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    File('${dir.path}/$name').writeAsBytesSync(bytes!.buffer.asUint8List());
  });
}

Future<void> _saveLargestShot(WidgetTester tester, String name) async {
  final dir = Directory('/opt/cursor/artifacts');
  if (!dir.existsSync()) return;
  RenderRepaintBoundary? best;
  for (final ro in tester.allRenderObjects.whereType<RenderRepaintBoundary>()) {
    if (!ro.hasSize || ro.size.isEmpty) continue;
    final area = ro.size.width * ro.size.height;
    final bestArea = best == null ? 0.0 : best.size.width * best.size.height;
    if (area > bestArea) best = ro;
  }
  final boundary = best;
  if (boundary == null) return;
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    File('${dir.path}/$name').writeAsBytesSync(bytes!.buffer.asUint8List());
  });
}
