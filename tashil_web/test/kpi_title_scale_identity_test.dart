// KPI titles must use the Sell-Out title style at 1.0 scale (no FittedBox
// shrinking) and must not ellipsize real strings at 1280+DesktopSidebar.
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tashil_web/core/data/app_cache.dart';
import 'package:tashil_web/core/network/api_client.dart';
import 'package:tashil_web/core/theme/app_theme.dart';
import 'package:tashil_web/core/widgets/m3_section_title.dart';
import 'package:tashil_web/features/oos_monitor/presentation/screens/oos_dashboard_screen.dart';
import 'package:tashil_web/features/sell_out_analytics/presentation/screens/sell_out_explorer_screen.dart';

import 'oos_m3_support.dart';
import 'support/live_viewport.dart';
import 'support/product_master_m3_support.dart' hide ignoreGoogleFontLoadErrors;

Future<void> _pumpSellOutShell(WidgetTester tester) async {
  tester.view.physicalSize = const Size(kLiveViewportWidth, 2400);
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
    home: Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        body: Row(
          textDirection: TextDirection.rtl,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(
              width: kLiveSidebarWidth,
              child: ColoredBox(color: Color(0xFF1A1C19)),
            ),
            Expanded(
              child: SellOutExplorerScreen(apiClient: ApiClient()),
            ),
          ],
        ),
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

TextStyle _titleStyle(WidgetTester tester, Finder title) {
  final rich = find.descendant(of: title, matching: find.byType(RichText));
  expect(rich, findsWidgets, reason: 'no RichText under $title');
  return tester.widget<RichText>(rich.first).text.style!;
}

double _paintScale(WidgetTester tester, Finder title, Finder card) {
  final para = tester.renderObject<RenderParagraph>(
      find.descendant(of: title, matching: find.byType(RichText)).first);
  final cardBox = tester.renderObject(card);
  return para.getTransformTo(cardBox).getMaxScaleOnAxis();
}

bool _titleEllipsized(WidgetTester tester, Finder title) {
  final para = tester.renderObject<RenderParagraph>(
      find.descendant(of: title, matching: find.byType(RichText)).first);
  return para.didExceedMaxLines;
}

void _assertCardTitleMatchesSellOut(
  WidgetTester tester, {
  required Finder card,
  required TextStyle sellOutTitle,
  required String page,
}) {
  final title = find.descendant(of: card, matching: find.byType(M3SectionTitle));
  expect(title, findsOneWidget, reason: '$page card missing title');
  // No FittedBox may shrink the title.
  expect(
    find.descendant(of: card, matching: find.byType(FittedBox)),
    findsNothing,
    reason: '$page title must not be scaled by FittedBox',
  );
  final style = _titleStyle(tester, title);
  expect(style.fontSize, sellOutTitle.fontSize, reason: '$page title fontSize');
  expect(style.fontWeight, sellOutTitle.fontWeight, reason: '$page title fontWeight');
  expect(style.fontFamily, sellOutTitle.fontFamily, reason: '$page title fontFamily');
  expect(
    _paintScale(tester, title, card),
    closeTo(1.0, 0.01),
    reason: '$page title paint scale must be 1.0 (Sell-Out identity)',
  );
  expect(_titleEllipsized(tester, title), isFalse,
      reason: '$page title ellipsized: ${tester.widget<M3SectionTitle>(title).text}');
}

void main() {
  ignoreGoogleFontLoadErrors();
  setUpAll(loadOosFonts);
  setUp(AppCache.clear);

  testWidgets(
      'OOS KPI titles match Sell-Out text scale at 1280+sidebar, no ellipsis (Product Master has none)',
      (tester) async {
    await _pumpSellOutShell(tester);
    final soCard = find.byKey(const ValueKey('kpi_card_Net Sales (EGP)'));
    expect(soCard, findsOneWidget);
    final soTitle = find.descendant(
        of: soCard, matching: find.byType(M3SectionTitle));
    final sellOutStyle = _titleStyle(tester, soTitle);
    expect(sellOutStyle.fontSize, 16.0);
    expect(_paintScale(tester, soTitle, soCard), closeTo(1.0, 0.01));
    expect(tester.widget<M3SectionTitle>(soTitle).text, 'صافي المبيعات');

    // OOS at the live 1280+sidebar shell.
    await pumpOos(
      tester,
      Row(
        textDirection: TextDirection.rtl,
        children: [
          const SizedBox(
            width: kLiveSidebarWidth,
            child: ColoredBox(color: Color(0xFF1A1C19)),
          ),
          Expanded(
            child: OOSDashboardScreen(apiClient: OosShotApiClient()),
          ),
        ],
      ),
      width: kLiveViewportWidth,
    );

    expect(find.text('نسبة التوافر OSA%'), findsOneWidget);
    expect(find.text('الأصناف المنعدمة'), findsOneWidget);
    expect(find.text('الفروع المتأثرة'), findsOneWidget);
    expect(find.text('الخسارة اليومية'), findsOneWidget);
    expect(find.text('الخسارة الشهرية'), findsOneWidget);
    // Shortened titles must not appear as the visible title in the long form.
    expect(find.text('مؤشر التوافر على الرفوف OSA%'), findsNothing);

    const oosKeys = [
      'osa_summary_card',
      'kpi_card_Total OOS SKUs',
      'kpi_card_Impacted Branches',
      'kpi_card_Daily Lost Revenue',
      'kpi_card_Monthly Projected Loss',
    ];
    for (final k in oosKeys) {
      final card = find.byKey(ValueKey(k));
      expect(card, findsOneWidget, reason: k);
      expect(tester.getSize(card).height, closeTo(138.0, 1.0), reason: k);
      _assertCardTitleMatchesSellOut(
        tester,
        card: card,
        sellOutTitle: sellOutStyle,
        page: 'OOS $k',
      );
    }

    // Product Master has no KPI cards (owner decision): nothing to compare there.
    await pumpProductMaster(
      tester,
      width: kLiveViewportWidth,
      withSidebar: true,
    );
    expect(find.byWidgetPredicate((w) =>
        w.key is ValueKey<String> &&
        (w.key as ValueKey<String>).value.startsWith('pm_kpi_card_')),
        findsNothing);
  });
}
