// Writes PNGs when TASHIL_SHOTS_DIR is set. Made-up fixture data only.
// One toImage() per test — capturing the same boundary twice can hang the tester.
import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:tashil_web/core/data/app_cache.dart';
import 'package:tashil_web/core/network/api_client.dart';
import 'package:tashil_web/core/theme/app_theme.dart';
import 'package:tashil_web/features/sell_out_analytics/presentation/screens/sell_in_explorer_screen.dart';

import 'oos_m3_support.dart';
import 'support/sell_in_waterfall_fixture.dart';

const _sidebarWidth = 250.0;

class _DemoApi extends ApiClient {
  _DemoApi(this.response) : super(tenantId: 'tenant-adeco');
  final SellInExplorerResponse response;

  @override
  Future<SellInExplorerResponse> getSellInRecords({
    String? chain,
    int? year,
    int? month,
    String? region,
    String? sector,
    String? brand,
    String? query,
    int limit = 250,
    int offset = 0,
  }) async =>
      response;
}

Future<void> _pump(WidgetTester tester, double width, double height, SellInExplorerResponse data) async {
  tester.view.physicalSize = Size(width, height);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(MaterialApp(
    theme: AppTheme.light(),
    locale: const Locale('ar'),
    supportedLocales: const [Locale('ar'), Locale('en')],
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    home: Directionality(
      textDirection: TextDirection.rtl,
      child: RepaintBoundary(
        key: const ValueKey('sellin-shot-root'),
        child: Builder(builder: (context) {
          final cs = Theme.of(context).colorScheme;
          return Scaffold(
            body: Column(children: [
              Container(
                width: double.infinity,
                color: cs.tertiaryContainer,
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Text('بيانات تجريبية للعرض فقط — ليست بيانات العميل',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(color: cs.onTertiaryContainer)),
              ),
              Expanded(
                child: Row(children: [
                  Container(width: _sidebarWidth, color: cs.surfaceContainer),
                  Expanded(child: SellInExplorerScreen(apiClient: _DemoApi(data))),
                ]),
              ),
            ]),
          );
        }),
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

Future<void> _save(WidgetTester tester, String path) async {
  Directory(File(path).parent.path).createSync(recursive: true);
  final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(const ValueKey('sellin-shot-root')));
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1.0);
    final bytes = await image.toByteData(format: ImageByteFormat.png);
    File(path).writeAsBytesSync(bytes!.buffer.asUint8List());
  });
}

void main() {
  final out = Platform.environment['TASHIL_SHOTS_DIR'];
  if (out == null || out.isEmpty) {
    test('shots skipped (set TASHIL_SHOTS_DIR to capture)', () {});
    return;
  }

  GoogleFonts.config.allowRuntimeFetching = false;
  ignoreGoogleFontLoadErrors();
  setUpAll(() async {
    await loadOosFonts();
    final icons = File(
        '${Platform.environment['FLUTTER_ROOT'] ?? '/opt/flutter'}/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf');
    if (icons.existsSync()) {
      final data = ByteData.view(Uint8List.fromList(icons.readAsBytesSync()).buffer);
      await (FontLoader('MaterialIcons')..addFont(Future.value(data))).load();
    }
  });
  setUp(AppCache.clear);

  for (final width in const [1280.0, 1440.0]) {
    testWidgets('all chains @$width', (tester) async {
      await _pump(tester, width, 1000, demoWaterfallResponse(demoAllChains));
      await _save(tester, '$out/sell-in-waterfall-all-chains-${width.toInt()}.png');
    });
    testWidgets('one chain @$width', (tester) async {
      await _pump(tester, width, 1000, demoWaterfallResponse(demoFathalla));
      await _save(tester, '$out/sell-in-waterfall-fathalla-${width.toInt()}.png');
    });
  }

  testWidgets('product table @1440', (tester) async {
    await _pump(
        tester,
        1440,
        1800,
        demoWaterfallResponse(const [
          // Totals of `demoRecords`: Fathalla 4 priced cartons (expected 342, actual 360.50) + 1 unpriced (50).
          DemoChain('fathalla', 400, extraPct: 5, saved: true, execution: -18.5, unpriced: 50),
          DemoChain('gomla', 100),
        ], records: demoRecords, cases: 6, units: 60));
    await _save(tester, '$out/sell-in-product-table-1440.png');
  });
}
