import 'package:flutter_test/flutter_test.dart';
import 'package:tashil_web/core/network/api_client.dart';

/// Regression (2026-11-02 23:43 Cairo): a 401 for a request sent before login,
/// arriving ~2 min late during a cold start, logged out the fresh session.
void main() {
  final url = Uri.parse('https://x/api/v1/analytics/executive-summary');
  late int expired;

  setUp(() {
    expired = 0;
    ApiClient.onSessionExpired = () => expired++;
  });
  tearDown(() => ApiClient.onSessionExpired = null);

  test('late 401 from a pre-login request (no token) does not log out', () {
    ApiClient(authToken: 'fresh-token');
    ApiClient.reportAuthStatus(401, url, 'Bearer ');
    ApiClient.reportAuthStatus(401, url, null);
    expect(expired, 0);
  });

  test('late 401 for an old token does not log out the new session', () {
    final api = ApiClient(authToken: 'old-token');
    api.authToken = 'fresh-token';
    ApiClient.reportAuthStatus(401, url, 'Bearer old-token');
    expect(expired, 0);
  });

  test('401 with the current token logs out', () {
    ApiClient(authToken: 'fresh-token');
    ApiClient.reportAuthStatus(401, url, 'Bearer fresh-token');
    expect(expired, 1);
  });

  test('403 with the current token does not log out', () {
    ApiClient(authToken: 'fresh-token');
    ApiClient.reportAuthStatus(403, url, 'Bearer fresh-token');
    expect(expired, 0);
  });
}
