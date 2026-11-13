import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tashil_web/features/data_quality/presentation/screens/data_quality_screen.dart';

import 'errors_m3_support.dart';

/// Writes PNG shots when ERRORS_SHOT_DIR is set. Skipped otherwise so the
/// regular suite never writes files.
void main() {
  final dir = Platform.environment['ERRORS_SHOT_DIR'];
  if (dir == null || dir.isEmpty) {
    test('shot capture skipped (no ERRORS_SHOT_DIR)', () {});
    return;
  }

  ignoreGoogleFontLoadErrors();
  setUpAll(loadErrorsFonts);

  for (final width in [1280.0, 1024.0]) {
    testWidgets('errors shots at ${width.toInt()}', (tester) async {
      await pumpErrors(
        tester,
        DataQualityScreen(
          dataSource: ErrorsShotSource(),
          pollInterval: const Duration(hours: 1),
        ),
        width: width,
        height: 3600,
      );
      await saveErrorsShot(tester, '$dir/errors-${width.toInt()}.png');
    });
  }
}
