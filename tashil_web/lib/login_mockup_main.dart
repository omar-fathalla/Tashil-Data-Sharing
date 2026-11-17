// MOCKUP ONLY. Not wired into the production router.
//
// Review the three login page layouts in a browser:
//   flutter run -d chrome -t lib/login_mockup_main.dart
//   ?variant=a | b | c   &lang=ar | en   &state=error
//
// Does not deploy, and does not change TenantLoginScreen.

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_web_plugins/url_strategy.dart';

import 'core/theme/app_theme.dart';
import 'features/auth/presentation/mockups/login_mockup_kit.dart';
import 'features/auth/presentation/mockups/login_mockup_variants.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  if (kIsWeb) usePathUrlStrategy();
  final q = Uri.base.queryParameters;
  runApp(LoginMockupApp(
    variant: LoginMockupVariant.parse(q['variant']),
    initialLocale: Locale(q['lang'] == 'en' ? 'en' : 'ar'),
    showError: q['state'] == 'error',
  ));
}

class LoginMockupApp extends StatefulWidget {
  final LoginMockupVariant variant;
  final Locale initialLocale;
  final bool showError;

  const LoginMockupApp({
    super.key,
    required this.variant,
    this.initialLocale = const Locale('ar'),
    this.showError = false,
  });

  @override
  State<LoginMockupApp> createState() => _LoginMockupAppState();
}

class _LoginMockupAppState extends State<LoginMockupApp> {
  late Locale _locale = widget.initialLocale;

  void _toggleLocale() => setState(() {
        _locale = _locale.languageCode == 'ar'
            ? const Locale('en')
            : const Locale('ar');
      });

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Tashil login mockup',
      theme: AppTheme.light(),
      locale: _locale,
      supportedLocales: const [Locale('ar'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: LoginMockupPage(
        variant: widget.variant,
        onToggleLocale: _toggleLocale,
        showError: widget.showError,
      ),
    );
  }
}

class LoginMockupPage extends StatelessWidget {
  final LoginMockupVariant variant;
  final VoidCallback onToggleLocale;
  final bool showError;

  const LoginMockupPage({
    super.key,
    required this.variant,
    required this.onToggleLocale,
    this.showError = false,
  });

  @override
  Widget build(BuildContext context) {
    final actions = LoginMockupActions(
      onToggleLocale: onToggleLocale,
      initialError: showError
          ? loginTr(
              context,
              'البريد الإلكتروني أو كلمة المرور غير صحيحة.',
              'The email or password is incorrect.',
            )
          : null,
      onSubmit: (email, password, rememberMe) async {
        await Future<void>.delayed(const Duration(milliseconds: 1200));
        if (!context.mounted) return;
        throw Exception(loginTr(
          context,
          'نسخة تجريبية للعرض فقط: لم يتم إرسال أي بيانات.',
          'Mockup only: nothing was sent.',
        ));
      },
      onForgotPassword: () => ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(loginTr(
            context,
            'في التطبيق يفتح هذا نافذة استعادة كلمة المرور.',
            'In the app this opens the password reset dialog.',
          )),
        ),
      ),
    );

    return Scaffold(
      body: SafeArea(
        child: LoginFocusOrder(
          child: switch (variant) {
            LoginMockupVariant.a => LoginVariantA(actions: actions),
            LoginMockupVariant.b => LoginVariantB(actions: actions),
            LoginMockupVariant.c => LoginVariantC(actions: actions),
          },
        ),
      ),
    );
  }
}
