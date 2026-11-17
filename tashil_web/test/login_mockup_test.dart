import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:tashil_web/features/auth/presentation/mockups/login_mockup_kit.dart';
import 'package:tashil_web/features/auth/presentation/mockups/login_mockup_variants.dart';
import 'package:tashil_web/login_mockup_main.dart';

import 'errors_m3_support.dart';
import 'support/real_fonts.dart';

const _sizes = <Size>[
  Size(1440, 900),
  Size(1280, 800),
  Size(1024, 768),
  Size(720, 1024),
  Size(390, 844),
];

Future<void> _pump(
  WidgetTester tester,
  LoginMockupVariant variant,
  Size size, {
  String lang = 'ar',
  bool showError = false,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(LoginMockupApp(
    variant: variant,
    initialLocale: Locale(lang),
    showError: showError,
  ));
  await tester.pumpAndSettle();
}

void main() {
  ignoreGoogleFontLoadErrors();
  setUpAll(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    await loadRealCairoFont();
  });

  for (final variant in LoginMockupVariant.values) {
    for (final size in _sizes) {
      for (final lang in ['ar', 'en']) {
        final name = '${variant.name} ${size.width.toInt()}x'
            '${size.height.toInt()} $lang';
        testWidgets('$name lays out without overflow', (tester) async {
          await _pump(tester, variant, size, lang: lang);
          expect(tester.takeException(), isNull);

          final form = find.byType(LoginMockupForm);
          expect(form, findsOneWidget);
          final formWidth = tester.getSize(form).width;
          expect(formWidth, lessThanOrEqualTo(440.0));
          if (size.width >= 600) expect(formWidth, greaterThanOrEqualTo(336.0));

          expect(find.byType(LoginFeatureIcon), findsNWidgets(7));
          expect(find.text('D'), findsNothing);
          expect(find.text('Tashil'), findsWidgets);

          // 40dp container inside the padded 48dp tap target.
          final submit = tester.getSize(find
              .descendant(
                of: find.byKey(const ValueKey('login_submit')),
                matching: find.byType(Material),
              )
              .first);
          expect(submit.height, 40.0);
          expect(submit.width, formWidth);

          // Language switch sits at the top end: left in RTL, right in LTR.
          final lang0 = tester.getCenter(
              find.byKey(const ValueKey('login_language_button')));
          if (lang == 'ar') {
            expect(lang0.dx, lessThan(size.width / 2));
          } else {
            expect(lang0.dx, greaterThan(size.width / 2));
          }
        });
      }
    }
  }

  testWidgets('A: brand pane is at the start (right in RTL), 7:5 on large',
      (tester) async {
    await _pump(tester, LoginMockupVariant.a, const Size(1440, 900));
    final brand = tester.getRect(find.byKey(const ValueKey('login_brand_pane')));
    expect(brand.right, 1440.0);
    expect(brand.width, closeTo(1440 * 7 / 12, 1.0));
  });

  testWidgets('A: 1:1 split on expanded, LTR puts brand on the left',
      (tester) async {
    await _pump(tester, LoginMockupVariant.a, const Size(1024, 768), lang: 'en');
    final brand = tester.getRect(find.byKey(const ValueKey('login_brand_pane')));
    expect(brand.left, 0.0);
    expect(brand.width, closeTo(512, 1.0));
  });

  testWidgets('compact: features come after the form', (tester) async {
    await _pump(tester, LoginMockupVariant.a, const Size(390, 844));
    final formBottom = tester.getRect(find.byType(LoginMockupForm)).bottom;
    final firstFeature = tester.getRect(find.byType(LoginFeatureIcon).first).top;
    expect(firstFeature, greaterThan(formBottom));
  });

  testWidgets('language switch flips locale and direction', (tester) async {
    await _pump(tester, LoginMockupVariant.c, const Size(1440, 900));
    expect(find.text('تسجيل الدخول'), findsWidgets);
    final ctx = tester.element(find.byType(LoginMockupForm));
    expect(Directionality.of(ctx), TextDirection.rtl);

    await tester.tap(find.byKey(const ValueKey('login_language_button')));
    await tester.pumpAndSettle();
    expect(find.text('Sign in'), findsWidgets);
    final ctx2 = tester.element(find.byType(LoginMockupForm));
    expect(Directionality.of(ctx2), TextDirection.ltr);
  });

  testWidgets('empty submit validates inline; button stays enabled',
      (tester) async {
    await _pump(tester, LoginMockupVariant.c, const Size(1440, 900));
    final button = tester.widget<FilledButton>(
        find.byKey(const ValueKey('login_submit')));
    expect(button.onPressed, isNotNull);
    await tester.tap(find.byKey(const ValueKey('login_submit')));
    await tester.pumpAndSettle();
    expect(find.text('أدخل البريد الإلكتروني'), findsOneWidget);
    expect(find.text('أدخل كلمة المرور'), findsOneWidget);
    expect(find.byKey(const ValueKey('login_error_banner')), findsNothing);
  });

  testWidgets('failed sign-in shows the errorContainer banner and keeps label',
      (tester) async {
    await _pump(tester, LoginMockupVariant.a, const Size(1440, 900));
    await tester.enterText(
        find.byKey(const ValueKey('login_email')), 'user@example.com');
    await tester.enterText(
        find.byKey(const ValueKey('login_password')), 'secret');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('login_submit')),
        matching: find.text('تسجيل الدخول'),
      ),
      findsOneWidget,
    );
    await tester.pumpAndSettle(const Duration(seconds: 2));
    final banner = find.byKey(const ValueKey('login_error_banner'));
    expect(banner, findsOneWidget);
    final box = tester.widget<DecoratedBox>(banner).decoration as BoxDecoration;
    final cs = Theme.of(tester.element(banner)).colorScheme;
    expect(box.color, cs.errorContainer);
    expect(
      tester.getRect(banner).bottom,
      lessThan(tester.getRect(find.byKey(const ValueKey('login_submit'))).top),
    );
  });

  testWidgets('password toggle has the Arabic tooltip; remember me is 48dp',
      (tester) async {
    await _pump(tester, LoginMockupVariant.b, const Size(1440, 900));
    final toggle = tester.widget<IconButton>(
        find.byKey(const ValueKey('login_password_visibility')));
    expect(toggle.tooltip, 'إظهار كلمة المرور');
    expect(
      tester.getSize(find.byKey(const ValueKey('login_remember_me'))).height,
      greaterThanOrEqualTo(48.0),
    );
    final field = tester.getSize(find.byKey(const ValueKey('login_email')));
    expect(field.height, greaterThanOrEqualTo(56.0));
  });

  testWidgets('B: preview is labelled and the card overlaps the hero edge',
      (tester) async {
    await _pump(tester, LoginMockupVariant.b, const Size(1440, 900));
    expect(find.bySemanticsLabel('معاينة لوحة التحليلات'), findsOneWidget);
    final band = tester.getRect(find.byKey(const ValueKey('login_hero_band')));
    final card = tester.getRect(find.byKey(const ValueKey('login_form_card')));
    final preview =
        tester.getRect(find.byKey(const ValueKey('login_dashboard_preview')));
    expect(card.top, lessThan(band.bottom));
    expect(card.bottom, greaterThan(band.bottom));
    expect(card.width, 400.0);
    expect(card.overlaps(preview), isFalse);
    expect(card.left, lessThan(preview.left)); // end side in RTL
  });

  testWidgets('C: centred 440dp card on surfaceContainer', (tester) async {
    await _pump(tester, LoginMockupVariant.c, const Size(1440, 900));
    final card = tester.getRect(find.byKey(const ValueKey('login_form_card')));
    expect(card.width, 440.0);
    expect(card.center.dx, closeTo(720, 1.0));
  });
}
