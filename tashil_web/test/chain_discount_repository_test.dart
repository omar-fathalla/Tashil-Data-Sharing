import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tashil_web/core/network/api_client.dart';
import 'package:tashil_web/core/network/backend_http.dart';
import 'package:tashil_web/features/product_master/data/chain_discount_repository.dart';

void main() {
  tearDown(() {
    ChainDiscountRepository.loadTimeout = const Duration(seconds: 20);
    ChainDiscountRepository.saveTimeout = const Duration(seconds: 45);
    BackendHttp.cache.clear();
  });

  ChainDiscountRepository repo() => ChainDiscountRepository(
      ApiClient(tenantId: 'tenant-adeco', allowMockFallback: false));

  test('client budget is 20s (backend bounds its own read at 5s)', () {
    expect(ChainDiscountRepository.loadTimeout, const Duration(seconds: 20));
  });

  test('a hung GET surfaces the friendly Arabic timeout, not TimeoutException',
      () async {
    ChainDiscountRepository.loadTimeout = const Duration(milliseconds: 30);
    final server = MockClient((req) async {
      await Future<void>.delayed(const Duration(seconds: 1));
      return http.Response('{}', 200);
    });
    await http.runWithClient(() async {
      await expectLater(
        repo().load(),
        throwsA(isA<ChainDiscountException>()
            .having((e) => e.message, 'message', kChainDiscountTimeoutMessage)
            .having((e) => e.toString(), 'toString',
                isNot(contains('TimeoutException')))),
      );
    }, () => server);
  });

  test('backend 504 (store timed out) maps to the same friendly message',
      () async {
    final server = MockClient((req) async => http.Response(
        jsonEncode({'error': 'chain discounts store timed out'}), 504));
    await http.runWithClient(() async {
      await expectLater(
        repo().load(),
        throwsA(isA<ChainDiscountException>()
            .having((e) => e.message, 'message', kChainDiscountTimeoutMessage)),
      );
    }, () => server);
  });

  test('connection errors map to an Arabic connection message', () async {
    final server = MockClient((req) async => throw http.ClientException('x'));
    await http.runWithClient(() async {
      await expectLater(
        repo().load(),
        throwsA(isA<ChainDiscountException>().having(
            (e) => e.message, 'message', kChainDiscountConnectionMessage)),
      );
    }, () => server);
  });

  test('friendlyChainDiscountError', () {
    expect(friendlyChainDiscountError(TimeoutException('x')),
        kChainDiscountTimeoutMessage);
    expect(friendlyChainDiscountError(const ChainDiscountException('رسالة')),
        'رسالة');
    expect(friendlyChainDiscountError(StateError('boom')),
        kChainDiscountConnectionMessage);
  });

  test('known chains: 200 keeps the normalized key, not the display name', () async {
    final server = MockClient((req) async {
      expect(req.url.path, '/api/v1/product-master/chains');
      return http.Response(
          jsonEncode({
            'chains': [
              {
                'key': 'fathalla',
                'name': 'fathalla',
                'display_name': 'أسواق فتح الله (Fathalla Market)',
                'row_count': 4,
                'last_data_date': '2026-05-01'
              }
            ]
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'});
    });
    await http.runWithClient(() async {
      final list = await repo().loadKnownChains();
      expect(list.single.key, 'fathalla');
      expect(list.single.displayName, 'أسواق فتح الله (Fathalla Market)');
      expect(list.single.rowCount, 4);
      expect(list.single.lastDataDate, '2026-05-01');
    }, () => server);
  });

  test('known chains: 504 and a hang become the Arabic timeout, never the raw exception',
      () async {
    final server = MockClient((req) async => http.Response(
        jsonEncode({'error': 'known chains lookup timed out'}), 504));
    await http.runWithClient(() async {
      await expectLater(
        repo().loadKnownChains(),
        throwsA(isA<ChainDiscountException>().having(
            (e) => e.message, 'message', kKnownChainsTimeoutMessage)),
      );
    }, () => server);

    ChainDiscountRepository.loadTimeout = const Duration(milliseconds: 30);
    final hung = MockClient((req) async {
      await Future<void>.delayed(const Duration(seconds: 1));
      return http.Response('{}', 200);
    });
    await http.runWithClient(() async {
      await expectLater(
        repo().loadKnownChains(),
        throwsA(isA<ChainDiscountException>()
            .having((e) => e.message, 'message', kKnownChainsTimeoutMessage)
            .having((e) => e.toString(), 'toString',
                isNot(contains('TimeoutException')))),
      );
    }, () => hung);
  });

  test('known chains: connection errors stay Arabic', () async {
    final server = MockClient((req) async => throw http.ClientException('x'));
    await http.runWithClient(() async {
      await expectLater(
        repo().loadKnownChains(),
        throwsA(isA<ChainDiscountException>().having(
            (e) => e.message, 'message', kKnownChainsConnectionMessage)),
      );
    }, () => server);
  });

  test('200 parses profiles', () async {
    final server = MockClient((req) async => http.Response(
        jsonEncode({
          'profiles': [
            {
              'chain': 'kazyon',
              'invoice_discount_pct': 12,
              'additional_discount_pct': 2
            }
          ]
        }),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'}));
    await http.runWithClient(() async {
      final list = await repo().load();
      expect(list.single.chain, 'kazyon');
      expect(list.single.invoiceDiscountPct, 12);
    }, () => server);
  });

  group('save', () {
    const sent = [
      ChainDiscountProfileModel(
          chain: 'kazyon',
          invoiceDiscountPct: 12,
          additionalDiscountPct: 2,
          vatRatePct: 14),
      ChainDiscountProfileModel(
          chain: 'fathalla', invoiceDiscountPct: 10, additionalDiscountPct: 0),
    ];

    String body(List<Map<String, dynamic>> profiles) =>
        jsonEncode({'profiles': profiles});

    Map<String, dynamic> row(String chain, double inv, double add,
            {double? vat}) =>
        {
          'chain': chain,
          'invoice_discount_pct': inv,
          'additional_discount_pct': add,
          if (vat != null) 'vat_rate_pct': vat,
          'updated_at': '2026-11-17T15:38:00Z',
          'updated_by': 'admin@adeco.test',
        };

    final jsonHeaders = {'content-type': 'application/json; charset=utf-8'};

    test('the PUT budget is 45s (the live save took 14.9s and 22.7s)', () {
      expect(ChainDiscountRepository.saveTimeout, const Duration(seconds: 45));
    });

    test('a slow PUT inside the budget succeeds without a read-back', () async {
      var gets = 0;
      final server = MockClient((req) async {
        if (req.method == 'GET') gets++;
        await Future<void>.delayed(const Duration(milliseconds: 40));
        return http.Response(
            body([row('kazyon', 12, 2, vat: 14), row('fathalla', 10, 0)]), 200,
            headers: jsonHeaders);
      });
      ChainDiscountRepository.saveTimeout = const Duration(seconds: 5);
      await http.runWithClient(() async {
        final out = await repo().save(sent);
        expect(out.map((p) => p.chain), ['kazyon', 'fathalla']);
      }, () => server);
      expect(gets, 0);
    });

    test('PUT times out but the server stored it: re-GET equals sent -> saved',
        () async {
      ChainDiscountRepository.saveTimeout = const Duration(milliseconds: 30);
      final methods = <String>[];
      final server = MockClient((req) async {
        methods.add(req.method);
        if (req.method == 'PUT') {
          await Future<void>.delayed(const Duration(seconds: 1));
          return http.Response('{}', 200);
        }
        return http.Response(
            body([row('fathalla', 10, 0), row('Kazyon', 12, 2, vat: 14)]), 200,
            headers: jsonHeaders);
      });
      await http.runWithClient(() async {
        final out = await repo().save(sent);
        expect(out.map((p) => p.chain).toSet(), {'fathalla', 'Kazyon'});
        expect(out.first.updatedBy, 'admin@adeco.test',
            reason: 'the table shows what the server stored');
      }, () => server);
      expect(methods, ['PUT', 'GET']);
    });

    test('PUT times out and the stored list differs -> unverified, not saved',
        () async {
      ChainDiscountRepository.saveTimeout = const Duration(milliseconds: 30);
      final server = MockClient((req) async {
        if (req.method == 'PUT') {
          await Future<void>.delayed(const Duration(seconds: 1));
          return http.Response('{}', 200);
        }
        return http.Response(body([row('kazyon', 11, 2, vat: 14)]), 200,
            headers: jsonHeaders);
      });
      await http.runWithClient(() async {
        await expectLater(
          repo().save(sent),
          throwsA(isA<ChainDiscountSaveUnverifiedException>().having(
              (e) => e.message,
              'message',
              kChainDiscountSaveUnverifiedMessage)),
        );
      }, () => server);
    });

    test('PUT times out and the re-GET fails too -> unverified', () async {
      ChainDiscountRepository.saveTimeout = const Duration(milliseconds: 30);
      final server = MockClient((req) async {
        if (req.method == 'PUT') {
          await Future<void>.delayed(const Duration(seconds: 1));
          return http.Response('{}', 200);
        }
        return http.Response('{}', 504);
      });
      await http.runWithClient(() async {
        await expectLater(repo().save(sent),
            throwsA(isA<ChainDiscountSaveUnverifiedException>()));
      }, () => server);
    });

    test('the read-back is a fresh GET, not a cached copy', () async {
      ChainDiscountRepository.saveTimeout = const Duration(milliseconds: 30);
      var gets = 0;
      final server = MockClient((req) async {
        if (req.method == 'PUT') {
          await Future<void>.delayed(const Duration(seconds: 1));
          return http.Response('{}', 200);
        }
        gets++;
        // First GET (the page load) returns the old list, the read-back the new one.
        return http.Response(
            gets == 1
                ? body([])
                : body([row('kazyon', 12, 2, vat: 14), row('fathalla', 10, 0)]),
            200,
            headers: jsonHeaders);
      });
      await http.runWithClient(() async {
        expect(await repo().load(), isEmpty);
        final out = await repo().save(sent);
        expect(out, hasLength(2));
      }, () => server);
      expect(gets, 2);
    });

    test('a 400 from the server is surfaced, never verified', () async {
      var gets = 0;
      final server = MockClient((req) async {
        if (req.method == 'GET') gets++;
        return http.Response(jsonEncode({'error': 'invalid'}), 400);
      });
      await http.runWithClient(() async {
        await expectLater(
            repo().save(sent),
            throwsA(isA<ChainDiscountException>()
                .having((e) => e, 'type', isNot(isA<ChainDiscountSaveUnverifiedException>()))));
      }, () => server);
      expect(gets, 0);
    });

    test('sameChainProfileTerms ignores order, case and audit fields', () {
      expect(
          sameChainProfileTerms(sent, sent.reversed.toList()), isTrue);
      expect(
          sameChainProfileTerms([
            const ChainDiscountProfileModel(
                chain: ' Kazyon ',
                invoiceDiscountPct: 12,
                additionalDiscountPct: 2,
                vatRatePct: 14,
                updatedBy: 'x')
          ], [
            sent.first
          ]),
          isTrue);
      expect(
          sameChainProfileTerms(sent, [sent.first]), isFalse);
      expect(
          sameChainProfileTerms([
            sent.first
          ], [
            const ChainDiscountProfileModel(
                chain: 'kazyon',
                invoiceDiscountPct: 12,
                additionalDiscountPct: 2)
          ]),
          isFalse,
          reason: 'VAT set vs unset differs');
    });
  });
}
