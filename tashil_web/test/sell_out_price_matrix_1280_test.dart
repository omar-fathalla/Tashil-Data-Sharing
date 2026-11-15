// Live 1280 + 250dp DesktopSidebar harness for the Sell-Out
// «الأسعار وهامش السلسلة» table. Owner rule: the table fills the width,
// no horizontal scroll, centred columns except the name, values wrap ≤3.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tashil_web/core/data/app_cache.dart';
import 'package:tashil_web/core/data/result.dart';
import 'package:tashil_web/core/network/api_client.dart';
import 'package:tashil_web/core/theme/app_theme.dart';
import 'package:tashil_web/core/utils/currency_formatter.dart';
import 'package:tashil_web/features/navigation/presentation/desktop_sidebar.dart';
import 'package:tashil_web/features/sell_out_analytics/data/sell_out_explorer_repository.dart';
import 'package:tashil_web/core/widgets/atomic_numeric_text.dart';
import 'package:tashil_web/core/widgets/hyphenated_code_text.dart';
import 'package:tashil_web/features/sell_out_analytics/presentation/screens/sell_out_explorer_screen.dart';

import 'support/real_fonts.dart';

const kLiveViewportWidth = 1280.0;

/// Longest live-like names seen on the price table at v160.
const kLiveLongName =
    'عرض شنطة كلوريل ( عبوة 1050 جم مبيض & عبوة 1 ك 1*2 & عبوة 1ك 1*4 & عبوة الوان 1 ك ) 3 مجموعة';
const kLiveLongName2 =
    'عرض شرك فيبا بلس + 3 كجم & فيبا 3 كجم - 3 مجموعه';

SellOutExplorerData _livePriceData() => const SellOutExplorerData(
      records: [],
      summary: SellOutRecordsSummaryModel(
        totalCount: 3,
        totalNetRevenue: 32740000,
        totalUnitsSold: 213622,
        totalCartonsSold: 213622,
        matchedSkusCount: 3,
        totalFactoryCost: 159690000,
        totalRetailerGrossProfit: -32740000,
        avgRetailerMarginPct: -25.8,
        skuSummaries: [
          SellOutSkuSummaryModel(
            itemCode: 'PRHC-0003-0009',
            skuName: kLiveLongName2,
            unitsPerCarton: 3,
            totalUnitsSold: 33779,
            totalCartonsSold: 11259.7,
            officialConsumerRsp: 400.98,
            avgSellingPrice: 224.59,
            priceDeltaPct: -44.0,
            factoryUnitCost: 180.25,
            netCartonInvoiceCost: 1082.66,
            totalNetRevenue: 7588000,
            retailerGrossProfit: -4600000,
            retailerMarginPct: -60.3,
          ),
          SellOutSkuSummaryModel(
            itemCode: 'PRHC-0001-0001',
            skuName: kLiveLongName,
            unitsPerCarton: 3,
            totalUnitsSold: 87233,
            totalCartonsSold: 17446.6,
            officialConsumerRsp: 152.54,
            avgSellingPrice: 105.81,
            priceDeltaPct: -30.6,
            factoryUnitCost: 90.10,
            netCartonInvoiceCost: 260.00,
            totalNetRevenue: 2508000,
            retailerGrossProfit: -640000,
            retailerMarginPct: -25.5,
          ),
          SellOutSkuSummaryModel(
            itemCode: 'FGDG-0004-0001',
            skuName: 'فيبا 4 كجم منظف متعدد الاغراض ليمون',
            unitsPerCarton: 4,
            totalUnitsSold: 39360,
            totalCartonsSold: 9840.0,
            officialConsumerRsp: 214.97,
            avgSellingPrice: 150.09,
            priceDeltaPct: -30.2,
            factoryUnitCost: 110.00,
            netCartonInvoiceCost: 420.00,
            totalNetRevenue: 5907000,
            retailerGrossProfit: -1200000,
            retailerMarginPct: -20.3,
          ),
        ],
      ),
      stores: [],
      currentBranchMatrix: [],
      prevBranchMatrix: [],
      yoyCurrentBranchMatrix: [],
    );

class _OneShotRepo extends SellOutExplorerRepository {
  _OneShotRepo(this._data)
      : super(ApiClient(tenantId: 'tenant-adeco', allowMockFallback: false));
  final SellOutExplorerData _data;

  @override
  Future<Result<SellOutExplorerData>> load(SellOutExplorerQuery q,
          {bool forceRefresh = false}) async =>
      Success(_data);
}

Future<void> _pumpLiveShell(WidgetTester tester) async {
  tester.view.physicalSize = const Size(kLiveViewportWidth, 4000);
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
      child: Row(
        children: [
          DesktopSidebar(
            selectedIndex: 1,
            onDestinationSelected: (_) {},
            activeTenant: 'adeco',
            onTenantChanged: (_) {},
          ),
          Expanded(
            child: Scaffold(
              body: SellOutExplorerScreen(
                apiClient: ApiClient(
                    tenantId: 'tenant-adeco', allowMockFallback: false),
                repository: _OneShotRepo(_livePriceData()),
              ),
            ),
          ),
        ],
      ),
    ),
  ));
  await tester.pumpAndSettle(const Duration(seconds: 2));
}

double _hScrollExtent(WidgetTester tester, Finder scope) {
  var maxExtent = 0.0;
  for (final e in find
      .descendant(of: scope, matching: find.byType(Scrollable))
      .evaluate()) {
    final state = tester.state<ScrollableState>(
        find.byElementPredicate((x) => x == e));
    if (state.position.axis == Axis.horizontal &&
        state.position.maxScrollExtent > maxExtent) {
      maxExtent = state.position.maxScrollExtent;
    }
  }
  return maxExtent;
}

bool _onScreen(WidgetTester tester, Finder f, {double width = kLiveViewportWidth}) {
  final box = tester.renderObject<RenderBox>(f);
  final topLeft = box.localToGlobal(Offset.zero);
  final rect = topLeft & box.size;
  return rect.left >= -1.0 && rect.right <= width + 1.0;
}

void main() {
  GoogleFonts.config.allowRuntimeFetching = false;
  setUpAll(loadRealCairoFont);
  setUp(AppCache.clear);

  testWidgets(
    'price matrix fits 1280+DesktopSidebar with no h-scroll and no clipped columns',
    (tester) async {
      await http.runWithClient(() async {
        await _pumpLiveShell(tester);
        expect(tester.takeException(), isNull);

        final table = find.byKey(const ValueKey('price_matrix_table'));
        expect(table, findsOneWidget);
        expect(
          _hScrollExtent(tester, table),
          lessThanOrEqualTo(2.0),
          reason: 'price matrix must not scroll horizontally at 1280+sidebar',
        );

        for (final label in [
          'كود الصنف',
          'الصنف الرسمي',
          'وحدات/كرتونة',
          'الوحدات',
          'الكراتين',
          'سعر القائمة (شامل الضريبة)',
          'سعر البيع الفعلي',
          'فرق السعر %',
          'تكلفة المصنع للقطعة',
          'صافي سعر الكرتونة (فاتورة)',
          'صافي المبيعات',
          'هامش السلسلة',
        ]) {
          final head = find.descendant(of: table, matching: find.text(label));
          expect(head, findsWidgets, reason: 'missing header $label');
          expect(_onScreen(tester, head.first), isTrue,
              reason: 'header "$label" is clipped or off-screen');
        }

        final names = find.byKey(const ValueKey('price_matrix_sku_name'));
        expect(names, findsNWidgets(3));
        for (final t in tester.widgetList<Text>(names)) {
          expect(t.maxLines, 3);
          expect(t.overflow, TextOverflow.ellipsis);
        }
        for (final e in names.evaluate()) {
          final p = tester.renderObject<RenderParagraph>(
              find.byElementPredicate((x) => x == e));
          expect(p.didExceedMaxLines, isFalse,
              reason: 'name "${(e.widget as Text).data}" clipped before 3 lines');
        }

        // Live negative deltas keep the minus on the left.
        final delta = find.byKey(const ValueKey('price_matrix_delta_pct'));
        expect(delta, findsWidgets);
        final deltaTexts = tester
            .widgetList<AtomicNumericText>(delta)
            .map((t) => t.text)
            .toList();
        expect(deltaTexts, contains(CurrencyFormatter.formatSignedPct(-44.0)));
        expect(deltaTexts.any((t) => t.contains('-')), isFalse);

        final dt = tester.widget<DataTable>(
            find.descendant(of: table, matching: find.byType(DataTable)));
        String? colLabel(DataColumn c) {
          Widget w = c.label;
          while (true) {
            if (w is Text) return w.data;
            if (w is ConstrainedBox && w.child != null) {
              w = w.child!;
              continue;
            }
            if (w is Align && w.child != null) {
              w = w.child!;
              continue;
            }
            return null;
          }
        }

        for (final c in dt.columns) {
          final label = colLabel(c);
          expect(
            c.headingRowAlignment,
            label == 'الصنف الرسمي'
                ? isNot(MainAxisAlignment.center)
                : MainAxisAlignment.center,
            reason: label,
          );
        }

        expect(find.byType(HyphenatedCodeText), findsWidgets);
        for (final code in ['PRHC-0003-0009', 'PRHC-0001-0001', 'FGDG-0004-0001']) {
          final f = find.descendant(of: table, matching: find.text(code));
          expect(f, findsOneWidget, reason: 'code $code must stay on one line');
          expect(_onScreen(tester, f), isTrue, reason: 'code $code off-screen');
          final para = tester.renderObject<RenderParagraph>(f);
          expect(para.didExceedMaxLines, isFalse, reason: code);
          expect(
            para.size.height,
            lessThanOrEqualTo(22.0),
            reason: 'code $code wrapped to more than one line (h=${para.size.height})',
          );
        }

        final marginText = CurrencyFormatter.formatMarginSummary(-4600000, -60.3);
        expect(marginText, contains('60.3%'));
        final margin = find.descendant(of: table, matching: find.text(marginText));
        expect(margin, findsOneWidget, reason: 'full margin "$marginText"');
        expect(_onScreen(tester, margin), isTrue);
        final marginPara = tester.renderObject<RenderParagraph>(margin);
        expect(
          marginPara.didExceedMaxLines,
          isFalse,
          reason: 'هامش السلسلة ellipsized: $marginText',
        );

        // Numbers must never wrap internally (11259.7, 17446.6, 1082.66).
        for (final number in ['11259.7', '17446.6', '1082.66', '87,233']) {
          final f = find.descendant(of: table, matching: find.textContaining(number));
          expect(f, findsWidgets, reason: 'missing $number');
          for (final e in f.evaluate()) {
            final data = (e.widget as Text).data ?? '';
            if (!data.contains(number)) continue;
            final para = tester.renderObject<RenderParagraph>(
                find.byElementPredicate((x) => x == e));
            final start = data.indexOf(number);
            final boxes = para.getBoxesForSelection(
              TextSelection(baseOffset: start, extentOffset: start + number.length),
            );
            expect(boxes, isNotEmpty, reason: '$number not painted');
            final tops = {for (final b in boxes) b.toRect().top.round()};
            expect(tops, hasLength(1),
                reason: '$number broke mid-number across lines in "$data"');
          }
        }
        expect(find.text('11259.'), findsNothing);
        expect(find.text('17446.'), findsNothing);
        expect(find.text('1082.6'), findsNothing);
      },
          () => MockClient((req) async => http.Response.bytes(
                utf8.encode(jsonEncode(req.url.path.contains('archive') ||
                        req.url.path.contains('upload')
                    ? <Object>[]
                    : {'records': [], 'total_count': 0})),
                200,
                headers: {'content-type': 'application/json'},
              )));
    },
  );
}
