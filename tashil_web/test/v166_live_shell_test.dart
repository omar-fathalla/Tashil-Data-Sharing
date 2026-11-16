import 'dart:io';
import 'package:flutter/services.dart';
// Live 1280+DesktopSidebar harness (real Cairo): v166 follow-up to the
// v165 review. Targets / Sell-In KPI cards must match Sell-Out (138px,
// titleMedium, no title ellipsis) and the Sell-In waterfall plus Product
// Master codes must be fully visible — no clip, no overflow.
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tashil_web/core/data/app_cache.dart';
import 'package:tashil_web/core/network/api_client.dart';
import 'package:tashil_web/core/theme/app_theme.dart';
import 'package:tashil_web/core/widgets/m3_section_title.dart';
import 'package:tashil_web/features/sell_out_analytics/presentation/screens/sell_in_explorer_screen.dart';
import 'package:tashil_web/features/sell_out_analytics/presentation/screens/sell_out_explorer_screen.dart';

import 'oos_m3_support.dart';
import 'support/live_viewport.dart';
import 'support/product_master_m3_support.dart' hide ignoreGoogleFontLoadErrors;

Future<void> _pumpShell(WidgetTester tester, Widget screen) async {
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
            Expanded(child: screen),
          ],
        ),
      ),
    ),
  ));
  await tester.pump();
  // Avoid pumpAndSettle: Sell-In may keep a loading indicator ticking
  // while HTTP is stubbed. A few frames are enough for first layout.
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

bool _ellipsized(WidgetTester tester, Finder textHost) {
  final rich = find.descendant(of: textHost, matching: find.byType(RichText));
  expect(rich, findsWidgets, reason: 'no RichText under $textHost');
  return tester
      .renderObject<RenderParagraph>(rich.first)
      .didExceedMaxLines;
}

TextStyle _titleStyle(WidgetTester tester, Finder title) {
  final rich = find.descendant(of: title, matching: find.byType(RichText));
  return tester.widget<RichText>(rich.first).text.style!;
}

void _assertSellOutCard(
  WidgetTester tester, {
  required Finder card,
  required TextStyle sellOutTitle,
  required String name,
}) {
  expect(card, findsOneWidget, reason: name);
  expect(tester.getSize(card).height, closeTo(138.0, 1.0), reason: name);
  final title = find.descendant(of: card, matching: find.byType(M3SectionTitle));
  expect(title, findsOneWidget, reason: '$name missing title');
  expect(
    find.descendant(of: card, matching: find.byType(FittedBox)),
    findsNothing,
    reason: '$name title must not be scaled',
  );
  final style = _titleStyle(tester, title);
  expect(style.fontSize, sellOutTitle.fontSize, reason: '$name fontSize');
  expect(style.fontWeight, sellOutTitle.fontWeight, reason: '$name fontWeight');
  expect(_ellipsized(tester, title), isFalse,
      reason: '$name title ellipsized: ${tester.widget<M3SectionTitle>(title).text}');
}

bool _paragraphClipped(RenderParagraph p) {
  if (p.didExceedMaxLines) return true;
  if (p.constraints.hasBoundedWidth &&
      p.size.width > p.constraints.maxWidth + 0.5) {
    return true;
  }
  return false;
}

void main() {
  ignoreGoogleFontLoadErrors();
  setUpAll(() async {
    await loadOosFonts();
    // Catalog codes use fontFamily: monospace; map it to the real Cairo
    // so one-line width at 1280 matches the live shell, not Ahem (1em/char).
    final bytes = File('test/fonts/Cairo-Variable.ttf').readAsBytesSync();
    final data = ByteData.view(Uint8List.fromList(bytes).buffer);
    await (FontLoader('monospace')..addFont(Future.value(data))).load();
    await (FontLoader('Courier')..addFont(Future.value(data))).load();
  });
  setUp(AppCache.clear);

  testWidgets(
      'Targets, Sell-In KPIs/waterfall, and Product Master codes fit the live 1280 shell',
      (tester) async {
    await _pumpShell(tester, SellOutExplorerScreen(apiClient: ApiClient()));

    final soCard = find.byKey(const ValueKey('kpi_card_Net Sales (EGP)'));
    expect(soCard, findsOneWidget);
    expect(tester.getSize(soCard).height, closeTo(138.0, 1.0));
    final soTitle = find.descendant(
        of: soCard, matching: find.byType(M3SectionTitle));
    final sellOutStyle = _titleStyle(tester, soTitle);
    expect(sellOutStyle.fontSize, 16.0);

    // --- Sell-Out Targets tab ---
    final targetsTab = find.text('المستهدفات');
    expect(targetsTab, findsWidgets);
    await tester.tap(targetsTab.first);
    await tester.pumpAndSettle();

    const targetKeys = [
      'targets_kpi_card_مستهدف المبيعات',
      'targets_kpi_card_المحقق',
      'targets_kpi_card_نسبة التحقيق',
      'targets_kpi_card_الفرق',
    ];
    for (final k in targetKeys) {
      _assertSellOutCard(
        tester,
        card: find.byKey(ValueKey(k)),
        sellOutTitle: sellOutStyle,
        name: 'Targets $k',
      );
    }
    expect(find.text('مستهدف المبيعات'), findsWidgets);
    expect(find.text('المحقق'), findsWidgets);
    expect(find.text('نسبة التحقيق'), findsWidgets);
    // Long forms are tooltips only, not the visible title.
    expect(find.text('نسبة التحقيق الإجمالية'), findsNothing);
    expect(find.text('المحقق (Sell-Out)'), findsNothing);

    // --- Sell-In data tab + waterfall ---
    await _pumpShell(
      tester,
      SellInExplorerScreen(apiClient: ApiClient(tenantId: 'tenant-adeco')),
    );
    const sellInKeys = [
      'kpi_card_Net Sell-In after returns (excl. VAT)',
      'kpi_card_Quantity (cases)',
      'kpi_card_Weight (t)',
      'kpi_card_Gross Sell-In (incl. VAT)',
    ];
    for (final k in sellInKeys) {
      _assertSellOutCard(
        tester,
        card: find.byKey(ValueKey(k)),
        sellOutTitle: sellOutStyle,
        name: 'Sell-In $k',
      );
    }
    expect(find.text('صافي التوريد'), findsWidgets);
    expect(find.text('قيمة الفواتير'), findsWidgets);
    expect(find.text('صافي التوريد بعد المرتجعات'), findsNothing);
    expect(find.text('قيمة الفواتير شامل الضريبة'), findsNothing);

    final strip = find.byKey(const ValueKey('sellin_waterfall_strip'));
    expect(strip, findsOneWidget);
    final stripRect = tester.getRect(strip);
    for (final label in [
      '1. السعر الرسمي',
      '2. خصم الفاتورة',
      '3. خصم إضافي للسلسلة',
      '4. صافي التوريد',
      '5. الضريبة 14%',
      '6. الفواتير',
    ]) {
      final f = find.text(label);
      expect(f, findsWidgets, reason: 'waterfall missing $label');
      final r = tester.getRect(f.first);
      expect(r.left + 0.5, greaterThanOrEqualTo(stripRect.left),
          reason: '$label clipped on the start of the strip');
      expect(r.right - 0.5, lessThanOrEqualTo(stripRect.right),
          reason: '$label clipped on the end of the strip');
      expect(_ellipsized(tester, f.first), isFalse,
          reason: 'waterfall label ellipsized: $label');
    }
    expect(tester.takeException(), isNull);

    // --- Product Master catalog at the same shell ---
    await pumpProductMaster(
      tester,
      width: kLiveViewportWidth,
      withSidebar: true,
    );
    expect(find.text('FGCL-0550-0001'), findsWidgets,
        reason: 'item code must be fully visible on one line at 1280');
    expect(find.text('6221133000181'), findsWidgets,
        reason: 'barcode must be fully visible on one line at 1280');
    // Barcode and item code share one column; carton / unit-excl prices are
    // behind the columns menu at 1280 so the table fits without h-scroll.
    for (final header in [
      'الباركود / الكود',
      'اسم الصنف',
      'السعر ش.ض',
      'الصافي',
      'النوع / السحب',
    ]) {
      final f = find.text(header);
      expect(f, findsWidgets, reason: 'missing header $header');
      final para = tester.renderObject<RenderParagraph>(
          find.descendant(of: f, matching: find.byType(RichText)).first);
      expect(_paragraphClipped(para), isFalse,
          reason: 'header clipped: $header');
    }
    for (final value in ['FGCL-0550-0001', '6221133000181']) {
      final f = find.text(value);
      final para = tester.renderObject<RenderParagraph>(
          find.descendant(of: f, matching: find.byType(RichText)).first);
      expect(_paragraphClipped(para), isFalse, reason: 'value clipped: $value');
      expect(para.size.height, lessThan(24.0),
          reason: '$value must stay on one line');
    }
    expect(tester.takeException(), isNull);
  });
}
