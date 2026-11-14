
// After a JWT rotation, a stored (still unexpired) token is not a valid
// session. The boot probe hits GET /api/v1/me once; only a 401 is treated
// as "log in again". Other failures must not bounce a valid user.
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

  Future<bool> probe(Object script, {String token = 'fresh-token'}) {
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
    expect(await api.verifySession(), isFalse);
  });

  test('401 from /me is a rejected session', () async {
    expect(await probe(401), isFalse);
  });

  test('200 from /me is a valid session', () async {
    expect(await probe(200), isTrue);
  });

  test('503 from /me does not force a re-login', () async {
    expect(await probe(503), isTrue);
  });

  test('network error does not force a re-login', () async {
    expect(await probe(http.ClientException('offline')), isTrue);
  });
}
