import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:tashil_web/core/network/api_client.dart';
import 'package:tashil_web/core/theme/app_theme.dart';
import 'package:tashil_web/features/navigation/presentation/app_shell.dart';
import 'package:tashil_web/features/sell_out_analytics/presentation/screens/sell_in_explorer_screen.dart';
import 'package:tashil_web/features/sell_out_analytics/presentation/screens/sell_out_explorer_screen.dart';
import 'package:tashil_web/features/sell_out_analytics/presentation/widgets/sell_in_derived_targets_view.dart';
import 'package:tashil_web/features/sell_out_analytics/presentation/widgets/target_management_panel.dart';

void _ignoreOverflows() {
  final previous = FlutterError.onError;
  FlutterError.onError = (details) {
    if (details.exceptionAsString().contains('A RenderFlex overflowed')) {
      return;
    }
    previous?.call(details);
  };
  addTearDown(() => FlutterError.onError = previous);
}

Future<void> _openTab(WidgetTester tester, Pattern label) async {
  final f = find.textContaining(label);
  expect(f, findsWidgets, reason: 'tab "$label" not found');
  await tester.ensureVisible(f.first);
  await tester.pumpAndSettle();
  await tester.tap(f.first);
  await tester.pumpAndSettle();
}

void main() {
  GoogleFonts.config.allowRuntimeFetching = false;

  testWidgets('Sell-Out explorer opens on the targets tab when asked',
      (tester) async {
    _ignoreOverflows();
    tester.view.physicalSize = const Size(1440, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(
        body: SellOutExplorerScreen(apiClient: ApiClient(), initialTab: 2),
      ),
    ));
    await tester.pumpAndSettle();

    final panel =
        tester.widget<TargetManagementPanel>(find.byType(TargetManagementPanel));
    expect(panel.targetType, 'sell_out');
  });

  testWidgets(
      'Sell-In targets «تعديل مستهدف Sell-Out» jumps to the Sell-Out targets tab',
      (tester) async {
    _ignoreOverflows();
    tester.view.physicalSize = const Size(1440, 1400);
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
        apiClient: ApiClient(),
        activeTenant: 'adeco',
        onTenantChanged: (_) {},
        initialPageIndex: 2,
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.byType(SellInExplorerScreen), findsOneWidget);
    await _openTab(tester, RegExp('^المستهدفات\$'));
    expect(find.byType(SellInDerivedTargetsView), findsOneWidget);

    final button = find.byKey(const ValueKey('sellin_edit_sellout_targets'));
    await tester.ensureVisible(button);
    await tester.pumpAndSettle();
    await tester.tap(button);
    await tester.pumpAndSettle();

    expect(find.byType(SellInExplorerScreen), findsNothing);
    expect(find.byType(SellOutExplorerScreen), findsOneWidget);
    final panel =
        tester.widget<TargetManagementPanel>(find.byType(TargetManagementPanel));
    expect(panel.targetType, 'sell_out');
    expect(find.byType(SellInDerivedTargetsView), findsNothing);
  });
}
