import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:tashil_web/features/auth/presentation/mockup/login_mockup_app.dart';
import 'package:tashil_web/features/auth/presentation/mockup/login_mockup_variant.dart';
import 'package:tashil_web/main.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = false;

  Future<void> pumpVariant(
    WidgetTester tester,
    LoginMockupVariant variant, {
    Size size = const Size(1440, 900),
    Locale locale = const Locale('en'),
  }) async {
    appLocaleNotifier.value = locale;
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(LoginMockupApp(variant: variant));
    await tester.pumpAndSettle();
  }

  testWidgets('variant A keeps login fields and drops the D tile', (tester) async {
    await pumpVariant(tester, LoginMockupVariant.a);
    expect(find.text('Tashil'), findsWidgets);
    expect(find.text('Data Sharing Platform'), findsOneWidget);
    expect(find.text('Login'), findsWidgets);
    expect(find.text('user@example.com'), findsOneWidget);
    expect(find.text('Remember Me'), findsOneWidget);
    expect(find.text('Forgot Password?'), findsOneWidget);
    expect(find.text('Contact the following number'), findsOneWidget);
    expect(find.text('01211857725'), findsOneWidget);
    expect(find.text('العربية'), findsOneWidget);
    expect(find.text('D'), findsNothing);
  });

  testWidgets('variants B and C render the same controls', (tester) async {
    for (final variant in [LoginMockupVariant.b, LoginMockupVariant.c]) {
      await pumpVariant(tester, variant);
      expect(find.text('Data Sharing Platform'), findsOneWidget);
      expect(find.text('user@example.com'), findsOneWidget);
      expect(find.text('Forgot Password?'), findsOneWidget);
      expect(find.byIcon(Icons.visibility_off_rounded), findsOneWidget);
    }
  });

  testWidgets('variant C lists the three product highlights', (tester) async {
    await pumpVariant(tester, LoginMockupVariant.c);
    expect(find.text('Sell-In / Sell-Out analytics'), findsOneWidget);
    expect(find.text('Smart Excel ingestion'), findsOneWidget);
    expect(find.text('Chain pricing'), findsOneWidget);
  });

  testWidgets('language toggle switches variant A to Arabic RTL', (tester) async {
    await pumpVariant(tester, LoginMockupVariant.a);
    await tester.tap(find.text('العربية'));
    await tester.pumpAndSettle();
    expect(find.text('تسجيل الدخول'), findsWidgets);
    expect(find.text('منصة مشاركة البيانات'), findsOneWidget);
    expect(find.text('تذكرني'), findsOneWidget);
    final direction = Directionality.of(tester.element(find.text('تسجيل الدخول').first));
    expect(direction, TextDirection.rtl);
  });

  testWidgets('password visibility toggles and empty password blocks login', (tester) async {
    await pumpVariant(tester, LoginMockupVariant.b);
    await tester.tap(find.byIcon(Icons.visibility_off_rounded));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.visibility_rounded), findsOneWidget);

    await tester.tap(find.text('Remember Me'));
    await tester.pumpAndSettle();
    final checkbox = tester.widget<Checkbox>(find.byType(Checkbox));
    expect(checkbox.value, isTrue);

    await tester.tap(find.widgetWithText(FilledButton, 'Login'));
    await tester.pumpAndSettle();
    expect(find.text('Please enter password'), findsOneWidget);
  });

  testWidgets('forgot password opens the recovery dialog', (tester) async {
    await pumpVariant(tester, LoginMockupVariant.a);
    await tester.tap(find.text('Forgot Password?'));
    await tester.pumpAndSettle();
    expect(find.text('Password recovery'), findsOneWidget);
    expect(
      find.text('Contact your administrator to reset your password'),
      findsOneWidget,
    );
  });

  testWidgets('narrow widths keep a single column without overflow', (tester) async {
    for (final variant in LoginMockupVariant.values) {
      await pumpVariant(
        tester,
        variant,
        size: const Size(390, 844),
      );
      final exception = tester.takeException();
      expect(exception, isNull, reason: '$variant');
      expect(find.text('user@example.com'), findsOneWidget, reason: '$variant');
      final emailTop = tester.getTopLeft(find.text('user@example.com')).dy;
      expect(emailTop, lessThan(700), reason: '$variant email at $emailTop');
      final phone = tester.getRect(find.text('01211857725'));
      expect(phone.bottom, lessThan(844), reason: '$variant phone bottom ${phone.bottom}');
    }
  });

  test('query variant parser', () {
    expect(LoginMockupVariant.parse(null), LoginMockupVariant.a);
    expect(LoginMockupVariant.parse('b'), LoginMockupVariant.b);
    expect(LoginMockupVariant.parse('C'), LoginMockupVariant.c);
    expect(LoginMockupVariant.parse('nope'), LoginMockupVariant.a);
  });
}
