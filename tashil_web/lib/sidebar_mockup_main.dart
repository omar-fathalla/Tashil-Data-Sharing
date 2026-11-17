// MOCKUP ONLY. Not wired into the production router.
//
// Review the three sidebar groupings in a browser:
//   flutter run -d chrome -t lib/sidebar_mockup_main.dart --dart-define=APP_VERSION=187
//   ?variant=a | b | c | a-collapsed
//
// Does not deploy, and does not change DesktopSidebar / AppShell destinations.

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_web_plugins/url_strategy.dart';

import 'core/config/app_version.dart';
import 'core/theme/app_theme.dart';
import 'features/navigation/presentation/sidebar_section_mockup.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  if (kIsWeb) {
    usePathUrlStrategy();
    // Lets the review browser wait on real labels (section titles, Adeco).
    SemanticsBinding.instance.ensureSemantics();
  }
  // Footer widget is the production one. Pin a sample stamp so the review
  // frame reads "v187" instead of the local "dev" fallback.
  AppVersion.applyDeployedAppVersion('187');
  final variant = SidebarMockupVariant.parse(
    Uri.base.queryParameters['variant'],
  );
  runApp(SidebarMockupApp(variant: variant));
}

class SidebarMockupApp extends StatelessWidget {
  final SidebarMockupVariant variant;

  const SidebarMockupApp({super.key, required this.variant});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Tashil sidebar mockup',
      theme: AppTheme.light(),
      locale: const Locale('ar'),
      supportedLocales: const [Locale('ar'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: SidebarSectionMockupPage(variant: variant),
    );
  }
}
