import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tashil_web/core/network/api_client.dart';
import 'package:tashil_web/features/trade_marketing/data/cached_trade_marketing_repository.dart';
import 'package:tashil_web/features/trade_marketing/data/trade_marketing_repository.dart';

void main() {
  http.Response j(Object body, [int status = 200]) =>
      http.Response.bytes(utf8.encode(jsonEncode(body)), status, headers: {'content-type': 'application/json'});

  MockClient server(List<String> log, {int roiStatus = 200}) => MockClient((req) async {
        log.add('${req.method} ${req.url.path}');
        if (req.url.path.endsWith('/roi')) {
          if (roiStatus != 200) return j({'error': 'boom'}, roiStatus);
          return j({
            'summaries': [
              {'year': 2026, 'month': 3, 'chain_name': 'Fathalla', 'current_month_sales_egp': 1000}
            ]
          });
        }
        if (req.method == 'DELETE') return j({'ok': true});
        return j({'expenses': []});
      });

  CachedTradeMarketingRepository build(MockClient c) {
    final api = ApiClient(tenantId: 'tenant-adeco', allowMockFallback: false);
    return CachedTradeMarketingRepository(ApiTradeMarketingRepository(api, httpClient: c), api);
  }

  test('ROI + expenses are cached; writes invalidate', () async {
    final log = <String>[];
    final repo = build(server(log));
    expect((await repo.getRoi()).single.currentMonthSalesEgp, 1000);
    await repo.getRoi();
    await repo.listExpenses();
    await repo.listExpenses();
    expect(log.length, 2);
    await repo.getRoi(year: 2026, month: 3, chain: 'Fathalla');
    expect(log.length, 3, reason: 'different filter = new key');
    await repo.deleteExpense('x1');
    await repo.getRoi();
    expect(log.length, 5, reason: 'delete invalidated cache');
  });

  test('errors keep TradeMarketingException contract and Result helper wraps them', () async {
    final repo = build(server([], roiStatus: 401));
    await expectLater(repo.getRoi(), throwsA(isA<TradeMarketingException>()));
    final r = await repo.loadRoi();
    expect(r.isFailure, isTrue);
    expect(r.errorOrNull!.isAuth, isTrue);
    expect(r.errorOrNull!.message, 'boom');
  });
}
