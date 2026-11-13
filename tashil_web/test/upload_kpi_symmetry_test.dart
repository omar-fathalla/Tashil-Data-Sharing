// Owner rule (t437u): Upload KPI cards must match the Sell-Out reference
// exactly — padding, height, title/value typography, and icon size.
// Shared widget: M3SummaryKpiCard. Made-up fixtures. Real Cairo font, 1280dp.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:tashil_web/core/data/app_cache.dart';
import 'package:tashil_web/core/network/api_client.dart';
import 'package:tashil_web/core/theme/app_theme.dart';
import 'package:tashil_web/core/theme/m3_spacing.dart';
import 'package:tashil_web/core/widgets/m3_summary_kpi_card.dart';
import 'package:tashil_web/core/widgets/m3_section_title.dart';
import 'package:tashil_web/features/data_ingestion/presentation/screens/upload_portal_screen.dart';
import 'package:tashil_web/features/sell_out_analytics/presentation/screens/sell_out_explorer_screen.dart';

import 'support/real_fonts.dart';
import 'upload_page_m3_test.dart' show UploadFixtureApi;

class _Metrics {
  _Metrics({
    required this.padding,
    required this.height,
    required this.iconSize,
    required this.titleSize,
    required this.titleWeight,
    required this.titleFamily,
    required this.valueSize,
    required this.valueWeight,
    required this.valueFamily,
  });

  final EdgeInsetsGeometry? padding;
  final double height;
  final double? iconSize;
  final double? titleSize;
  final FontWeight? titleWeight;
  final String? titleFamily;
  final double? valueSize;
  final FontWeight? valueWeight;
  final String? valueFamily;
}

Future<void> _fonts() async {
  await loadRealCairoFont();
  final bytes = File('test/fonts/Cairo-Variable.ttf').readAsBytesSync();
  final data = ByteData.view(Uint8List.fromList(bytes).buffer);
  await (FontLoader('Cairo-Regular')..addFont(Future.value(data))).load();
}

Future<void> _pump(WidgetTester tester, Widget page) async {
  tester.view.physicalSize = const Size(1280, 3000);
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
      child: Scaffold(body: page),
    ),
  ));
  await tester.pumpAndSettle();
}

_Metrics _read(WidgetTester tester, Key key, Key valueKey) {
  final card = find.byKey(key);
  expect(card, findsOneWidget, reason: '$key missing');
  final widget = tester.widget(card);
  EdgeInsetsGeometry? padding;
  if (widget is Container) padding = widget.padding;
  if (widget is M3SummaryKpiCard) padding = M3SummaryKpiStyle.padding;

  final icon = tester.widget<Icon>(
      find.descendant(of: card, matching: find.byType(Icon)).first);
  final title = tester.widget<M3SectionTitle>(
      find.descendant(of: card, matching: find.byType(M3SectionTitle)).first);
  final titleText = tester.widget<Text>(find
      .descendant(of: find.byWidget(title), matching: find.byType(Text))
      .first);
  final value = tester.widget<Text>(find.byKey(valueKey));
  final ctx = tester.element(card);
  final titleStyle = titleText.style ?? M3SectionTitle.styleOf(ctx);
  return _Metrics(
    padding: padding,
    height: tester.getRect(card).height,
    iconSize: icon.size,
    titleSize: titleStyle?.fontSize,
    titleWeight: titleStyle?.fontWeight,
    titleFamily: titleStyle?.fontFamily,
    valueSize: value.style?.fontSize,
    valueWeight: value.style?.fontWeight,
    valueFamily: value.style?.fontFamily,
  );
}

void main() {
  GoogleFonts.config.allowRuntimeFetching = false;
  setUpAll(_fonts);
  setUp(AppCache.clear);

  testWidgets('Upload KPI card padding, height, fonts and icon match Sell-Out',
      (tester) async {
    await _pump(tester,
        SellOutExplorerScreen(apiClient: ApiClient(tenantId: 'tenant-adeco')));
    const sellOutKey = ValueKey('kpi_card_Net Sales (EGP)');
    const sellOutValue = ValueKey('kpi_value_Net Sales (EGP)');
    final sellOut = _read(tester, sellOutKey, sellOutValue);

    await _pump(tester, UploadPortalScreen(apiClient: UploadFixtureApi()));
    const uploadKey = ValueKey('kpi_card_Files');
    const uploadValue = ValueKey('kpi_value_Files');
    final upload = _read(tester, uploadKey, uploadValue);

    expect(sellOut.padding, const EdgeInsets.all(M3Spacing.sm));
    expect(upload.padding, sellOut.padding);
    expect(sellOut.iconSize, M3SummaryKpiStyle.iconSize);
    expect(upload.iconSize, sellOut.iconSize);
    expect(upload.titleSize, sellOut.titleSize);
    expect(upload.titleWeight, sellOut.titleWeight);
    expect(upload.titleFamily, sellOut.titleFamily);
    expect(upload.valueSize, sellOut.valueSize);
    expect(upload.valueWeight, FontWeight.w900);
    expect(sellOut.valueWeight, FontWeight.w900);
    expect(upload.valueFamily, sellOut.valueFamily);

    // Short titles/values stay on one line, so the tiles share a height.
    expect(upload.height, closeTo(sellOut.height, 2.0),
        reason:
            'Upload KPI height ${upload.height} vs Sell-Out ${sellOut.height}');
  });
}
