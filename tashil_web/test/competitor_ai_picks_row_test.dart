import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tashil_web/core/network/api_client.dart';
import 'package:tashil_web/core/testing/test_semantics.dart';
import 'package:tashil_web/features/competitor_comparison/presentation/widgets/competitor_ai_picks_row.dart';
import 'package:tashil_web/features/competitor_comparison/presentation/widgets/competitor_suggestions_review.dart';

import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

CompetitorSkuComparisonModel _pick({
  required String barcode,
  required String brand,
  required String name,
  required String size,
  required double price,
}) {
  return CompetitorSkuComparisonModel(
    skuName: name,
    barcode: barcode,
    supplierName: 'Supplier',
    brand: brand,
    category: 'صابون سائل اطباق',
    packSizeLabel: size,
    packVolumeUnits: 3,
    volumeUnitLabel: 'كجم',
    unitPrice: price,
    pricePerUnitVolume: price / 3,
    priceDiffEgp: price - 180,
    priceDiffPct: ((price - 180) / 180) * 100,
    pricePosition: price > 180 ? 'higher' : 'lower',
    unitsSold: 5,
    netRevenue: price * 5,
    categorySharePct: 10,
    isPinnedDirect: false,
  );
}

void main() {
  testWidgets('AI picks row shows اختيار AI badge and selects on tap',
      (tester) async {
    CompetitorSkuComparisonModel? selected;
    final picks = [
      _pick(
        barcode: 'C1',
        brand: 'Pril',
        name: 'بريل 4 كجم',
        size: '4 كجم',
        price: 150,
      ),
      _pick(
        barcode: 'C2',
        brand: 'Fairy',
        name: 'فييري 2 لتر',
        size: '2 لتر',
        price: 160,
      ),
      _pick(
        barcode: 'C3',
        brand: 'Wafeer',
        name: 'وفير 3 كجم',
        size: '3 كجم',
        price: 170,
      ),
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CompetitorAiPicksRow(
            loading: false,
            picks: picks,
            selectedBarcode: selected?.barcode,
            onSelect: (c) => selected = c,
          ),
        ),
      ),
    );

    expect(find.text('اقتراحات الذكاء الاصطناعي (أعلى 3)'), findsOneWidget);
    expect(find.text('اختيار AI'), findsNWidgets(3));
    expect(find.text('بريل 4 كجم'), findsOneWidget);
    expect(find.text('Pril'), findsOneWidget);
    expect(find.textContaining('150.0'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('ai-pick-C1')));
    await tester.pump();
    expect(selected?.barcode, 'C1');
  });

  testWidgets('AI picks row shows loading skeleton', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: CompetitorAiPicksRow(
            loading: true,
            picks: [],
            onSelect: _noop,
          ),
        ),
      ),
    );
    expect(find.text('اختيار AI'), findsNothing);
    expect(find.byType(CompetitorAiPicksRow), findsOneWidget);
  });

  testWidgets('batch run surfaces backend error via snackbar', (tester) async {
    MockClient fake() => MockClient((req) async {
          if (req.url.path.contains('/competitors/suggestions/run') &&
              req.method == 'POST') {
            return http.Response.bytes(
              utf8.encode(jsonEncode({'error': 'كتالوج المنافسة غير متاح حالياً'})),
              503,
              headers: {'content-type': 'application/json'},
            );
          }
          if (req.url.path.contains('/competitors/suggestions') &&
              req.method == 'GET') {
            return http.Response.bytes(
              utf8.encode(jsonEncode({'suggestions': [], 'count': 0})),
              200,
              headers: {'content-type': 'application/json'},
            );
          }
          return http.Response('{"error":"unhandled"}', 500);
        });

    await http.runWithClient(() async {
      final api = ApiClient(tenantId: 'tenant-adeco', allowMockFallback: false);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: CompetitorSuggestionsReview(
                apiClient: api,
                chain: 'fathalla',
                year: 2026,
                isOwner: true,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.textContaining('تشغيل دفعة'));
      await tester.pumpAndSettle();

      expect(find.textContaining('كتالوج المنافسة غير متاح حالياً'), findsWidgets);
      // M3Feedback error snackbar uses TestIds.snackbarError as semantics identifier.
      expect(
        tester.getSemantics(find.textContaining('كتالوج المنافسة غير متاح حالياً').first),
        isNotNull,
      );
      expect(TestIds.snackbarError, 'snackbar-error');
    }, fake);
  });

  test('KPI averages flag stays OFF by default', () {
    expect(ApiClient.includeAiSuggestionsInKpiAverages, isFalse);
  });
}

void _noop(CompetitorSkuComparisonModel _) {}
