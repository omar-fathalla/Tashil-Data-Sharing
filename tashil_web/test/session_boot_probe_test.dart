
// After a JWT rotation, a stored (still unexpired) token is not a valid
// session. The boot probe hits GET /api/v1/me; only HTTP 200 is a valid
// session. A 401 forces a re-login. 503 / network errors are "unavailable"
// so the shell stays closed (no partial 401 storm) without clearing the token.
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tashil_web/core/network/api_client.dart';
import 'package:tashil_web/core/network/backend_http.dart';

void main() {
  setUp(() {
    BackendHttp.cache.clear();
    BackendHttp.onResponseStatus = null;
    ApiClient.onSessionExpired = null;
  });
  tearDown(() {
    BackendHttp.cache.clear();
    BackendHttp.onResponseStatus = null;
    ApiClient.onSessionExpired = null;
  });

  Future<SessionVerifyResult> probe(Object script, {String token = 'fresh-token'}) {
    return http.runWithClient(() {
      final api = ApiClient(
        tenantId: 'tenant-adeco',
        authToken: token,
        allowMockFallback: false,
      );
      return api.verifySession();
    }, () => MockClient((req) async {
      expect(req.url.path, '/api/v1/me');
      if (script is int) {
        return http.Response(
            script == 200 ? '{"user_id":"u1","tenant_id":"tenant-adeco"}' : 'no',
            script);
      }
      throw script;
    }));
  }

  test('authorizationHeader is case-insensitive', () {
    expect(BackendHttp.authorizationHeader({'Authorization': 'Bearer a'}),
        'Bearer a');
    expect(BackendHttp.authorizationHeader({'authorization': 'Bearer b'}),
        'Bearer b');
    expect(BackendHttp.authorizationHeader({'AUTHORIZATION': 'Bearer c'}),
        'Bearer c');
    expect(BackendHttp.authorizationHeader({'X-Tenant-ID': 't'}), isNull);
    expect(BackendHttp.authorizationHeader(null), isNull);
  });

  test('empty token is not a valid session', () async {
    final api = ApiClient(authToken: '', allowMockFallback: false);
    expect(await api.verifySession(), SessionVerifyResult.unauthorized);
  });

  test('401 from /me is a rejected session', () async {
    expect(await probe(401), SessionVerifyResult.unauthorized);
  });

  test('200 from /me is a valid session', () async {
    expect(await probe(200), SessionVerifyResult.valid);
  });

  test('503 from /me is unavailable — not a valid session and not a logout',
      () async {
    expect(await probe(503), SessionVerifyResult.unavailable);
  });

  test('network error is unavailable — not a valid session and not a logout',
      () async {
    expect(await probe(http.ClientException('offline')),
        SessionVerifyResult.unavailable);
  });
}
