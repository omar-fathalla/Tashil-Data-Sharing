// Returns page: Sell-Out / Sell-In M3 treatment, synchronized matrix
// row heights, and display-only shared branch-name prefix stripping.
// Rendered at 1280 and 1024 content width with made-up fixture data.
// Live Chrome 150% zoom fullscreen on the box is a 1280×800 CSS viewport
// with the 250dp desktop sidebar, so a second harness pumps that shell.
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:tashil_web/core/data/app_cache.dart';
import 'package:tashil_web/core/data/available_years.dart';
import 'package:tashil_web/core/network/api_client.dart';
import 'package:tashil_web/core/theme/app_theme.dart';
import 'package:tashil_web/core/widgets/m3_summary_kpi_card.dart';
import 'package:tashil_web/core/widgets/m3_toolbar_button.dart';
import 'package:tashil_web/features/sell_in_returns/presentation/screens/sell_in_returns_screen.dart';
import 'package:tashil_web/features/sell_in_returns/presentation/widgets/returns_heatmap_matrix.dart';
import 'package:tashil_web/features/sell_out_analytics/presentation/screens/sell_out_explorer_screen.dart';

import 'support/real_fonts.dart';
import 'support/returns_fixture.dart';

/// Live desktop sidebar width from [DesktopSidebar] (`width: 250.0`).
const kLiveSidebarWidth = 250.0;
const kLiveWindowWidth = 1280.0;

Future<List<FlutterErrorDetails>> _pump(
  WidgetTester tester,
  double width, {
  Widget? page,
  double? momChangePct = 8.5,
  bool withSidebar = false,
  ReturnsFakeRepo? repository,
}) async {
  tester.view.physicalSize = Size(width, 3200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  AvailableYears.setForTest(
      const YearOptions(years: [2026], defaultYear: 2026));
  final errors = <FlutterErrorDetails>[];
  final old = FlutterError.onError;
  FlutterError.onError = (d) {
    if (d.exceptionAsString().contains('overflowed')) errors.add(d);
  };
  addTearDown(() => FlutterError.onError = old);
  final body = page ??
      SellInReturnsScreen(
        apiClient: ApiClient(),
        repository: repository ?? ReturnsFakeRepo(momChangePct: momChangePct),
      );
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
        body: withSidebar
            ? Row(
                textDirection: TextDirection.rtl,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(
                    width: kLiveSidebarWidth,
                    child: ColoredBox(color: Color(0xFF1A1C19)),
                  ),
                  Expanded(child: body),
                ],
              )
            : body,
      ),
    ),
  ));
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  FlutterError.onError = old;
  return errors;
}

class _KpiMetrics {
  _KpiMetrics(this.size, this.padding, this.iconSize, this.fonts, this.weights);
  final Size size;
  final EdgeInsetsGeometry? padding;
  final double? iconSize;
  final List<double?> fonts;
  final List<FontWeight?> weights;
  @override
  String toString() =>
      'size=$size padding=$padding icon=$iconSize fonts=$fonts weights=$weights';
}

_KpiMetrics _kpi(WidgetTester tester, Finder card) {
  final texts = find.descendant(of: card, matching: find.byType(Text));
  final styles = [
    for (final e in texts.evaluate())
      (find
              .descendant(
                  of: find.byWidget(e.widget), matching: find.byType(RichText))
              .evaluate()
              .first
              .widget as RichText)
          .text
          .style,
  ];
  return _KpiMetrics(
    tester.getSize(card),
    tester
        .widget<Container>(
            find.descendant(of: card, matching: find.byType(Container)).first)
        .padding,
    tester
        .widget<Icon>(
            find.descendant(of: card, matching: find.byType(Icon)).first)
        .size,
    [for (final st in styles) st?.fontSize],
    [for (final st in styles) st?.fontWeight],
  );
}

String _branchKey(String name) => 'qa-$name';

void main() {
  GoogleFonts.config.allowRuntimeFetching = false;
  setUpAll(loadRealCairoFont);
  setUp(AppCache.clear);

  for (final width in const [1280.0, 1024.0]) {
    group('returns @$width', () {
      testWidgets('matrix rows share one height model and hide scroll buttons',
          (tester) async {
        final errors = await _pump(tester, width);
        expect(errors, isEmpty,
            reason: errors.map((e) => e.exceptionAsString()).join('\n'));
        expect(find.byType(ReturnsHeatmapMatrix), findsOneWidget);

        // No needless scroll-hint buttons in the matrix header.
        expect(
          find.descendant(
            of: find.byType(ReturnsHeatmapMatrix),
            matching: find.text('يمين'),
          ),
          findsNothing,
        );
        expect(find.text('اسحب أو تحرك:'), findsNothing);

        final headerB =
            tester.getRect(find.byKey(ReturnsHeatmapMatrix.branchHeaderKey));
        final headerM =
            tester.getRect(find.byKey(ReturnsHeatmapMatrix.headerRowKey));
        final headerT =
            tester.getRect(find.byKey(ReturnsHeatmapMatrix.totalHeaderKey));
        expect(headerB.top, closeTo(headerM.top, 0.5));
        expect(headerT.top, closeTo(headerM.top, 0.5));
        expect(headerB.height, closeTo(headerM.height, 0.5));
        expect(headerT.height, closeTo(headerM.height, 0.5));

        for (final name in kReturnsFixtureBranches) {
          final key = _branchKey(name);
          final b = tester
              .getRect(find.byKey(ReturnsHeatmapMatrix.branchCellKey(key)));
          final m = tester
              .getRect(find.byKey(ReturnsHeatmapMatrix.monthsRowKey(key)));
          final t = tester
              .getRect(find.byKey(ReturnsHeatmapMatrix.totalCellKey(key)));
          final why = name;
          expect(b.top, closeTo(m.top, 0.5), reason: why);
          expect(t.top, closeTo(m.top, 0.5), reason: why);
          expect(b.height, closeTo(m.height, 0.5), reason: why);
          expect(t.height, closeTo(m.height, 0.5), reason: why);
          expect(b.bottom, closeTo(m.bottom, 0.5), reason: why);
          expect(t.bottom, closeTo(m.bottom, 0.5), reason: why);
        }
      });

      testWidgets('shared branch prefix is stripped in the matrix and filters',
          (tester) async {
        await _pump(tester, width);
        expect(find.text('مخزن ألفا'), findsWidgets);
        expect(find.text('فرع بيتا'), findsWidgets);
        expect(find.text('المستودع المركزي'), findsWidgets);
        expect(
          find.text('فرع النيل الجديد ذو الاسم الطويل للتحقق من اللف'),
          findsWidgets,
        );
        // Original prefixed labels are display-stripped (data itself is unchanged).
        expect(find.text(kReturnsFixtureBranches[0]), findsNothing);
        expect(find.textContaining(kReturnsFixturePrefix.trim()), findsNothing);

        final long =
            find.text('فرع النيل الجديد ذو الاسم الطويل للتحقق من اللف');
        for (final e in long.evaluate()) {
          if (e.widget is! Text) continue;
          final text = e.widget as Text;
          expect(text.maxLines == null || text.maxLines! >= 3, isTrue);
          final ro = e.renderObject;
          if (ro is RenderParagraph) {
            expect(ro.didExceedMaxLines, isFalse);
          }
        }
      });

      testWidgets('KPI titles never clipped; counted nouns; — without MoM',
          (tester) async {
        await _pump(tester, width, momChangePct: null);
        expect(find.textContaining('4 فروع'), findsWidgets);
        final titles = find.byWidgetPredicate((w) =>
            w.key is ValueKey<String> &&
            (w.key as ValueKey<String>).value.startsWith('returns_kpi_title_'));
        expect(titles, findsNWidgets(4));
        for (final e in titles.evaluate()) {
          expect(
            (e.renderObject! as RenderParagraph).didExceedMaxLines,
            isFalse,
            reason: '${e.widget.key}',
          );
        }
        expect(find.text('—'), findsWidgets);
        expect(find.text('لا توجد بيانات للمقارنة'), findsWidgets);
      });

      testWidgets('export button is a 40dp stadium control', (tester) async {
        await _pump(tester, width);
        final label = find.text('تصدير Excel');
        expect(label, findsOneWidget);
        final button = find.ancestor(
          of: label,
          matching: find.byType(OutlinedButton),
        );
        expect(button, findsOneWidget);
        final material =
            find.descendant(of: button, matching: find.byType(Material)).first;
        expect(tester.getSize(material).height,
            closeTo(M3ToolbarButton.height, 0.5));
        expect(tester.widget<Material>(material).shape, isA<StadiumBorder>());
      });
    });
  }

  for (final width in const [1280.0, 1024.0]) {
    testWidgets('KPI cards match the Sell-Out reference @$width',
        (tester) async {
      await _pump(
        tester,
        width,
        page: SellOutExplorerScreen(apiClient: ApiClient()),
      );
      final ref = _kpi(
        tester,
        find.byKey(const ValueKey('kpi_card_Net Sales (EGP)')),
      );
      await _pump(tester, width);
      final cards = find.byWidgetPredicate((w) =>
          w is M3SummaryKpiCard &&
          w.key is ValueKey<String> &&
          (w.key as ValueKey<String>).value.startsWith('returns_kpi_card_'));
      expect(cards, findsNWidgets(4));
      for (final e in cards.evaluate()) {
        final m = _kpi(tester, find.byWidget(e.widget));
        final why = 'returns ${e.widget.key}: $m\nsell-out: $ref';
        expect(m.padding, ref.padding, reason: why);
        expect(m.iconSize, ref.iconSize, reason: why);
        expect(m.iconSize, M3SummaryKpiStyle.iconSize, reason: why);
        expect(m.padding, M3SummaryKpiStyle.padding, reason: why);
        expect(m.fonts, ref.fonts, reason: why);
        expect(m.weights, ref.weights, reason: why);
        expect(m.size.width, closeTo(ref.size.width, 0.5), reason: why);
        // At 1024 a longer Arabic title or subtitle can wrap; the equal-height
        // grid then raises every card. Padding, type and icons still match.
        if (width >= 1280) {
          expect(m.size.height, closeTo(ref.size.height, 0.5), reason: why);
        } else {
          expect(m.size.height, greaterThanOrEqualTo(ref.size.height),
              reason: why);
        }
      }
    });
  }

  group('live 1280 shell (250dp sidebar, Cairo, live-scale values)', () {
    final liveRepo = ReturnsFakeRepo(
      momChangePct: -17.9,
      branchNames: kReturnsLiveVariantBranches,
      kpiValueEgp: 3.19e6,
      kpiQty: 23900,
      kpiReturnPct: 2.3,
    );

    testWidgets('strips typo-variant prefixes and fits the matrix',
        (tester) async {
      final errors = await _pump(
        tester,
        kLiveWindowWidth,
        withSidebar: true,
        repository: liveRepo,
      );
      expect(errors, isEmpty);

      expect(find.text('مخزن ألفا'), findsWidgets);
      expect(find.text('فرع بيتا'), findsWidgets);
      expect(find.text('المستودع المركزي'), findsWidgets);
      expect(find.text('فرع منفصل بدون بادئة'), findsWidgets);
      expect(find.textContaining('سلسله تجريبيه'), findsNothing);
      expect(find.textContaining('سلسلة تجريبية'), findsNothing);

      final matrix = find.byType(ReturnsHeatmapMatrix);
      expect(matrix, findsOneWidget);
      final octFinder =
          find.descendant(of: matrix, matching: find.text('أكتوبر'));
      final totalFinder =
          find.descendant(of: matrix, matching: find.text('الإجمالي'));
      expect(octFinder, findsWidgets);
      expect(totalFinder, findsWidgets);
      final oct = tester.getRect(octFinder.first);
      // The matrix also labels the totals *row* "الإجمالي". Use the header
      // that shares a row with October, which is the pinned total column.
      Rect? total;
      for (final e in totalFinder.evaluate()) {
        final r = tester.getRect(find.byWidget(e.widget));
        if ((r.center.dy - oct.center.dy).abs() <= 24) {
          total = r;
          break;
        }
      }
      expect(total, isNotNull,
          reason: 'no الإجمالي header aligned with October ($oct)');
      expect(oct.left, greaterThanOrEqualTo(-0.5),
          reason: 'October left=$oct total=$total');
      expect(oct.right, lessThanOrEqualTo(kLiveWindowWidth + 0.5),
          reason: 'October clipped past the window: $oct');
      expect(oct.left, greaterThanOrEqualTo(total!.right - 1.0),
          reason: 'October is behind the pinned total: oct=$oct total=$total');
      final hScroll = find.descendant(
        of: matrix,
        matching: find.byWidgetPredicate((w) =>
            w is Scrollable &&
            (w.axisDirection == AxisDirection.left ||
                w.axisDirection == AxisDirection.right)),
      );
      expect(hScroll, findsWidgets);
      final extent =
          tester.state<ScrollableState>(hScroll.first).position.maxScrollExtent;
      expect(extent, lessThanOrEqualTo(2.0),
          reason: 'matrix still scrolls horizontally (extent=$extent)');
    });

    testWidgets('KPI height matches Sell-Out in the live shell',
        (tester) async {
      await _pump(
        tester,
        kLiveWindowWidth,
        withSidebar: true,
        page: SellOutExplorerScreen(apiClient: ApiClient()),
      );
      final ref = _kpi(
        tester,
        find.byKey(const ValueKey('kpi_card_Net Sales (EGP)')),
      );
      await _pump(
        tester,
        kLiveWindowWidth,
        withSidebar: true,
        repository: liveRepo,
      );
      final cards = find.byWidgetPredicate((w) =>
          w is M3SummaryKpiCard &&
          w.key is ValueKey<String> &&
          (w.key as ValueKey<String>).value.startsWith('returns_kpi_card_'));
      expect(cards, findsNWidgets(4));
      expect(find.text('نسبة المرتجع'), findsWidgets);
      expect(find.text('نسبة المرتجع من الإجمالي'), findsNothing);
      for (final e in cards.evaluate()) {
        final m = _kpi(tester, find.byWidget(e.widget));
        final why = 'live-shell returns ${e.widget.key}: $m\nsell-out: $ref';
        expect(m.padding, ref.padding, reason: why);
        expect(m.iconSize, ref.iconSize, reason: why);
        expect(m.fonts, ref.fonts, reason: why);
        expect(m.weights, ref.weights, reason: why);
        expect(m.size.width, closeTo(ref.size.width, 0.5), reason: why);
        expect(m.size.height, closeTo(ref.size.height, 0.5), reason: why);
        expect(m.size.height, closeTo(138.0, 1.0), reason: why);
      }
    });
  });
}
