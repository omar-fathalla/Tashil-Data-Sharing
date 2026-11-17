import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../main.dart';
import 'login_mockup_variant.dart';
import 'login_variant_a.dart';
import 'login_variant_b.dart';
import 'login_variant_c.dart';

/// Scratch app that hosts one login mockup. Not used by production `main`.
class LoginMockupApp extends StatelessWidget {
  const LoginMockupApp({super.key, required this.variant});

  final LoginMockupVariant variant;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Locale>(
      valueListenable: appLocaleNotifier,
      builder: (context, locale, _) {
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          title: 'Tashil Data Sharing',
          themeMode: ThemeMode.light,
          theme: AppTheme.light(),
          scrollBehavior: const AppScrollBehavior(),
          locale: locale,
          supportedLocales: const [
            Locale('en'),
            Locale('ar'),
          ],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: switch (variant) {
            LoginMockupVariant.a => const LoginVariantA(),
            LoginMockupVariant.b => const LoginVariantB(),
            LoginMockupVariant.c => const LoginVariantC(),
          },
        );
      },
    );
  }
}
