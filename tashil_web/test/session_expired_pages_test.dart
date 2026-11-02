import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tashil_web/core/network/api_client.dart';
import 'package:tashil_web/core/theme/app_theme.dart';
import 'package:tashil_web/features/executive_dashboard/presentation/screens/executive_screen.dart';
import 'package:tashil_web/features/sell_out_analytics/presentation/screens/sell_in_explorer_screen.dart';
import 'package:tashil_web/features/sell_out_analytics/presentation/screens/sell_out_explorer_screen.dart';

/// Regression: an expired/refused login (HTTP 401) must route through the
/// shared BackendHttp handler (→ logout to login) and pages must show an
/// error + Retry state instead of a blank/empty body.
Future<(int, List<FlutterErrorDetails>)> _pump401(
    WidgetTester tester, Widget Function(ApiClient) page,
    {Size size = const Size(1280, 800)}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  var expired = 0;
  ApiClient.installSessionGuard();
  ApiClient.onSessionExpired = () => expired++;
  addTearDown(() => ApiClient.onSessionExpired = null);
  final errors = <FlutterErrorDetails>[];
  final prev = FlutterError.onError;
  FlutterError.onError = errors.add;
  await http.runWithClient(() async {
    final api = ApiClient(tenantId: 'tenant-expired-401', authToken: 'current-token', allowMockFallback: false);
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(body: page(api)),
    ));
    await tester.pumpAndSettle();
  }, () => MockClient((_) async => http.Response('{"error":"invalid token"}', 401)));
  FlutterError.onError = prev;
  return (expired, errors);
}

void main() {
  testWidgets('Sell-Out: 401 → session expired + error/Retry state', (tester) async {
    final (expired, errors) =
        await _pump401(tester, (api) => SellOutExplorerScreen(apiClient: api));
    expect(errors, isEmpty, reason: errors.map((e) => e.exceptionAsString()).join('\n'));
    expect(expired, greaterThan(0));
    expect(find.byKey(const ValueKey('sell_out_error_state')), findsOneWidget);
    expect(find.text('إعادة المحاولة'), findsOneWidget);
  });

  testWidgets('Sell-In: 401 → session expired + error/Retry state', (tester) async {
    final (expired, errors) =
        await _pump401(tester, (api) => SellInExplorerScreen(apiClient: api));
    expect(errors, isEmpty, reason: errors.map((e) => e.exceptionAsString()).join('\n'));
    expect(expired, greaterThan(0));
    expect(find.byKey(const ValueKey('sell_in_error_state')), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
  });

  testWidgets('Auth endpoints (wrong password) never trigger session expiry', (tester) async {
    var expired = 0;
    ApiClient.onSessionExpired = () => expired++;
    addTearDown(() => ApiClient.onSessionExpired = null);
    ApiClient.reportAuthStatus(401, Uri.parse('https://x/api/v1/auth/login'));
    ApiClient.reportAuthStatus(403, Uri.parse('https://x/api/v1/sellout'));
    expect(expired, 0);
  });

  testWidgets('Executive Dashboard header has no overflow at 900px window with sidebar',
      (tester) async {
    tester.view.physicalSize = const Size(900, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final errors = <FlutterErrorDetails>[];
    final prev = FlutterError.onError;
    FlutterError.onError = errors.add;
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light(),
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          body: Row(children: [
            const SizedBox(width: 280),
            Expanded(child: ExecutiveScreen(apiClient: ApiClient(tenantId: 'tenant_adeco'))),
          ]),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    FlutterError.onError = prev;
    expect(errors, isEmpty, reason: errors.map((e) => e.exceptionAsString()).join('\n'));
  });
}
