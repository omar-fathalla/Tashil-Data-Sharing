import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tashil_web/core/network/api_client.dart';
import 'package:tashil_web/core/theme/app_theme.dart';
import 'package:tashil_web/features/executive_dashboard/presentation/screens/executive_screen.dart';

/// Regression: a stale token after a deploy made the backend answer 401 and the
/// Executive Dashboard body rendered completely blank. It must now trigger the
/// session-expired hook (→ logout/login) and show an error + Retry state.
void main() {
  testWidgets('ExecutiveScreen at 1280px: 401 → session expired hook + error/retry state, never blank',
      (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
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
      final api = ApiClient(tenantId: 'tenant-expired-401', allowMockFallback: false);
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(body: ExecutiveScreen(apiClient: api)),
      ));
      await tester.pumpAndSettle();
    }, () => MockClient((_) async => http.Response('{"error":"invalid token"}', 401)));

    FlutterError.onError = prev;
    expect(errors, isEmpty, reason: errors.map((e) => e.exceptionAsString()).join('\n'));
    expect(expired, greaterThan(0));
    expect(find.byKey(const ValueKey('exec_error_state')), findsOneWidget);
    expect(find.byKey(const ValueKey('exec_retry_button')), findsOneWidget);
  });
}
