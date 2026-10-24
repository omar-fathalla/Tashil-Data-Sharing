import 'package:http/http.dart' as http;

/// Single entry point for every backend HTTP call.
///
/// Every response passes through [onResponseStatus], which ApiClient wires to
/// its session-expired handling: a 401/403 (refused or expired login, e.g. a
/// stale token after a deploy) logs the user out to the login screen instead
/// of leaving pages blank.
class BackendHttp {
  BackendHttp._();

  static void Function(int statusCode, Uri url)? onResponseStatus;

  static T _note<T extends http.BaseResponse>(T r, Uri url) {
    onResponseStatus?.call(r.statusCode, url);
    return r;
  }

  static Future<http.Response> get(Uri url, {Map<String, String>? headers}) async =>
      _note(await http.get(url, headers: headers), url);

  static Future<http.Response> post(Uri url,
          {Map<String, String>? headers, Object? body}) async =>
      _note(await http.post(url, headers: headers, body: body), url);

  static Future<http.Response> put(Uri url,
          {Map<String, String>? headers, Object? body}) async =>
      _note(await http.put(url, headers: headers, body: body), url);

  static Future<http.Response> patch(Uri url,
          {Map<String, String>? headers, Object? body}) async =>
      _note(await http.patch(url, headers: headers, body: body), url);

  static Future<http.Response> delete(Uri url,
          {Map<String, String>? headers, Object? body}) async =>
      _note(await http.delete(url, headers: headers, body: body), url);

  static Future<http.StreamedResponse> send(http.BaseRequest request) async =>
      _note(await request.send(), request.url);
}
