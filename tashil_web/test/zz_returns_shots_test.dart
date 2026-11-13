// Writes PNGs when TASHIL_SHOTS_DIR is set. Made-up fixture data only.
// One toImage() per test — capturing the same boundary twice can hang the tester.
import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:tashil_web/core/data/available_years.dart';
import 'package:tashil_web/core/network/api_client.dart';
import 'package:tashil_web/core/theme/app_theme.dart';
import 'package:tashil_web/features/sell_in_returns/presentation/screens/sell_in_returns_screen.dart';

import 'support/real_fonts.dart';
import 'support/returns_fixture.dart';

Future<void> _pump(WidgetTester tester, double width) async {
  tester.view.physicalSize = Size(width, 2800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  AvailableYears.setForTest(
      const YearOptions(years: [2026], defaultYear: 2026));
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(),
      locale: const Locale('ar'),
      supportedLocales: const [Locale('ar'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          body: RepaintBoundary(
            key: const ValueKey('returns-shot-root'),
            child: SellInReturnsScreen(
              apiClient: ApiClient(),
              repository: ReturnsFakeRepo(),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump(const Duration(milliseconds: 400));
}

Future<void> _savePage(WidgetTester tester, String path) async {
  final dir = Directory(File(path).parent.path);
  if (!dir.existsSync()) dir.createSync(recursive: true);
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(const ValueKey('returns-shot-root')),
  );
  final image = await boundary.toImage(pixelRatio: 1.0);
  final bytes = await image.toByteData(format: ImageByteFormat.png);
  File(path).writeAsBytesSync(bytes!.buffer.asUint8List());
}

void main() {
  final out = Platform.environment['TASHIL_SHOTS_DIR'];
  if (out == null || out.isEmpty) {
    test('shots skipped (set TASHIL_SHOTS_DIR to capture)', () {});
    return;
  }

  GoogleFonts.config.allowRuntimeFetching = false;
  setUpAll(loadRealCairoFont);

  for (final width in const [1280.0, 1024.0]) {
    testWidgets('returns page @$width', (tester) async {
      await _pump(tester, width);
      await _savePage(tester, '$out/page-${width.toInt()}.png');
    });
  }
}
