import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:tashil_web/core/storage/session_storage.dart';
import 'package:tashil_web/features/auth/presentation/screens/tenant_login_screen.dart';
import 'package:tashil_web/features/navigation/app_page_route.dart';
import 'package:tashil_web/main.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = false;

  setUp(() {
    SessionStorage.clearAll();
    appLocaleNotifier.value = const Locale('en');
  });

  test('isBareRoot recognizes site root paths', () {
    expect(AppPageRoute.isBareRoot('/'), isTrue);
    expect(AppPageRoute.isBareRoot(''), isTrue);
    expect(AppPageRoute.isBareRoot('/index.html'), isTrue);
    expect(AppPageRoute.isBareRoot(' / '), isTrue);
    expect(AppPageRoute.isBareRoot('/adeco'), isFalse);
    expect(AppPageRoute.isBareRoot('/adeco/sell-in'), isFalse);
    expect(AppPageRoute.isBareRoot('/admin'), isFalse);
  });

  testWidgets(
      'bare root (no session) shows company login, never a blank body',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    // Non-web tests see an empty Uri.base.path — same bare-root branch as `/`.
    await tester.pumpWidget(const TashilDataSharingApp());
    await tester.pumpAndSettle();

    expect(find.byType(TenantLoginScreen), findsOneWidget);
    expect(find.text('Login'), findsWidgets);
    // Must not be an empty MaterialApp / missing home route.
    expect(tester.takeException(), isNull);
    expect(find.byType(Scaffold), findsWidgets);
  });
}
