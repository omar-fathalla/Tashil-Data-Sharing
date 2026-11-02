import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:tashil_web/core/data/available_years.dart';
import 'package:tashil_web/core/network/backend_http.dart';

/// Every test starts with an empty HTTP stale-while-revalidate cache, so cached
/// responses from one test's mock server never leak into another.
/// The year filters are data driven; tests get a fixed list (as if the server reported data for
/// 2024-2026) so they do not depend on the machine's clock.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  setUp(BackendHttp.cache.clear);
  setUp(() => AvailableYears.setForTest(const YearOptions(years: [2026, 2025, 2024], defaultYear: 2026)));
  await testMain();
}
