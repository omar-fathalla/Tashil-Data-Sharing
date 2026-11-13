import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tashil_web/core/network/api_client.dart';
import 'package:tashil_web/features/competitor_comparison/presentation/widgets/competitor_suggestions_review.dart';

CompetitorSuggestionModel _sug({
  required String id,
  required String own,
  required String ownName,
  required String comp,
  required String compName,
  required int rank,
  double confidence = 0.8,
}) {
  return CompetitorSuggestionModel(
    id: id,
    ownBarcode: own,
    ownSkuName: ownName,
    ownCategory: 'صابون سائل اطباق',
    competitorBarcode: comp,
    competitorSkuName: compName,
    competitorBrand: 'Brand',
    competitorSupplier: 'Supplier',
    category: 'صابون سائل اطباق',
    retailerChain: 'fathalla',
    reasonAr: 'نفس الفئة',
    confidence: confidence,
    rank: rank,
    status: 'pending',
    ownUnitPrice: 180,
    competitorUnitPrice: 150,
    ownUnits: 10,
    competitorUnits: 8,
    sizeLabelCompetitor: '3 كجم',
  );
}

void main() {
  test('groupPendingSuggestionsByOwnSku collapses pairs into one card per own SKU', () {
    final groups = groupPendingSuggestionsByOwnSku([
      _sug(id: 'a1', own: 'OWN1', ownName: 'فيبا 3ك', comp: 'C1', compName: 'بريل', rank: 2),
      _sug(id: 'a2', own: 'OWN1', ownName: 'فيبا 3ك', comp: 'C2', compName: 'فيري', rank: 1),
      _sug(id: 'b1', own: 'OWN2', ownName: 'فلفيتا', comp: 'C3', compName: 'أريال', rank: 1),
    ]);
    expect(groups, hasLength(2));
    expect(groups[0].ownBarcode, 'OWN1');
    expect(groups[0].suggestions.map((s) => s.id).toList(), ['a2', 'a1']);
    expect(groups[1].ownBarcode, 'OWN2');
    expect(groups[1].suggestions, hasLength(1));
  });

  testWidgets(
      'pending tab paginates many own-SKU groups (25+) without batch-size cap',
      (tester) async {
    // Regression for live gap: with only 2 groups, pager was unverifiable.
    // Keep a 25-group fixture so page 2 (OWN20+) is asserted.
    final store = <Map<String, dynamic>>[
      for (var i = 0; i < 25; i++) ...[
        {
          'id': 'csug_${i}_1',
          'own_barcode': 'OWN$i',
          'own_sku_name': 'صنف $i',
          'own_category': 'صابون سائل اطباق',
          'competitor_barcode': 'COMP${i}A',
          'competitor_sku_name': 'منافس $i-أ',
          'competitor_brand': 'Brand',
          'competitor_supplier': 'هنكل',
          'category': 'صابون سائل اطباق',
          'retailer_chain': 'fathalla',
          'reason_ar': 'نفس الفئة',
          'confidence': 0.8,
          'rank': 1,
          'status': 'pending',
          'own_unit_price': 180.0,
          'competitor_unit_price': 150.0,
          'own_units': 10,
          'competitor_units': 8,
        },
        {
          'id': 'csug_${i}_2',
          'own_barcode': 'OWN$i',
          'own_sku_name': 'صنف $i',
          'own_category': 'صابون سائل اطباق',
          'competitor_barcode': 'COMP${i}B',
          'competitor_sku_name': 'منافس $i-ب',
          'competitor_brand': 'Brand',
          'competitor_supplier': 'هنكل',
          'category': 'صابون سائل اطباق',
          'retailer_chain': 'fathalla',
          'reason_ar': 'حجم قريب',
          'confidence': 0.75,
          'rank': 2,
          'status': 'pending',
          'own_unit_price': 180.0,
          'competitor_unit_price': 160.0,
          'own_units': 10,
          'competitor_units': 7,
        },
      ],
    ];

    MockClient fake() => MockClient((req) async {
          if (req.url.path.contains('/competitors/suggestions') &&
              req.method == 'GET') {
            return http.Response.bytes(
              utf8.encode(jsonEncode({
                'suggestions': store,
                'count': store.length,
              })),
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

      // 25 own SKUs × 2 suggestions; page size 20 → first page shows 20 group cards.
      expect(find.textContaining('25 صنفًا · 50 اقتراحًا'), findsOneWidget);
      expect(find.text('موافقة على الكل'), findsNWidgets(20));
      expect(find.byKey(const ValueKey('suggestion-group-OWN0')), findsOneWidget);
      expect(find.byKey(const ValueKey('suggestion-group-OWN19')), findsOneWidget);
      expect(find.byKey(const ValueKey('suggestion-group-OWN20')), findsNothing);

      // Batch dropdown still 5/10 only — does not shrink the pending count.
      expect(find.byKey(const ValueKey('run-suggestions-batch')), findsOneWidget);
      expect(find.text('تشغيل دفعة'), findsOneWidget);

      // M3 tonal/outlined actions — not solid dark-green FilledButton alone.
      expect(find.text('موافقة'), findsWidgets);
      expect(find.text('رفض'), findsWidgets);

      // Pager sits below ~20 tall cards; must scroll into the 800×600 test viewport.
      final nextPage = find.byTooltip('الصفحة التالية');
      await tester.ensureVisible(nextPage);
      await tester.pumpAndSettle();
      await tester.tap(nextPage);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('suggestion-group-OWN20')), findsOneWidget);
      expect(find.text('موافقة على الكل'), findsNWidgets(5));
    }, fake);
  });

  testWidgets('approve-all for a group clears that own SKU card', (tester) async {
    final store = <Map<String, dynamic>>[
      {
        'id': 'csug_1',
        'own_barcode': 'OWN1',
        'own_sku_name': 'فيبا 3 كجم',
        'own_category': 'صابون سائل اطباق',
        'competitor_barcode': 'COMP1',
        'competitor_sku_name': 'بريل 4 كجم',
        'competitor_brand': 'Pril',
        'competitor_supplier': 'هنكل',
        'category': 'صابون سائل اطباق',
        'retailer_chain': 'fathalla',
        'reason_ar': 'نفس الفئة',
        'confidence': 0.82,
        'rank': 1,
        'status': 'pending',
        'own_unit_price': 180.0,
        'competitor_unit_price': 150.0,
        'own_units': 10,
        'competitor_units': 8,
      },
      {
        'id': 'csug_2',
        'own_barcode': 'OWN1',
        'own_sku_name': 'فيبا 3 كجم',
        'own_category': 'صابون سائل اطباق',
        'competitor_barcode': 'COMP2',
        'competitor_sku_name': 'فيري 2 لتر',
        'competitor_brand': 'Fairy',
        'competitor_supplier': 'P&G',
        'category': 'صابون سائل اطباق',
        'retailer_chain': 'fathalla',
        'reason_ar': 'حجم قريب',
        'confidence': 0.8,
        'rank': 2,
        'status': 'pending',
        'own_unit_price': 180.0,
        'competitor_unit_price': 160.0,
        'own_units': 10,
        'competitor_units': 6,
      },
    ];
    final approved = <String>[];
    var mappingsChanged = 0;

    MockClient fake() => MockClient((req) async {
          if (req.url.path.contains('/competitors/suggestions/approve') &&
              req.method == 'POST') {
            final body = jsonDecode(req.body) as Map<String, dynamic>;
            final id = '${body['id']}';
            approved.add(id);
            store.removeWhere((r) => r['id'] == id);
            return http.Response.bytes(
              utf8.encode(jsonEncode({
                'suggestion': {'id': id, 'status': 'approved'},
                'mapping': {'id': 'cmap_$id'},
              })),
              200,
              headers: {'content-type': 'application/json'},
            );
          }
          if (req.url.path.contains('/competitors/suggestions') &&
              req.method == 'GET') {
            return http.Response.bytes(
              utf8.encode(jsonEncode({
                'suggestions': store,
                'count': store.length,
              })),
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
                onMappingsChanged: () => mappingsChanged++,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('suggestion-group-OWN1')), findsOneWidget);
      expect(find.text('بريل 4 كجم'), findsOneWidget);
      expect(find.text('فيري 2 لتر'), findsOneWidget);

      await tester.tap(find.text('موافقة على الكل'));
      await tester.pumpAndSettle();

      expect(approved, containsAll(['csug_1', 'csug_2']));
      expect(find.text('لا توجد اقتراحات بانتظار الموافقة'), findsOneWidget);
      expect(mappingsChanged, greaterThan(0));
    }, fake);
  });
}
