import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tashil_web/core/network/api_client.dart';
import 'package:tashil_web/core/theme/app_theme.dart';
import 'package:tashil_web/features/sell_out_analytics/presentation/screens/sell_in_explorer_screen.dart';

/// While Sell-In totals load, KPI cards and the waterfall show M3 skeletons and a progress bar,
/// never a previous filter's numbers; the values appear once the response arrives.
void main() {
  testWidgets('Sell-In KPI cards and waterfall show skeletons until totals arrive', (tester) async {
    tester.view.physicalSize = const Size(1400, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final gate = Completer<void>();
    final body = jsonEncode({
      'records': [],
      'total_count': 7,
      'total_value_egp': 1234567.0,
      'total_cases': 100.0,
      'total_units_pieces': 1200,
      'total_net_excl_vat_egp': 1234567.0,
      'total_official_list_excl_vat_egp': 1500000.0,
      'total_discount_granted_egp': 265433.0,
      'effective_discount_pct': 17.7,
    });
    await http.runWithClient(() async {
      final api = ApiClient(tenantId: 'tenant-skeleton-test', allowMockFallback: false);
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(body: SellInExplorerScreen(apiClient: api)),
      ));
      await tester.pump();
      expect(find.byKey(const ValueKey('sell_in_loading_bar')), findsOneWidget);
      expect(find.byKey(const ValueKey('sell_in_kpi_skeleton')), findsWidgets);
      expect(find.byKey(const ValueKey('sell_in_waterfall_skeleton')), findsWidgets);
      final bar = tester.widget<LinearProgressIndicator>(find.byKey(const ValueKey('sell_in_loading_bar')));
      // ignore: deprecated_member_use
      expect(bar.year2023, isFalse);

      gate.complete();
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('sell_in_loading_bar')), findsNothing);
      expect(find.byKey(const ValueKey('sell_in_kpi_skeleton')), findsNothing);
      expect(find.byKey(const ValueKey('sell_in_waterfall_skeleton')), findsNothing);
    }, () => MockClient((req) async {
          if (req.url.path.contains('sell-in-records')) {
            await gate.future;
            return http.Response(body, 200, headers: {'content-type': 'application/json'});
          }
          return http.Response('{}', 200, headers: {'content-type': 'application/json'});
        }));
  });
}
