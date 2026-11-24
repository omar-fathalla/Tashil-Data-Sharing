import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_web_plugins/url_strategy.dart';

import 'features/auth/presentation/mockup/login_mockup_app.dart';
import 'features/auth/presentation/mockup/login_mockup_variant.dart';
import 'main.dart';

/// Owner-review entrypoint for the desktop login mockups.
///
/// Run with `flutter run -d web-server -t lib/login_mockup_main.dart`.
/// Choose a layout with `?variant=a`, `?variant=b`, or `?variant=c`.
/// Arabic RTL: add `&lang=ar`. This file is not the production app.
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  if (kIsWeb) {
    usePathUrlStrategy();
  }
  final params = Uri.base.queryParameters;
  final variant = LoginMockupVariant.parse(params['variant']);
  final lang = (params['lang'] ?? params['locale'] ?? '').toLowerCase();
  if (lang == 'ar' || lang == 'arabic') {
    appLocaleNotifier.value = const Locale('ar');
  }
  runApp(LoginMockupApp(variant: variant));
}
