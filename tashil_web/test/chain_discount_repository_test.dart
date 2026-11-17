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
}
