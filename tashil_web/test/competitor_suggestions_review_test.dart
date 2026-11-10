import 'dart:async';
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
          if (req.url.path.contains('/competitors/suggestions/no-candidates') &&
              req.method == 'GET') {
            return _json(jsonEncode({'skus': [], 'count': 0}), 200);
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
      expect(find.byKey(const ValueKey('run-suggestions-batch')), findsOneWidget);
      expect(find.text('تشغيل دفعة'), findsOneWidget);
      expect(find.byKey(const ValueKey('generate-all-suggestions')), findsOneWidget);
      expect(find.text('توليد للكل'), findsOneWidget);
      expect(find.text('صنف الشركة'), findsOneWidget);
      expect(find.text('المنافس المقترح'), findsOneWidget);
      expect(find.byKey(const ValueKey('suggestion-group-OWN1')), findsOneWidget);

      await tester.tap(find.text('موافقة'));
      await tester.pumpAndSettle();
      expect(find.text('لا توجد اقتراحات بانتظار الموافقة'), findsOneWidget);
    }, fake);
  });

  testWidgets('توليد للكل loops /run until remaining_uncovered=0 with progress',
      (tester) async {
    var runCalls = 0;
    final store = <Map<String, dynamic>>[];
    // Gate the 2nd /run so progress UI is observable mid-loop (zero cooldown
    // would otherwise finish both batches before the assert).
    final allowSecondRun = Completer<void>();

    MockClient fake() => MockClient((req) async {
          if (req.url.path.contains('/competitors/suggestions/run') &&
              req.method == 'POST') {
            runCalls++;
            if (runCalls == 1) {
              store.add({
                'id': 'csug_a',
                'own_barcode': 'OWN1',
                'own_sku_name': 'صنف 1',
                'own_category': 'صابون',
                'competitor_barcode': 'C1',
                'competitor_sku_name': 'منافس 1',
                'competitor_brand': 'Brand',
                'competitor_supplier': 'S',
                'category': 'صابون',
                'retailer_chain': 'fathalla',
                'reason_ar': 'نفس الفئة',
                'confidence': 0.8,
                'rank': 1,
                'status': 'pending',
                'own_unit_price': 10.0,
                'competitor_unit_price': 9.0,
                'own_units': 1,
                'competitor_units': 1,
              });
              return _json(
                jsonEncode({
                  'created_count': 1,
                  'processed_own': 1,
                  'remaining_uncovered': 1,
                  'suggestions': [store.last],
                  'skipped': [],
                }),
                200,
              );
            }
            await allowSecondRun.future;
            store.add({
              'id': 'csug_b',
              'own_barcode': 'OWN2',
              'own_sku_name': 'صنف 2',
              'own_category': 'صابون',
              'competitor_barcode': 'C2',
              'competitor_sku_name': 'منافس 2',
              'competitor_brand': 'Brand',
              'competitor_supplier': 'S',
              'category': 'صابون',
              'retailer_chain': 'fathalla',
              'reason_ar': 'نفس الفئة',
              'confidence': 0.8,
              'rank': 1,
              'status': 'pending',
              'own_unit_price': 10.0,
              'competitor_unit_price': 9.0,
              'own_units': 1,
              'competitor_units': 1,
            });
            return _json(
              jsonEncode({
                'created_count': 1,
                'processed_own': 1,
                'remaining_uncovered': 0,
                'suggestions': [store.last],
                'skipped': [],
              }),
              200,
            );
          }
          if (req.url.path.contains('/competitors/suggestions/no-candidates') &&
              req.method == 'GET') {
            return _json(jsonEncode({'skus': [], 'count': 0}), 200);
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
                chainRunCooldown: Duration.zero,
                rateLimitBackoff: Duration.zero,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('توليد للكل'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('generate-all-suggestions')));
      // First /run + reload; second /run is gated so progress stays visible.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.byKey(const ValueKey('generate-all-progress')), findsOneWidget);
      expect(find.textContaining('1 من'), findsWidgets);

      allowSecondRun.complete();
      await tester.pumpAndSettle();

      expect(runCalls, 2);
      expect(find.text('توليد للكل'), findsOneWidget);
      expect(store, hasLength(2));
    }, fake);
  });

  testWidgets('توليد للكل stop button ends the loop early', (tester) async {
    var runCalls = 0;
    MockClient fake() => MockClient((req) async {
          if (req.url.path.contains('/competitors/suggestions/run') &&
              req.method == 'POST') {
            runCalls++;
            return _json(
              jsonEncode({
                'created_count': 1,
                'processed_own': 1,
                'remaining_uncovered': 50,
                'suggestions': [],
                'skipped': [],
              }),
              200,
            );
          }
          if (req.url.path.contains('/competitors/suggestions/no-candidates') &&
              req.method == 'GET') {
            return _json(jsonEncode({'skus': [], 'count': 0}), 200);
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
                // Long cooldown so we can tap stop between batches.
                chainRunCooldown: const Duration(seconds: 30),
                rateLimitBackoff: Duration.zero,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('generate-all-suggestions')));
      // Allow the first /run + reload to finish, then sit in the cooldown wait.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.byKey(const ValueKey('stop-generate-all-suggestions')),
          findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('stop-generate-all-suggestions')));
      await tester.pump();
      // Drain the remaining cooldown timer after stop was requested.
      await tester.pump(const Duration(seconds: 30));
      await tester.pumpAndSettle();

      expect(runCalls, 1);
      expect(find.text('توليد للكل'), findsOneWidget);
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
          if (req.url.path.contains('/competitors/suggestions/no-candidates') &&
              req.method == 'GET') {
            return _json(jsonEncode({'skus': [], 'count': 0}), 200);
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

      await tester.tap(find.byKey(const ValueKey('run-suggestions-batch')));
      await tester.pumpAndSettle();

      expect(find.byType(SnackBar), findsOneWidget);
      expect(
        find.textContaining('تعذر تشغيل الاقتراحات'),
        findsWidgets,
      );
    }, fake);
  });

  testWidgets('no-suggestion SKUs panel shows per-SKU Arabic reason',
      (tester) async {
    MockClient fake() => MockClient((req) async {
          if (req.url.path.contains('/competitors/suggestions/no-candidates') &&
              req.method == 'GET') {
            return _json(
              jsonEncode({
                'count': 2,
                'auto_create_competitors': false,
                'skus': [
                  {
                    'barcode': 'OWN-CARE-1',
                    'sku_name': 'ديفا منظف ايدى الترا فريش',
                    'category': 'عناية شخصية',
                    'reason_ar':
                        'لا يوجد منافسين في نفس الفئة «عناية شخصية»',
                    'reason_code': 'NO_SAME_CATEGORY_COMPETITORS',
                  },
                  {
                    'barcode': 'OWN-FELVITA-OFFER',
                    'sku_name':
                        'عرض سعر فلفيتا 500 جم مزيل بقع مطور مسحوق',
                    'category': 'مزيلات بقع ملابس',
                    'reason_ar':
                        'تم استبعاد كل المنافسين (مرفوض أو معتمد مسبقاً)',
                    'reason_code': 'ALL_CANDIDATES_EXCLUDED',
                  },
                ],
              }),
              200,
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

      expect(find.byKey(const ValueKey('no-suggestion-skus-panel')), findsOneWidget);
      expect(find.textContaining('أصناف بلا اقتراحات (2)'), findsOneWidget);
      expect(find.text('ديفا منظف ايدى الترا فريش'), findsOneWidget);
      expect(
        find.text('لا يوجد منافسين في نفس الفئة «عناية شخصية»'),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('no-suggestion-sku-OWN-CARE-1')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('no-suggestion-sku-OWN-FELVITA-OFFER')),
        findsOneWidget,
      );
      expect(
        find.textContaining('لا يُنشأ منافسون تلقائياً'),
        findsOneWidget,
      );
    }, fake);
  });
}

http.Response _json(String body, int status) => http.Response.bytes(
      utf8.encode(body),
      status,
      headers: {'content-type': 'application/json'},
    );
