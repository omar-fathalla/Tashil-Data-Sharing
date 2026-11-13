// Upload page M3 parity with Sell-Out / Sell-In: dropdowns never clip,
// archive table wraps to 3 lines and centres every column except the file
// name, search hint is fully visible, KPI tiles use the shared card.
// Made-up fixtures only. Real Cairo font, 1280dp and 1024dp.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:tashil_web/core/data/app_cache.dart';
import 'package:tashil_web/core/network/api_client.dart';
import 'package:tashil_web/core/theme/app_theme.dart';
import 'package:tashil_web/core/utils/arabic_plural.dart';
import 'package:tashil_web/core/widgets/m3_summary_kpi_card.dart';
import 'package:tashil_web/core/widgets/m3_search_field.dart';
import 'package:tashil_web/core/widgets/table_scroll_container.dart';
import 'package:tashil_web/features/data_ingestion/presentation/screens/upload_portal_screen.dart';
import 'package:tashil_web/features/navigation/presentation/desktop_sidebar.dart';

import 'support/real_fonts.dart';

class UploadFixtureApi extends ApiClient {
  UploadFixtureApi() : super(tenantId: 'tenant-adeco');

  @override
  Future<List<RetailChainModel>> getRetailChains({String? targetTenant}) async {
    return [
      RetailChainModel(
        chainId: 'fathalla',
        tenantId: 'adeco',
        displayName: 'أسواق فتح الله (Fathalla Market)',
        code: 'fathalla',
        storeCount: 42,
      ),
      RetailChainModel(
        chainId: 'gomla',
        tenantId: 'adeco',
        displayName: 'جملة ماركت (Gomla Market)',
        code: 'gomla',
        storeCount: 18,
      ),
    ];
  }

  @override
  Future<UploadedFilesArchiveResponse> getUploadedFilesArchive({
    String? chain,
    String? year,
    String? searchQuery,
    String? targetTenant,
    String? fileType,
  }) async {
    final files = [
      ArchivedExcelFileModel(
        id: 'u1',
        tenantId: 'tenant-adeco',
        fileName:
            'تقرير مبيعات أسواق فتح الله لفروع الإسكندرية والدلتا لشهر أكتوبر 2026 - نسخة مراجعة نهائية.xlsx',
        contentType:
            'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
        fileSizeBytes: 2458624,
        retailChain: 'fathalla',
        chainNameAr: 'أسواق فتح الله',
        chainNameEn: 'Fathalla Market',
        targetYear: '2026',
        targetMonth: '10',
        rowsIngested: 81294,
        branchesCount: 42,
        totalRevenue: 127133355,
        uploadedAt: '2026-11-02T10:15:00Z',
        lastIngestedAt: '2026-11-12T18:40:00Z',
      ),
      ArchivedExcelFileModel(
        id: 'u2',
        tenantId: 'tenant-adeco',
        fileName: 'Gomla-SellOut-Sep-2026-revised-final-v3.xlsx',
        contentType:
            'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
        fileSizeBytes: 884736,
        retailChain: 'gomla',
        chainNameAr: 'جملة ماركت',
        chainNameEn: 'Gomla Market',
        targetYear: '2026',
        targetMonth: '09',
        rowsIngested: 22011,
        branchesCount: 18,
        totalRevenue: 18450220,
        uploadedAt: '2026-10-08T08:00:00Z',
      ),
    ];
    return UploadedFilesArchiveResponse(
      tenantId: 'tenant-adeco',
      totalCount: files.length,
      chainCounts: const {'fathalla': 1, 'gomla': 1},
      files: files,
    );
  }
}

/// Live-like Adeco chains at 1280×800 (sidebar + six archive tabs, including الوكالة).
class UploadLiveFixtureApi extends UploadFixtureApi {
  @override
  Future<List<RetailChainModel>> getRetailChains({String? targetTenant}) async {
    return [
      ...await super.getRetailChains(targetTenant: targetTenant),
      RetailChainModel(
        chainId: 'beet-elgomla',
        tenantId: 'adeco',
        displayName: 'بيت الجملة (Beet El Gomla)',
        code: 'beet-elgomla',
        storeCount: 9,
      ),
      RetailChainModel(
        chainId: 'qa-test',
        tenantId: 'adeco',
        displayName: 'QA Test',
        code: 'qa-test',
        storeCount: 0,
      ),
      RetailChainModel(
        chainId: 'chain-1080314',
        tenantId: 'adeco',
        displayName: 'الوكالة (El Wakala)',
        code: 'chain-1080314',
        storeCount: 4,
      ),
    ];
  }

  @override
  Future<UploadedFilesArchiveResponse> getUploadedFilesArchive({
    String? chain,
    String? year,
    String? searchQuery,
    String? targetTenant,
    String? fileType,
  }) async {
    final base = await super.getUploadedFilesArchive(
      chain: chain,
      year: year,
      searchQuery: searchQuery,
      targetTenant: targetTenant,
      fileType: fileType,
    );
    return UploadedFilesArchiveResponse(
      tenantId: base.tenantId,
      totalCount: base.totalCount,
      chainCounts: const {
        'fathalla': 1,
        'gomla': 1,
        'beet-elgomla': 0,
        'qa-test': 0,
        'chain-1080314': 3,
      },
      files: base.files,
    );
  }
}

List<String> clippedDropdowns(WidgetTester tester) {
  final out = <String>[];
  for (final e in find
      .byType(DropdownMenu<int>)
      .evaluate()
      .followedBy(find.byType(DropdownMenu<String>).evaluate())
      .followedBy(find.byType(DropdownMenu<String?>).evaluate())) {
    final dd = e.widget as DropdownMenu;
    final label = dd.label is Text ? (dd.label! as Text).data : '?';
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
      out.add('$label: "$text" ${tp.width.toStringAsFixed(1)} > '
          '${box.size.width.toStringAsFixed(1)}');
    }
    tp.dispose();
  }
  return out;
}

Future<void> pumpUpload(
  WidgetTester tester, {
  double width = 1280,
  double height = 3000,
  bool sidebar = false,
  ApiClient? api,
}) async {
  tester.view.physicalSize = Size(width, height);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final page = UploadPortalScreen(apiClient: api ?? UploadFixtureApi());
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
        body: sidebar
            ? Row(children: [
                DesktopSidebar(
                  selectedIndex: 10,
                  onDestinationSelected: (_) {},
                  activeTenant: 'adeco',
                  onTenantChanged: (_) {},
                ),
                Expanded(child: page),
              ])
            : page,
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

void expectTextFullyVisible(WidgetTester tester, Finder f, String what) {
  expect(f, findsWidgets, reason: what);
  final e = f.evaluate().first;
  final widget = e.widget;
  if (widget is Text && widget.data != null) {
    final box = tester.getRect(f.first);
    final style = widget.style;
    final tp = TextPainter(
      text: TextSpan(text: widget.data, style: style),
      textDirection: Directionality.of(e),
      textScaler: MediaQuery.textScalerOf(e),
      maxLines: widget.maxLines,
    )..layout();
    final cut = (widget.overflow == TextOverflow.ellipsis &&
            widget.maxLines != null &&
            tp.didExceedMaxLines) ||
        (widget.maxLines == 1 && tp.width > box.width + 0.5);
    tp.dispose();
    expect(cut, isFalse,
        reason: '$what is truncated ($box, overflow=${widget.overflow})');
  }
  try {
    final p = tester.renderObject<RenderParagraph>(f.first);
    expect(p.didExceedMaxLines, isFalse, reason: '$what exceeded maxLines');
  } catch (_) {}
}

double horizontalScrollExtent(WidgetTester tester, Finder table) {
  final scrollable = find.ancestor(
      of: table,
      matching: find.byWidgetPredicate((w) =>
          w is Scrollable &&
          w.axisDirection != AxisDirection.down &&
          w.axisDirection != AxisDirection.up));
  if (scrollable.evaluate().isEmpty) return 0.0;
  return tester
      .state<ScrollableState>(scrollable.first)
      .position
      .maxScrollExtent;
}

void expectInViewport(
    WidgetTester tester, Finder f, double width, String what) {
  expect(f, findsWidgets, reason: what);
  final r = tester.getRect(f.first);
  expect(r.left, greaterThanOrEqualTo(-0.5), reason: '$what $r');
  expect(r.right, lessThanOrEqualTo(width + 0.5), reason: '$what $r');
}

void main() {
  GoogleFonts.config.allowRuntimeFetching = false;
  setUpAll(() async {
    await loadRealCairoFont();
    final bytes = File('test/fonts/Cairo-Variable.ttf').readAsBytesSync();
    final data = ByteData.view(Uint8List.fromList(bytes).buffer);
    await (FontLoader('Cairo-Regular')..addFont(Future.value(data))).load();
  });
  setUp(AppCache.clear);

  for (final width in [1280.0, 1024.0]) {
    testWidgets('Upload dropdowns show their full value at ${width.toInt()}',
        (tester) async {
      await pumpUpload(tester, width: width);
      expect(find.textContaining('تلقائي من الشيت'), findsWidgets);
      expect(clippedDropdowns(tester), isEmpty);
    });
  }

  testWidgets('Upload archive is a full-width TableScrollContainer',
      (tester) async {
    await pumpUpload(tester);
    expect(find.byKey(const ValueKey('upload_archive_files_table')),
        findsOneWidget);
    expect(find.byType(TableScrollContainer), findsWidgets);
    final table = tester
        .getRect(find.byKey(const ValueKey('upload_archive_files_table')));
    final section = tester
        .getRect(find.byKey(const ValueKey('excel_upload_archive_section')));
    expect(table.width, greaterThan(section.width * 0.6));
  });

  testWidgets('Upload file name wraps to 3 lines; other cells are centred',
      (tester) async {
    await pumpUpload(tester);
    final name = find.descendant(
      of: find.byKey(const ValueKey('archive_file_card_u1')),
      matching: find.byType(Text),
    );
    expect(name, findsWidgets);
    final nameText = tester.widget<Text>(name.first);
    expect(nameText.maxLines, 3);
    expect(nameText.textAlign, TextAlign.start);

    final period = find.text('10 / 2026');
    expect(period, findsOneWidget);
    expect(tester.widget<Text>(period).maxLines, 3);
    expect(tester.widget<Text>(period).textAlign, TextAlign.center);
  });

  testWidgets('Upload search hint is fully visible', (tester) async {
    await pumpUpload(tester);
    expect(find.byType(M3SearchFieldWidth), findsOneWidget);
    const hint = 'ابحث باسم ملف الإكسيل أو السلسلة (مثال: 40-Adco أو Book1)...';
    final wrap = find.byType(M3SearchFieldWidth);
    final box = tester.getSize(wrap);
    final min = M3SearchFieldWidth.minWidthFor(tester.element(wrap), hint);
    expect(box.width + 0.5, greaterThanOrEqualTo(min));
  });

  testWidgets('Upload uses arabic plural counts and shared KPI cards',
      (tester) async {
    await pumpUpload(tester);
    expect(find.text(countFiles(2)), findsWidgets);
    expect(find.text(countSheets(2)), findsWidgets);
    expect(find.byType(M3SummaryKpiCard), findsNWidgets(4));
    expect(find.byKey(const ValueKey('kpi_card_Files')), findsOneWidget);
    expect(find.byKey(const ValueKey('kpi_card_Chains')), findsOneWidget);
    expect(find.byKey(const ValueKey('kpi_card_Records')), findsOneWidget);
    expect(find.byKey(const ValueKey('kpi_card_Revenue')), findsOneWidget);
  });

  for (final width in [1280.0, 1024.0]) {
    testWidgets(
        'Upload archive table does not scroll horizontally at ${width.toInt()} with long filenames',
        (tester) async {
      await pumpUpload(tester, width: width);
      expect(tester.takeException(), isNull);
      final table = find.byKey(const ValueKey('upload_archive_files_table'));
      expect(table, findsOneWidget);
      expect(find.text('الحجم'), findsNothing);
      expect(find.text('تاريخ الرفع'), findsOneWidget);
      expect(find.textContaining('تقرير مبيعات أسواق فتح الله'), findsWidgets);
      final name = tester.widget<Text>(find
          .descendant(
            of: find.byKey(const ValueKey('archive_file_card_u1')),
            matching: find.byType(Text),
          )
          .first);
      expect(name.maxLines, 3);
      expect(
        horizontalScrollExtent(tester, table),
        lessThanOrEqualTo(2.0),
        reason:
            'archive table must fill the page with no leftover scroll at $width',
      );
      expectInViewport(tester, find.text('الملف'), width, 'header الملف');
      expectInViewport(
          tester, find.text('تاريخ الرفع'), width, 'header تاريخ الرفع');
      expectInViewport(
        tester,
        find.byKey(const ValueKey('upload_archive_actions_column')),
        width,
        'pinned actions',
      );
      expectInViewport(
        tester,
        find.byKey(const ValueKey('archive_action_group_u1')),
        width,
        'row actions',
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
      'Upload last-import date is fully visible at 1280 with sidebar (live layout)',
      (tester) async {
    await pumpUpload(tester,
        width: 1280, sidebar: true, api: UploadLiveFixtureApi());
    expect(tester.takeException(), isNull);
    const width = 1280.0;
    expectInViewport(
        tester, find.text('آخر استيراد'), width, 'آخر استيراد label');
    expectInViewport(
        tester, find.text('2026-11-02 10:15'), width, 'uploaded timestamp');
    expectInViewport(
        tester, find.text('2026-11-12 18:40'), width, 'last-import timestamp');
    expectTextFullyVisible(tester, find.text('آخر استيراد'), 'آخر استيراد');
    expectTextFullyVisible(
        tester, find.text('2026-11-02 10:15'), 'uploaded timestamp');
    expectTextFullyVisible(
        tester, find.text('2026-11-12 18:40'), 'last-import timestamp');
    expect(find.textContaining('آخر استيراد:'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'Upload ingestion dropdown labels are short and uncut at 1280 with sidebar',
      (tester) async {
    await pumpUpload(tester,
        width: 1280, sidebar: true, api: UploadLiveFixtureApi());
    expect(find.text('السلسلة *'), findsWidgets);
    expect(find.text('السنة'), findsWidgets);
    expect(find.text('الشهر'), findsWidgets);
    expect(find.text('سلسلة التجزئة المستهدفة (Target Retail Chain) *'),
        findsNothing);
    expect(find.text('سنة البيانات (Target Year)'), findsNothing);
    expect(find.text('الشهر المستهدف (Target Month)'), findsNothing);
    expectTextFullyVisible(tester, find.text('السلسلة *'), 'سلسلة label');
    expectTextFullyVisible(tester, find.text('السنة').first, 'سنة label');
    expectTextFullyVisible(tester, find.text('الشهر').first, 'شهر label');
    expect(find.textContaining('تلقائي من الشيت'), findsWidgets);
    expect(clippedDropdowns(tester), isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'Upload الوكالة archive tab is fully visible at 1280 with sidebar',
      (tester) async {
    await pumpUpload(tester,
        width: 1280, sidebar: true, api: UploadLiveFixtureApi());
    const width = 1280.0;
    expect(find.byKey(const ValueKey('archive_chain_tab_chain-1080314')),
        findsOneWidget);
    expect(find.text('الوكالة (3)'), findsWidgets);
    expectInViewport(tester, find.text('الوكالة (3)'), width, 'الوكالة tab');
    expectInViewport(tester, find.text('الكل (5)'), width, 'الكل tab');
    expectInViewport(
        tester, find.text('أسواق فتح الله (1)'), width, 'Fathalla tab');
    expectInViewport(tester, find.text('QA Test (0)'), width, 'QA Test tab');
    expectTextFullyVisible(
        tester, find.text('الوكالة (3)'), 'الوكالة tab label');
    expect(tester.takeException(), isNull);
  });
}
