import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:tashil_web/core/network/backend_http.dart';

/// Every test starts with an empty HTTP stale-while-revalidate cache, so cached
/// responses from one test's mock server never leak into another.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  setUp(BackendHttp.cache.clear);
  await testMain();
}
