import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tashil_web/core/data/app_cache.dart';
import 'package:tashil_web/features/sell_out_analytics/presentation/screens/sell_out_explorer_screen.dart';
import 'package:tashil_web/core/network/api_client.dart';

import 'support/live_viewport.dart';
import 'support/product_master_m3_support.dart';

/// Writes PNG shots when PRODUCT_MASTER_SHOT_DIR is set.
void main() {
  final dir = Platform.environment['PRODUCT_MASTER_SHOT_DIR'];
  if (dir == null || dir.isEmpty) {
    test('shot capture skipped (no PRODUCT_MASTER_SHOT_DIR)', () {});
    return;
  }

  ignoreGoogleFontLoadErrors();
  setUpAll(loadProductMasterFonts);
  setUp(AppCache.clear);

  testWidgets('product master live-shell shots', (tester) async {
    await pumpProductMaster(
      tester,
      width: kLiveViewportWidth,
      height: 2200,
      withSidebar: true,
    );
    await saveProductMasterShot(tester, '$dir/01-catalog-1280-sidebar.png');

    final calc = find.textContaining('حاسبة الطلبيات');
    if (calc.evaluate().isNotEmpty) {
      await tester.tap(calc.first);
      await tester.pumpAndSettle();
      await saveProductMasterShot(
          tester, '$dir/02-calculator-1280-sidebar.png');
    }

    final sheets = find.textContaining('الشيتات');
    if (sheets.evaluate().isNotEmpty) {
      await tester.tap(sheets.first);
      await tester.pumpAndSettle();
      await saveProductMasterShot(tester, '$dir/03-sheets-1280-sidebar.png');
    }
  });

  testWidgets('product master 1024 shots', (tester) async {
    await pumpProductMaster(
      tester,
      width: 1024,
      height: 2200,
      withSidebar: true,
    );
    await saveProductMasterShot(tester, '$dir/04-catalog-1024-sidebar.png');
  });

  testWidgets('sell-out KPI baseline at live shell', (tester) async {
    await pumpProductMaster(
      tester,
      width: kLiveViewportWidth,
      height: 1600,
      withSidebar: true,
      page: SellOutExplorerScreen(apiClient: ApiClient()),
    );
    await saveProductMasterShot(tester, '$dir/00-sellout-kpi-baseline.png');
  });
}
