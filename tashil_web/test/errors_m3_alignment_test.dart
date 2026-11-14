// Errors (Data Quality): Sell-Out table, typography and card symmetry.
// Real Cairo font, 1280, 1024, and the live 1030 content width
// (1280 viewport minus the 250dp sidebar). Long live-like fixture values.
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tashil_web/core/network/api_client.dart';
import 'package:tashil_web/core/theme/app_theme.dart';
import 'package:tashil_web/core/utils/currency_formatter.dart';
import 'package:tashil_web/core/widgets/m3_section_title.dart';
import 'package:tashil_web/core/widgets/m3_summary_kpi_card.dart';
import 'package:tashil_web/features/data_quality/data/data_quality_repository.dart';
import 'package:tashil_web/features/data_quality/presentation/screens/data_quality_screen.dart';
import 'package:tashil_web/features/navigation/presentation/desktop_sidebar.dart';
import 'package:tashil_web/features/sell_out_analytics/presentation/screens/sell_out_explorer_screen.dart';

import 'errors_m3_support.dart';
import 'support/live_viewport.dart';
import 'support/text_visibility.dart';

const _searchHint = 'بحث بالصنف أو الكود أو الباركود أو النوع...';

List<String> _cutBeforeThreeLines(WidgetTester tester, Finder scope,
    {bool Function(Text t)? only}) {
  final out = <String>[];
  for (final e
      in find.descendant(of: scope, matching: find.byType(Text)).evaluate()) {
    final t = e.widget as Text;
    if (only != null && !only(t)) continue;
    if (t.data == null || t.data!.isEmpty) continue;
    final p = tester
        .renderObject<RenderParagraph>(find.byElementPredicate((x) => x == e));
    if (p.didExceedMaxLines && (t.maxLines ?? 99) < 3) {
      out.add('"${t.data}" cut at maxLines ${t.maxLines}');
    }
  }
  return out;
}

List<String> _clippedDropdowns(WidgetTester tester) {
  final out = <String>[];
  for (final e in find
      .byType(DropdownMenu<int>)
      .evaluate()
      .followedBy(find.byType(DropdownMenu<String>).evaluate())) {
    final editable = find.descendant(
        of: find.byElementPredicate((x) => x == e),
        matching: find.byType(EditableText));
    if (editable.evaluate().isEmpty) continue;
    final et = tester.widget<EditableText>(editable.first);
    final text = et.controller.text;
    if (text.isEmpty) continue;
    final box = tester.renderObject<RenderBox>(editable.first);
    final tp = TextPainter(
      text: TextSpan(text: text, style: et.style),
      textDirection: Directionality.of(e),
      textScaler: MediaQuery.textScalerOf(e),
      maxLines: 1,
    )..layout();
    if (tp.width > box.size.width + 0.5) {
      out.add('"$text" ${tp.width.toStringAsFixed(1)} > '
          '${box.size.width.toStringAsFixed(1)}');
    }
  }
  return out;
}

bool _valueIsOneLine(WidgetTester tester, Finder valueFinder) {
  expect(valueFinder, findsOneWidget);
  final el = valueFinder.evaluate().single;
  final text = el.widget as Text;
  final p = tester
      .renderObject<RenderParagraph>(find.byElementPredicate((x) => x == el));
  final tp = TextPainter(
    text: TextSpan(text: text.data, style: text.style ?? p.text.style),
    textDirection: Directionality.of(el),
    textScaler: MediaQuery.textScalerOf(el),
    maxLines: 1,
  )..layout(maxWidth: p.size.width);
  return (p.size.height - tp.height).abs() <= 1.5 && !p.didExceedMaxLines;
}

double _hScrollExtent(WidgetTester tester, Finder scope) {
  final scrollable =
      find.descendant(of: scope, matching: find.byType(Scrollable));
  expect(scrollable, findsWidgets);
  for (final el in scrollable.evaluate()) {
    final s = el.widget as Scrollable;
    if (s.axisDirection == AxisDirection.right ||
        s.axisDirection == AxisDirection.left) {
      final state = tester.state<ScrollableState>(find.byWidget(s));
      if (state.position.hasContentDimensions) {
        return state.position.maxScrollExtent;
      }
    }
  }
  return 0;
}

bool _onScreen(WidgetTester tester, Finder f, {double width = 1280}) {
  expect(f, findsWidgets);
  final box = tester.getRect(f.first);
  return box.left < width - 1 &&
      box.right > 1 &&
      box.top < 8000 &&
      box.bottom > 0;
}

_CardMetrics _metrics(WidgetTester tester, Finder card) {
  expect(card, findsOneWidget);
  final container = tester.widget<Container>(
      find.descendant(of: card, matching: find.byType(Container)).first);
  final padding = container.padding! as EdgeInsets;
  final icon = tester.widget<Icon>(
      find.descendant(of: card, matching: find.byType(Icon)).first);
  final titleText = tester.widget<Text>(find.descendant(
      of: find.descendant(of: card, matching: find.byType(M3SectionTitle)),
      matching: find.byType(Text)));
  final values = find.descendant(
      of: card,
      matching: find.byWidgetPredicate((w) =>
          w is Text &&
              w.key is ValueKey &&
              (w.key as ValueKey).value.toString().startsWith('dq_') ||
          (w is Text &&
              w.key is ValueKey &&
              (w.key as ValueKey).value.toString().startsWith('kpi_value_'))));
  Text value;
  if (values.evaluate().isNotEmpty) {
    value = tester.widget<Text>(values.first);
  } else {
    final texts = tester
        .widgetList<Text>(
            find.descendant(of: card, matching: find.byType(Text)))
        .toList();
    value = texts.length > 1 ? texts[1] : texts.first;
  }
  return _CardMetrics(
    padding: padding,
    iconSize: icon.size ?? 0,
    titleStyle: titleText.style,
    valueStyle: value.style,
    size: tester.getSize(card),
  );
}

class _CardMetrics {
  _CardMetrics({
    required this.padding,
    required this.iconSize,
    required this.titleStyle,
    required this.valueStyle,
    required this.size,
  });
  final EdgeInsets padding;
  final double iconSize;
  final TextStyle? titleStyle;
  final TextStyle? valueStyle;
  final Size size;
}

Future<void> _pumpSellOut(WidgetTester tester, {required double width}) async {
  tester.view.physicalSize = Size(width, 2400);
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
      child: Scaffold(body: SellOutExplorerScreen(apiClient: ApiClient())),
    ),
  ));
  await tester.pumpAndSettle();
}

Future<void> _pumpPage(WidgetTester tester, {required double width}) {
  return pumpErrors(
    tester,
    DataQualityScreen(
      dataSource: ErrorsShotSource(),
      pollInterval: const Duration(hours: 1),
    ),
    width: width,
    height: 3600,
  );
}

TextTheme _withSymbolFallback(TextTheme t) {
  TextStyle? f(TextStyle? s) =>
      s?.copyWith(fontFamilyFallback: const ['NotoSansSymbols2']);
  return t.copyWith(
    headlineSmall: f(t.headlineSmall),
    titleLarge: f(t.titleLarge),
    titleMedium: f(t.titleMedium),
    titleSmall: f(t.titleSmall),
    bodyLarge: f(t.bodyLarge),
    bodyMedium: f(t.bodyMedium),
    bodySmall: f(t.bodySmall),
    labelLarge: f(t.labelLarge),
    labelMedium: f(t.labelMedium),
    labelSmall: f(t.labelSmall),
  );
}

ThemeData _liveShellTheme() {
  final theme = AppTheme.light();
  return theme.copyWith(textTheme: _withSymbolFallback(theme.textTheme));
}

Future<void> _pumpPageWithSidebar(WidgetTester tester,
    {double width = kLiveViewportWidth}) async {
  tester.view.physicalSize = Size(width, 3600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(MaterialApp(
    theme: _liveShellTheme(),
    locale: const Locale('ar'),
    supportedLocales: const [Locale('ar'), Locale('en')],
    localizationsDelegates: const [
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    home: Directionality(
      textDirection: TextDirection.rtl,
      child: Row(
        children: [
          DesktopSidebar(
            selectedIndex: 12,
            onDestinationSelected: (_) {},
            activeTenant: 'adeco',
            onTenantChanged: (_) {},
          ),
          Expanded(
            child: Scaffold(
              body: DataQualityScreen(
                dataSource: ErrorsShotSource(),
                pollInterval: const Duration(hours: 1),
              ),
            ),
          ),
        ],
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

/// Delegates to [labelFullyVisible]: glyphs must sit inside the column cell,
/// not merely inside the table.
bool _labelFullyVisible(WidgetTester tester, Finder scope, String expected) {
  return labelFullyVisible(tester, expected, scope: scope);
}

void _assertTableFitsLiveContent(WidgetTester tester,
    {required double contentWidth}) {
  final scroller = find.byKey(const ValueKey('dq_table_scroll'));
  expect(scroller, findsOneWidget);
  expect(_hScrollExtent(tester, scroller), lessThanOrEqualTo(2.0));
  expect(
      _onScreen(tester, find.byKey(const ValueKey('dq_item_name')),
          width: contentWidth),
      isTrue);
  expect(_onScreen(tester, find.text('مفتوحة'), width: contentWidth), isTrue);
  expect(
      _onScreen(tester, find.byKey(const ValueKey('dq_status_e1')),
          width: contentWidth),
      isTrue);

  final table = find.byKey(const ValueKey('dq_table'));
  for (final header in [
    'الخطورة',
    'النوع',
    'كود الصنف',
    'الباركود',
    'اسم الصنف',
    'الموجود',
    'المتوقع',
    'التأثير',
    'الحالة',
  ]) {
    expect(_labelFullyVisible(tester, table, header), isTrue, reason: header);
  }
  expect(_labelFullyVisible(tester, table, kLongSkuName), isTrue,
      reason: 'item name');
  expect(_labelFullyVisible(tester, table, kLongTypeMissing), isTrue,
      reason: 'type');
  expect(_labelFullyVisible(tester, table, kLongFound), isTrue,
      reason: 'found value');
  expect(_labelFullyVisible(tester, table, kLongExpected), isTrue,
      reason: 'live expected «الصنف يتضاف لكارتة الأصناف» must show fully, '
          'including الأصناف, in ≤3 lines');
  expect(labelPaintedLineCount(tester, kLongExpected, scope: table),
      lessThanOrEqualTo(3),
      reason: 'live expected phrase');
  expect(_labelFullyVisible(tester, table, kLiveArabicCode), isTrue,
      reason: 'ماكسيل ماجيك متخصص عادي عادي must not clip at the cell edge');
  expect(codePaintedLineCount(tester, kLiveArabicCode, scope: table),
      inInclusiveRange(1, 3),
      reason: 'Arabic item code wraps at words, ≤3 lines');

  for (final code in [kLiveMissingCode, kLiveFgccCode, kLivePrccCode]) {
    expect(codeBreaksOnlyAtHyphens(tester, code, scope: table), isTrue,
        reason: '$code must stay intact and fully visible');
    expect(codePaintedLineCount(tester, code, scope: table), 1,
        reason: '$code must stay on one painted line at the live 1280 shell');
    expect(codeIsSingleLine(tester, code, scope: table), isTrue,
        reason: '$code must stay on one line at the live 1280 shell');
  }
  expect(
      codeColumnHasSlack(tester, kLiveMissingCode, slack: 16.0, scope: table),
      isTrue,
      reason: 'QA-NOT-IN-MASTER-999 column must keep ≥16dp slack over the '
          'one-line Cairo advance (v157 wrapped when slack was ~4dp)');
  for (final word in [
    'الخطورة',
    'مفتوحة',
    'الحالة',
    'تحذير',
    'حرجة',
    'متجاهلة'
  ]) {
    expect(shortWordUnsplit(tester, word, scope: table), isTrue,
        reason: 'short word "$word" must not split mid-word');
  }

  final chip = find.byKey(const ValueKey('dq_type_chip_missing_sku'));
  expect(chip, findsOneWidget);
  final chipText = tester.widget<Text>(
      find.descendant(of: chip, matching: find.byType(Text)).first);
  expect(chipText.data, 'ناقص');
  expect(_labelFullyVisible(tester, chip, chipText.data!), isTrue,
      reason: 'short type chip must sit inside the chip at $contentWidth');
  final desc = find.byKey(const ValueKey('dq_type_desc_missing_sku'));
  expect(desc, findsOneWidget);
  expect(tester.widget<Text>(desc).data, kLongTypeMissing);
  // Key is on the Text itself — scope the page, not the Text (descendant
  // lookup would miss self).
  expect(
      labelFullyVisible(tester, kLongTypeMissing,
          scope: find.byType(DataQualityScreen)),
      isTrue,
      reason: 'type description must stay fully visible at $contentWidth');
}

void main() {
  ignoreGoogleFontLoadErrors();
  setUpAll(loadErrorsFonts);

  for (final width in [1280.0, 1024.0]) {
    testWidgets(
        'Errors table fits ${width.toInt()} with no horizontal scroll; name and status visible together',
        (tester) async {
      await _pumpPage(tester, width: width);

      expect(find.byKey(const ValueKey('dq_table')), findsOneWidget);
      final scroller = find.byKey(const ValueKey('dq_table_scroll'));
      expect(scroller, findsOneWidget);
      expect(_hScrollExtent(tester, scroller), lessThanOrEqualTo(2.0));

      expect(find.byKey(const ValueKey('dq_item_name')), findsWidgets);
      expect(
          _onScreen(tester, find.byKey(const ValueKey('dq_item_name')),
              width: width),
          isTrue);
      expect(find.text('مفتوحة'), findsWidgets);
      expect(_onScreen(tester, find.text('مفتوحة'), width: width), isTrue);
      expect(find.byKey(const ValueKey('dq_status_e1')), findsOneWidget);
      expect(
          _onScreen(tester, find.byKey(const ValueKey('dq_status_e1')),
              width: width),
          isTrue);

      final dt =
          tester.widget<DataTable>(find.byKey(const ValueKey('dq_table')));
      for (final (i, c) in dt.columns.indexed) {
        expect(c.headingRowAlignment, MainAxisAlignment.center,
            reason: 'column $i');
      }
      for (final t in tester
          .widgetList<Text>(find.byKey(const ValueKey('dq_item_name')))) {
        expect(t.maxLines, 3);
        expect(t.textAlign, TextAlign.center);
      }
      expect(
        _cutBeforeThreeLines(
          tester,
          find.byType(DataQualityScreen),
          only: (text) => text.data != _searchHint,
        ),
        isEmpty,
      );
      expect(_clippedDropdowns(tester), isEmpty);
    });

    testWidgets(
        'Errors KPI card height, padding, fonts and icon match Sell-Out at ${width.toInt()}',
        (tester) async {
      await _pumpSellOut(tester, width: width);
      final soCard = find.byKey(const ValueKey('kpi_card_Net Sales (EGP)'));
      expect(soCard, findsOneWidget);
      final so = _metrics(tester, soCard);
      expect(so.padding, M3SummaryKpiStyle.padding);
      expect(so.iconSize, M3SummaryKpiStyle.iconSize);
      final soH = so.size.height;

      await _pumpPage(tester, width: width);
      expect(find.byKey(const ValueKey('dq_kpi_grid')), findsOneWidget);
      final dqCard = find.byKey(const ValueKey('dq_cleanliness_card'));
      expect(dqCard, findsOneWidget);
      final dq = _metrics(tester, dqCard);
      expect(dq.padding, so.padding);
      expect(dq.iconSize, so.iconSize);
      expect(dq.titleStyle?.fontSize, so.titleStyle?.fontSize);
      expect(dq.titleStyle?.fontWeight, so.titleStyle?.fontWeight);
      expect(dq.titleStyle?.fontFamily, so.titleStyle?.fontFamily);
      expect(dq.valueStyle?.fontSize, so.valueStyle?.fontSize);
      expect(dq.valueStyle?.fontWeight, so.valueStyle?.fontWeight);
      expect(dq.valueStyle?.fontFamily, so.valueStyle?.fontFamily);

      for (final key in [
        'dq_cleanliness_card',
        'dq_open_card',
        'dq_resolved_card',
        'dq_ignored_card',
      ]) {
        final card = find.byKey(ValueKey(key));
        expect(card, findsOneWidget, reason: key);
        expect(tester.getSize(card).height, closeTo(soH, 1.0),
            reason: '$key height at ${width.toInt()}');
      }

      for (final key in [
        'dq_cleanliness',
        'dq_value_open',
        'dq_value_resolved',
        'dq_value_ignored',
      ]) {
        expect(_valueIsOneLine(tester, find.byKey(ValueKey(key))), isTrue,
            reason: '$key must stay on one line at ${width.toInt()}');
      }

      // Live-like 2004 ends 03–10 → plural "أخطاء".
      expect(find.text('2004 أخطاء'), findsWidgets);
      expect(find.text('90.2%'), findsOneWidget);
    });
  }

  testWidgets(
      'Status dialog wraps long type and item names; ignore needs a reason',
      (tester) async {
    await _pumpPage(tester, width: 1280);
    final btn = find.byKey(const ValueKey('dq_status_e1'));
    expect(btn, findsOneWidget);
    await tester.ensureVisible(btn);
    await tester.pumpAndSettle();
    await tester.tap(btn);
    await tester.pumpAndSettle();

    expect(find.text('تغيير حالة الخطأ'), findsOneWidget);
    expect(find.textContaining(kLongTypeMissing), findsWidgets);
    expect(
        find.descendant(
            of: find.byType(AlertDialog), matching: find.text(kLongSkuName)),
        findsOneWidget);
    expect(_cutBeforeThreeLines(tester, find.byType(AlertDialog)), isEmpty);
    expect(_clippedDropdowns(tester), isEmpty);

    await tester.tap(find.byKey(const ValueKey('dq_status_save')));
    await tester.pumpAndSettle();
    expect(find.text('السبب مطلوب عند التجاهل'), findsOneWidget);
  });

  testWidgets(
      'Type chips use short word + description (TM pattern) at 1280',
      (tester) async {
    await _pumpPage(tester, width: 1280);
    final chip = find.byKey(const ValueKey('dq_type_chip_missing_sku'));
    expect(chip, findsOneWidget);
    expect(_onScreen(tester, chip), isTrue);
    final chipText = tester.widget<Text>(
        find.descendant(of: chip, matching: find.byType(Text)).first);
    expect(chipText.data, 'ناقص');
    expect(chipText.maxLines, greaterThanOrEqualTo(1));
    expect(chipText.overflow, isNot(TextOverflow.ellipsis));
    expect(chipText.softWrap, isTrue);

    final desc = find.byKey(const ValueKey('dq_type_desc_missing_sku'));
    expect(desc, findsOneWidget);
    final descText = tester.widget<Text>(desc);
    expect(descText.data, kLongTypeMissing);
    expect(descText.maxLines, greaterThanOrEqualTo(3));
    expect(descText.overflow, isNot(TextOverflow.ellipsis));
    expect(descText.overflow, isNot(TextOverflow.fade));
    expect(_cutBeforeThreeLines(tester, desc), isEmpty);
    expect(find.byKey(const ValueKey('dq_type_meta_missing_sku')),
        findsOneWidget);

    expect(find.byKey(const ValueKey('dq_type_chip_duplicate_barcode')),
        findsOneWidget);
    expect(
        tester
            .widget<Text>(find.descendant(
                of: find.byKey(const ValueKey('dq_type_chip_duplicate_barcode')),
                matching: find.byType(Text)))
            .data,
        'مكرر');
    expect(find.byKey(const ValueKey('dq_type_chip_price_mismatch')),
        findsOneWidget);
    expect(
        tester
            .widget<Text>(find.descendant(
                of: find.byKey(const ValueKey('dq_type_chip_price_mismatch')),
                matching: find.byType(Text)))
            .data,
        'سعر');
  });

  testWidgets(
      'empty rows show — cleanliness gauge, never fake 100.0%',
      (tester) async {
    await pumpErrors(
      tester,
      DataQualityScreen(
        dataSource: ErrorsShotSource(
          sum: const DataQualitySummary(
            types: [],
            totalRows: 0,
            criticalRows: 0,
            cleanlinessPct: 100,
            open: 79,
            resolved: 4,
          ),
          list: const [],
        ),
        pollInterval: const Duration(hours: 1),
      ),
      width: 1280,
    );
    expect(find.text('—'), findsOneWidget);
    expect(find.text('مفيش صفوف اتفحصت'), findsOneWidget);
    expect(find.text('100.0%'), findsNothing);
    expect(find.text('100%'), findsNothing);
  });

  testWidgets('missing impact cells show — not fake zeros', (tester) async {
    await pumpErrors(
      tester,
      DataQualityScreen(
        dataSource: ErrorsShotSource(
          sum: DataQualitySummary(
            types: kErrorsLiveSummary.types,
            totalRows: kErrorsLiveSummary.totalRows,
            criticalRows: kErrorsLiveSummary.criticalRows,
            cleanlinessPct: kErrorsLiveSummary.cleanlinessPct,
            open: 1,
            resolved: 0,
            ignored: 0,
            updatedAt: kErrorsLiveSummary.updatedAt,
          ),
          list: const [
            DataQualityIssue(
              id: 'no-impact',
              source: 'sell_out',
              type: 'missing_sku',
              typeLabel: kLongTypeMissing,
              severity: kDqWarning,
              itemCode: 'NO-IMPACT-1',
              itemName: 'صنف بدون تأثير محسوب',
              status: kDqOpen,
            ),
          ],
        ),
        pollInterval: const Duration(hours: 1),
      ),
      width: 1280,
    );
    expect(find.text('—'), findsWidgets);
    expect(find.text('0.00'), findsNothing);
    expect(find.text('0.0'), findsNothing);
    expect(find.textContaining('+0.0%'), findsNothing);
  });

  testWidgets('Errors page header matches Sell-Out M3PageHeader pattern',
      (tester) async {
    await _pumpPage(tester, width: 1280);
    expect(find.text('Errors'), findsOneWidget);
    expect(find.text('الأخطاء وجودة البيانات'), findsOneWidget);
    expect(find.byKey(const ValueKey('dq_refresh')), findsOneWidget);
    expect(find.byKey(const ValueKey('dq_export')), findsOneWidget);
  });

  testWidgets(
      'Errors table, headers and type chips fit at the live 1030 content width',
      (tester) async {
    await _pumpPage(tester, width: kLiveContentWidth);
    _assertTableFitsLiveContent(tester, contentWidth: kLiveContentWidth);
    expect(_clippedDropdowns(tester), isEmpty);

    for (final (key, title) in [
      ('dq_cleanliness_card', 'نظافة البيانات'),
      ('dq_open_card', 'مفتوحة'),
      ('dq_resolved_card', 'اتصلّحت'),
      ('dq_ignored_card', 'متجاهلة'),
    ]) {
      final card = find.byKey(ValueKey(key));
      expect(card, findsOneWidget, reason: key);
      final titleFinder = find.descendant(of: card, matching: find.text(title));
      expect(titleFinder, findsOneWidget, reason: title);
      final titleBox = tester.getRect(titleFinder);
      final cardBox = tester.getRect(card);
      expect(titleBox.left >= cardBox.left - 1.5, isTrue, reason: title);
      expect(titleBox.right <= cardBox.right + 1.5, isTrue, reason: title);
    }
  });

  testWidgets(
      'Errors table fits a 1280 viewport with the 250dp sidebar (1030 content)',
      (tester) async {
    await _pumpPageWithSidebar(tester);
    _assertTableFitsLiveContent(tester, contentWidth: kLiveContentWidth);
  });

  testWidgets(
      'at 1024+sidebar, codes may wrap at dashes only; no horizontal scroll',
      (tester) async {
    await _pumpPageWithSidebar(tester, width: 1024);
    const content = 1024.0 - kLiveSidebarWidth;
    final table = find.byKey(const ValueKey('dq_table'));
    expect(table, findsOneWidget);
    expect(
        _hScrollExtent(tester, find.byKey(const ValueKey('dq_table_scroll'))),
        lessThanOrEqualTo(2.0));
    for (final code in [kLiveMissingCode, kLiveFgccCode, kLivePrccCode]) {
      expect(codeBreaksOnlyAtHyphens(tester, code, scope: table), isTrue,
          reason: '$code');
    }
    expect(
        _onScreen(tester, find.byKey(const ValueKey('dq_item_name')),
            width: content),
        isTrue);
  });

  testWidgets(
      'QA-NOT-IN-MASTER-999 paints on one line at 1280+DesktopSidebar',
      (tester) async {
    await _pumpPageWithSidebar(tester);
    final table = find.byKey(const ValueKey('dq_table'));
    expect(table, findsOneWidget);
    expect(codePaintedLineCount(tester, kLiveMissingCode, scope: table), 1,
        reason: 'longest live code must be one painted line');
    expect(
        codeColumnHasSlack(tester, kLiveMissingCode, slack: 16.0, scope: table),
        isTrue,
        reason: 'column must be ≥16dp wider than the one-line advance');
    expect(
        _hScrollExtent(tester, find.byKey(const ValueKey('dq_table_scroll'))),
        lessThanOrEqualTo(2.0));
  });

  testWidgets(
      'live expected and Arabic item-code cells are fully visible at 1280+DesktopSidebar',
      (tester) async {
    await _pumpPageWithSidebar(tester);
    final table = find.byKey(const ValueKey('dq_table'));
    expect(table, findsOneWidget);
    for (final text in [
      kLongExpected,
      kLiveArabicCode,
      kLongTypeMissing,
      kLongSkuName,
      kLongFound,
      'الخطورة',
      'مفتوحة',
      'المتوقع',
      'الموجود',
    ]) {
      expect(_labelFullyVisible(tester, table, text), isTrue, reason: text);
      expect(labelPaintedLineCount(tester, text, scope: table),
          lessThanOrEqualTo(3),
          reason: text);
    }
    expect(codePaintedLineCount(tester, kLiveMissingCode, scope: table), 1);
    expect(codePaintedLineCount(tester, kLiveArabicCode, scope: table),
        lessThanOrEqualTo(3));
    expect(
        _hScrollExtent(tester, find.byKey(const ValueKey('dq_table_scroll'))),
        lessThanOrEqualTo(2.0));
  });

  testWidgets(
      'التأثير keeps the compact suffix on the number (401.0K) at 1280+sidebar',
      (tester) async {
    await _pumpPageWithSidebar(tester);
    final table = find.byKey(const ValueKey('dq_table'));
    expect(table, findsOneWidget);
    final compact = CurrencyFormatter.formatCompactEGP(401000);
    expect(compact, contains(CurrencyFormatter.scaleJoiner));
    expect(compact.contains('401.0K'), isFalse);

    final (prefix, suffix) = (
      compact.split(' ').first,
      compact.split(' ').last,
    );
    expect(prefix.contains('401.0'), isTrue);
    expect(prefix.contains('K'), isTrue);
    expect(suffix, 'ج.م');

    // The bound prefix is painted on one line; currency may be on the next.
    final prefixFinder = find.descendant(of: table, matching: find.textContaining('401.0'));
    expect(prefixFinder, findsWidgets);
    for (final e in prefixFinder.evaluate()) {
      final data = (e.widget as Text).data ?? '';
      if (!data.contains('K')) continue;
      expect(data.contains('401.0K'), isFalse,
          reason: 'K must be bound with a word joiner, got "$data"');
      final para = tester.renderObject<RenderParagraph>(
          find.byElementPredicate((x) => x == e));
      final numStart = data.indexOf('401.0');
      final kEnd = data.indexOf('K', numStart) + 1;
      expect(kEnd, greaterThan(numStart));
      final boxes = para.getBoxesForSelection(
        TextSelection(baseOffset: numStart, extentOffset: kEnd),
      );
      expect(boxes, isNotEmpty);
      expect({for (final b in boxes) b.toRect().top.round()}, hasLength(1),
          reason: '401.0 and K must share one line in "$data"');
      expect(data.contains('401.0'), isTrue);
      expect(data.contains('K'), isTrue);
    }
    expect(find.textContaining('401.0K'), findsNothing);
    expect(
        _hScrollExtent(tester, find.byKey(const ValueKey('dq_table_scroll'))),
        lessThanOrEqualTo(2.0));
  });
}
