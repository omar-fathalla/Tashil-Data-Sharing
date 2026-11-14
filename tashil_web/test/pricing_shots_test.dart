import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tashil_web/core/data/app_cache.dart';
import 'package:tashil_web/features/pricing_compliance/presentation/screens/pricing_compliance_screen.dart';

import 'pricing_m3_support.dart';

/// Writes PNG shots when PRICING_SHOT_DIR is set. Skipped otherwise so the
/// regular suite never writes files.
void main() {
  final dir = Platform.environment['PRICING_SHOT_DIR'];
  if (dir == null || dir.isEmpty) {
    test('shot capture skipped (no PRICING_SHOT_DIR)', () {});
    return;
  }

  // Keep runtime fetching as a fallback; loadPricingFonts still
  // registers the bundled Cairo family for glyph metrics.
  ignoreGoogleFontLoadErrors();
  setUpAll(loadPricingFonts);
  setUp(AppCache.clear);

  for (final width in [1280.0, 1024.0]) {
    testWidgets('pricing shots at ${width.toInt()}', (tester) async {
      final api = PricingShotApiClient();
      await pumpPricing(
        tester,
        PricingComplianceScreen(apiClient: api),
        width: width,
        height: 2800,
      );
      await saveShot(tester, '$dir/pricing-${width.toInt()}-main.png');

      final impact = find.text('أثر الأسعار');
      expect(impact, findsOneWidget);
      await tester.tap(impact);
      await tester.pumpAndSettle();
      await saveShot(tester, '$dir/pricing-${width.toInt()}-impact.png');
    });
  }
}
