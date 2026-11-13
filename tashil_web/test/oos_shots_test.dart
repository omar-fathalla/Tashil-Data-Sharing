import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tashil_web/core/data/app_cache.dart';
import 'package:tashil_web/features/oos_monitor/presentation/screens/oos_dashboard_screen.dart';

import 'oos_m3_support.dart';

/// Writes PNG shots when OOS_SHOT_DIR is set. Skipped otherwise so the
/// regular suite never writes files.
void main() {
  final dir = Platform.environment['OOS_SHOT_DIR'];
  if (dir == null || dir.isEmpty) {
    test('shot capture skipped (no OOS_SHOT_DIR)', () {});
    return;
  }

  ignoreGoogleFontLoadErrors();
  setUpAll(loadOosFonts);
  setUp(AppCache.clear);

  for (final width in [1280.0, 1024.0]) {
    testWidgets('oos shots at ${width.toInt()}', (tester) async {
      final api = OosShotApiClient();
      await pumpOos(
        tester,
        OOSDashboardScreen(apiClient: api),
        width: width,
        height: 3600,
      );
      await saveOosShot(tester, '$dir/oos-${width.toInt()}-alerts.png');

      final matrix = find.text('مصفوفة الفروع والنواقص');
      expect(matrix, findsOneWidget);
      await tester.tap(matrix);
      await tester.pumpAndSettle();
      await saveOosShot(tester, '$dir/oos-${width.toInt()}-matrix.png');
    });
  }
}
