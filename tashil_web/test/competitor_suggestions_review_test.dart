import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tashil_web/core/network/api_client.dart';
import 'package:tashil_web/features/competitor_comparison/presentation/widgets/competitor_suggestions_review.dart';

void main() {
  testWidgets(
      'pending suggestions review list shows own/competitor and approve clears queue',
      (tester) async {
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
        'reason_ar': 'نفس الفئة وحجم قريب',
        'confidence': 0.82,
        'rank': 1,
        'status': 'pending',
        'own_unit_price': 180.0,
        'competitor_unit_price': 150.0,
        'own_units': 10,
        'competitor_units': 8,
      },
    ];

    MockClient fake() => MockClient((req) async {
          if (req.url.path.contains('/competitors/suggestions/approve') &&
              req.method == 'POST') {
            final body = jsonDecode(req.body) as Map<String, dynamic>;
            store.removeWhere((r) => r['id'] == body['id']);
            return _json(
              jsonEncode({
                'suggestion': {'id': body['id'], 'status': 'approved'},
                'mapping': {'id': 'cmap_1'},
              }),
              200,
            );
          }
          if (req.url.path.contains('/competitors/suggestions/reject') &&
              req.method == 'POST') {
            final body = jsonDecode(req.body) as Map<String, dynamic>;
            store.removeWhere((r) => r['id'] == body['id']);
            return _json(
              jsonEncode({
                'suggestion': {'id': body['id'], 'status': 'rejected'},
              }),
              200,
            );
          }
          if (req.url.path.contains('/competitors/suggestions/run') &&
              req.method == 'POST') {
            return _json(
              jsonEncode({
                'created_count': 0,
                'suggestions': [],
                'skipped': [],
              }),
              200,
            );
          }
          if (req.url.path.contains('/competitors/suggestions') &&
              req.method == 'GET') {
            return _json(
              jsonEncode({'suggestions': store, 'count': store.length}),
              200,
            );
          }
          return _json('{"error":"unhandled"}', 500);
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

      expect(find.text('اقتراحات المنافسين (بانتظار الموافقة)'), findsOneWidget);
      expect(find.text('فيبا 3 كجم'), findsOneWidget);
      expect(find.text('بريل 4 كجم'), findsOneWidget);
      expect(find.text('نفس الفئة وحجم قريب'), findsOneWidget);
      expect(find.text('موافقة'), findsOneWidget);
      expect(find.text('رفض'), findsOneWidget);
      expect(find.text('موافقة على الكل'), findsOneWidget);
      expect(find.textContaining('تشغيل دفعة'), findsOneWidget);
      expect(find.text('صنف الشركة'), findsOneWidget);
      expect(find.text('المنافس المقترح'), findsOneWidget);
      expect(find.byKey(const ValueKey('suggestion-group-OWN1')), findsOneWidget);

      await tester.tap(find.text('موافقة'));
      await tester.pumpAndSettle();
      expect(find.text('لا توجد اقتراحات بانتظار الموافقة'), findsOneWidget);
    }, fake);
  });

  testWidgets('run failure shows Arabic snackbar instead of empty silence',
      (tester) async {
    MockClient fake() => MockClient((req) async {
          if (req.url.path.contains('/competitors/suggestions/run') &&
              req.method == 'POST') {
            return _json(
              jsonEncode({
                'error':
                    'فشل ترتيب كل الأصناف (1). تعذر ترتيب المرشحين: 1',
                'summary_ar':
                    'فشل ترتيب كل الأصناف (1). تعذر ترتيب المرشحين: 1',
                'created_count': 0,
                'suggestions': [],
                'skipped': [
                  {
                    'barcode': 'OWN1',
                    'reason_ar': 'تعذر ترتيب المرشحين',
                  }
                ],
                'skipped_reason_counts': {'تعذر ترتيب المرشحين': 1},
                'rank_attempts': 1,
                'rank_failures': 1,
              }),
              502,
            );
          }
          if (req.url.path.contains('/competitors/suggestions') &&
              req.method == 'GET') {
            return _json(
              jsonEncode({'suggestions': [], 'count': 0}),
              200,
            );
          }
          return _json('{"error":"unhandled"}', 500);
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

      expect(find.byType(SnackBar), findsOneWidget);
      expect(
        find.textContaining('تعذر تشغيل الاقتراحات'),
        findsWidgets,
      );
    }, fake);
  });
}

http.Response _json(String body, int status) => http.Response.bytes(
      utf8.encode(body),
      status,
      headers: {'content-type': 'application/json'},
    );
