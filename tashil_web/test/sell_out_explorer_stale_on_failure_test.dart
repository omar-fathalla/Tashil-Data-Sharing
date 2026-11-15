import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tashil_web/core/data/result.dart';
import 'package:tashil_web/core/utils/currency_formatter.dart';
import 'package:tashil_web/core/network/api_client.dart';
import 'package:tashil_web/core/theme/app_theme.dart';
import 'package:tashil_web/features/sell_out_analytics/data/sell_out_explorer_repository.dart';
import 'package:tashil_web/features/sell_out_analytics/presentation/screens/sell_out_explorer_screen.dart';
import 'package:tashil_web/features/sell_out_analytics/presentation/widgets/cascading_filter_toolbar.dart';

/// Scripted repo so the screen can succeed once, then fail on the next filter reload.
class _ScriptedSellOutRepo extends SellOutExplorerRepository {
  _ScriptedSellOutRepo(this._responses)
      : super(ApiClient(tenantId: 'tenant-adeco', allowMockFallback: false));

  final List<Result<SellOutExplorerData>> _responses;
  int calls = 0;

  @override
  Future<Result<SellOutExplorerData>> load(SellOutExplorerQuery q, {bool forceRefresh = false}) async {
    final i = calls++;
    if (i >= _responses.length) {
      return const Failure(AppError.unknown('unexpected extra load'));
    }
    return _responses[i];
  }
}

SellOutExplorerData _sampleData({required double factoryCost, required double margin}) {
  return SellOutExplorerData(
    records: [
      SellOutRecordModel(
        recordId: 'r1',
        retailerChain: 'fathalla',
        storeId: 's1',
        storeName: 'فرع 1',
        barcode: '622',
        skuName: 'Rahab Dish',
        category: 'صابون سائل اطباق',
        quantitySold: 12,
        netRevenue: 100,
        unitPrice: 8,
        transactionDate: '2026-01-15',
        cartonsSold: 1,
        totalFactoryCost: factoryCost,
        retailerGrossProfit: margin,
      ),
    ],
    summary: SellOutRecordsSummaryModel(
      totalCount: 28,
      totalNetRevenue: 320861,
      totalUnitsSold: 6887,
      totalCartonsSold: 688.7,
      totalFactoryCost: factoryCost,
      totalRetailerGrossProfit: margin,
      avgRetailerMarginPct: -46.1,
      activeStoresCount: 12,
      activeSkusCount: 28,
      matchedSkusCount: 28,
      skuSummaries: [
        SellOutSkuSummaryModel(
          itemCode: 'RH-1',
          skuName: 'Rahab Dish',
          category: 'صابون سائل اطباق',
          totalFactoryCost: factoryCost,
          retailerGrossProfit: margin,
          retailerMarginPct: -46.1,
          activeStoresCount: 3,
        ),
      ],
    ),
    stores: const [],
    currentBranchMatrix: const [],
    prevBranchMatrix: const [],
    yoyCurrentBranchMatrix: const [],
  );
}

void main() {
  testWidgets('failed Sell-Out reload clears previous prices/margin table', (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final repo = _ScriptedSellOutRepo([
      Success(_sampleData(factoryCost: 595500, margin: -274639)),
      Failure(AppError.fromStatus(429, 'HTTP 429: rate limited')),
    ]);

    await http.runWithClient(() async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: SellOutExplorerScreen(
              apiClient: ApiClient(tenantId: 'tenant-adeco', allowMockFallback: false),
              repository: repo,
            ),
          ),
        ),
      );
      // First load settles (scripted success); a few pumps cover post-frame snackbar clears.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pumpAndSettle(const Duration(seconds: 1));

      expect(find.textContaining('الأسعار وهامش السلسلة'), findsOneWidget);
      expect(find.textContaining('خسارة 274.6${CurrencyFormatter.scaleJoiner}K'), findsWidgets);
      expect(find.textContaining('595.5${CurrencyFormatter.scaleJoiner}K'), findsWidgets);

      final toolbar = tester.widget<CascadingFilterToolbar>(find.byType(CascadingFilterToolbar));
      toolbar.onCategoryChanged('صابون سائل اطباق');
      await tester.pump(); // start load: table cleared immediately
      expect(find.textContaining('595.5${CurrencyFormatter.scaleJoiner}K'), findsNothing);
      expect(find.textContaining('خسارة 274.6${CurrencyFormatter.scaleJoiner}K'), findsNothing);

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pumpAndSettle(const Duration(seconds: 1));

      expect(repo.calls, 2);
      expect(find.byKey(const ValueKey('sell_out_error_state')), findsOneWidget);
      expect(find.textContaining('595.5${CurrencyFormatter.scaleJoiner}K'), findsNothing);
      expect(find.textContaining('خسارة 274.6${CurrencyFormatter.scaleJoiner}K'), findsNothing);
      expect(find.text('إعادة المحاولة'), findsOneWidget);
    }, () => MockClient((req) async {
          final body = req.url.path.contains('archive') || req.url.path.contains('upload')
              ? <Object>[]
              : {'records': [], 'total_count': 0};
          return http.Response.bytes(
            utf8.encode(jsonEncode(body)),
            200,
            headers: {'content-type': 'application/json'},
          );
        }));
  });
}
