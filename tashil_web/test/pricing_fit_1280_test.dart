// v135 live-test follow-up: table fits at 1280, category chips wrap,
// Product Master dialog KPI titles are not ellipsized.
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tashil_web/core/storage/session_storage.dart';
import 'package:tashil_web/core/data/app_cache.dart';
import 'package:tashil_web/core/network/api_client.dart';
import 'package:tashil_web/core/utils/currency_formatter.dart';
import 'package:tashil_web/core/widgets/m3_chip_surface.dart';
import 'package:tashil_web/features/pricing_compliance/presentation/screens/pricing_compliance_screen.dart';
import 'package:tashil_web/features/product_master/presentation/screens/product_master_screen.dart';

import 'pricing_m3_support.dart';

class _FitApiClient extends PricingShotApiClient {
  @override
  Future<ProductMasterSummaryModel> getProductMaster({
    String? search,
    String? brand,
    String? category,
    String? prefix,
    String? itemType,
    String? packaging,
    String? pullStatus,
    String? priceChange,
  }) async {
    return const ProductMasterSummaryModel(
      tenantId: 'tenant-adeco',
      companyName: 'شركة الإسكندرية للمنظفات والكيماويات (ادكو - Adeco)',
      sheetDateLabel: 'تحديث 01-08-2026',
      sourceFilename: 'adeco_product_master_2026_08_01.xlsx',
      totalSkus: 389,
      regularSkusCount: 280,
      promoSkusCount: 109,
      uniqueBarcodesCount: 363,
      avgUnitsPerCarton: 10.3,
      activeInChainsCount: 327,
      unpulledSkusCount: 62,
      items: [],
    );
  }

  @override
  Future<UploadedFilesArchiveResponse> getUploadedFilesArchive({
    String? chain,
    String? year,
    String? searchQuery,
    String? targetTenant,
    String? fileType,
    bool forceRefresh = false,
  }) async {
    return const UploadedFilesArchiveResponse(
      tenantId: 'tenant-adeco',
      totalCount: 0,
      chainCounts: {},
      files: [],
    );
  }
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

List<String> _ellipsizedBefore(WidgetTester tester, Finder scope, int lines) {
  final out = <String>[];
  for (final e
      in find.descendant(of: scope, matching: find.byType(Text)).evaluate()) {
    final t = e.widget as Text;
    if (t.data == null || t.data!.isEmpty) continue;
    final p = tester
        .renderObject<RenderParagraph>(find.byElementPredicate((x) => x == e));
    if (p.didExceedMaxLines && (t.maxLines ?? 99) < lines) {
      out.add('"${t.data}" cut at maxLines ${t.maxLines}');
    }
  }
  return out;
}

void main() {
  ignoreGoogleFontLoadErrors();
  setUpAll(loadPricingFonts);
  setUp(AppCache.clear);

  testWidgets(
      'Pricing table fits 1280 with no horizontal scroll; name and status visible together',
      (tester) async {
    final api = _FitApiClient();
    await pumpPricing(
      tester,
      PricingComplianceScreen(apiClient: api),
      width: 1280,
      height: 2400,
    );

    final table = find.byKey(const ValueKey('pricing_compliance_table'));
    expect(table, findsOneWidget);
    final scroller = find.byKey(const ValueKey('pricing_table_scroll'));
    expect(scroller, findsOneWidget);
    expect(_hScrollExtent(tester, scroller), lessThanOrEqualTo(2.0));

    expect(find.byKey(const ValueKey('pricing_sku_name')), findsWidgets);
    expect(_onScreen(tester, find.byKey(const ValueKey('pricing_sku_name'))),
        isTrue);
    // Status short labels from the fixture (under_cutting / no promo).
    expect(find.text('حرق سعر'), findsWidgets);
    expect(_onScreen(tester, find.text('حرق سعر')), isTrue);
    expect(find.text('بدون عرض'), findsWidgets);
    expect(_onScreen(tester, find.text('بدون عرض')), isTrue);
    // Short chip + description (M3ChipSurface), not a full sentence inside the chip.
    expect(find.byType(M3ChipSurface), findsWidgets);
    expect(find.textContaining('عن السعر الموصى به'), findsWidgets);
  });

  testWidgets('Long Active Promos category names wrap instead of ellipsizing',
      (tester) async {
    await pumpPricing(
      tester,
      PricingComplianceScreen(apiClient: _FitApiClient()),
      width: 1280,
      height: 2400,
    );
    await tester.tap(find.text('عروض نشطة'));
    await tester.pumpAndSettle();

    for (final name in [
      'منظفات سجاد ومفروشات',
      'مسحوق غسالات اطباق',
      kLongCategory,
    ]) {
      final chip = find.widgetWithText(FilterChip, name);
      expect(chip, findsOneWidget, reason: name);
      expect(_onScreen(tester, chip), isTrue, reason: name);
      final texts = find.descendant(of: chip, matching: find.byType(Text));
      for (final t in tester.widgetList<Text>(texts)) {
        expect(t.maxLines, greaterThanOrEqualTo(3), reason: name);
        expect(t.overflow, isNot(TextOverflow.ellipsis), reason: name);
        expect(t.overflow, isNot(TextOverflow.fade), reason: name);
      }
      expect(_ellipsizedBefore(tester, chip, 3), isEmpty, reason: name);
    }
  });

  testWidgets(
      'Product Master opened from Pricing shows title + tabs (no KPI grid) and leaves the page URL alone',
      (tester) async {
    SessionStorage.replaceBrowserQueryParam('tab', null);
    final api = _FitApiClient();
    await pumpPricing(
      tester,
      PricingComplianceScreen(apiClient: api),
      width: 1280,
      height: 2400,
    );
    final open = find.text('كارتة الأصناف والأسعار');
    expect(open, findsOneWidget);
    await tester.ensureVisible(open);
    await tester.pumpAndSettle();
    await tester.tap(open);
    await tester.pumpAndSettle();

    expect(find.byType(ProductMasterScreen), findsOneWidget);
    expect(find.byKey(const ValueKey('product_master_kpi_grid')), findsNothing);
    final tabs = find.byKey(const ValueKey('product_master_tabs'));
    expect(tabs, findsOneWidget);
    expect(_onScreen(tester, tabs), isTrue);
    await tester.tap(find.byKey(const ValueKey('pm_tab_sheets')));
    await tester.pumpAndSettle();
    expect(SessionStorage.browserQueryParam('tab'), isNull,
        reason: 'the embedded dialog must not write ?tab= into the Pricing URL');
  });

  testWidgets('هامش السلسلة uses formatSignedPct so the minus stays on the left',
      (tester) async {
    await pumpPricing(
      tester,
      PricingComplianceScreen(apiClient: _FitApiClient()),
      width: 1280,
      height: 2400,
    );
    final expected =
        'هامش السلسلة: ${CurrencyFormatter.formatSignedPct(-5.0)}';
    final label = find.text(expected);
    expect(label, findsOneWidget);
    await tester.ensureVisible(label);
    await tester.pumpAndSettle();
    expect(find.text('هامش السلسلة: -5.0%'), findsNothing);
    expect(find.textContaining('%5.0-'), findsNothing);

    final para = tester.renderObject<RenderParagraph>(label);
    final text = expected;
    final minusIdx = text.indexOf('\u2212');
    final digitIdx = text.indexOf(RegExp(r'\d'));
    expect(minusIdx, greaterThanOrEqualTo(0));
    final minusBoxes = para.getBoxesForSelection(
      TextSelection(baseOffset: minusIdx, extentOffset: minusIdx + 1),
    );
    final digitBoxes = para.getBoxesForSelection(
      TextSelection(baseOffset: digitIdx, extentOffset: digitIdx + 1),
    );
    expect(minusBoxes, isNotEmpty);
    expect(digitBoxes, isNotEmpty);
    expect(
      minusBoxes.first.toRect().left,
      lessThan(digitBoxes.first.toRect().left),
    );
  });
}
