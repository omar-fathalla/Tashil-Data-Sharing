import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:tashil_web/core/network/api_client.dart';
import 'package:tashil_web/core/testing/test_semantics.dart';
import 'package:tashil_web/core/theme/app_theme.dart';
import 'package:tashil_web/core/theme/m3_color_roles.dart';
import 'package:tashil_web/features/auth/presentation/screens/tenant_login_screen.dart';
import 'package:tashil_web/features/data_ingestion/presentation/screens/upload_portal_screen.dart';
import 'package:tashil_web/main.dart';

int countSemanticsIdentifiers(WidgetTester tester, String id) {
  final owner = tester.binding.pipelineOwner.semanticsOwner;
  final root = owner?.rootSemanticsNode;
  if (root == null) return 0;

  var count = 0;
  void walk(SemanticsNode node) {
    if (node.getSemanticsData().identifier == id) {
      count += 1;
    }
    node.visitChildren((child) {
      walk(child);
      return true;
    });
  }

  walk(root);
  return count;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = false;

  setUp(() {
    appLocaleNotifier.value = const Locale('en');
  });

  testWidgets('TenantLoginScreen exposes login Semantics identifiers',
      (tester) async {
    final handle = tester.ensureSemantics();
    try {
      await tester.binding.setSurfaceSize(const Size(1280, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(seedColor: TenantBrandSeeds.adecoSeed),
          home: TenantLoginScreen(
            apiClient: ApiClient(tenantId: 'tenant-adeco'),
            tenantSlug: 'adeco',
            onLoginSuccess: (_) {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      for (final id in TestIds.loginPageIds) {
        expect(
          countSemanticsIdentifiers(tester, id),
          greaterThanOrEqualTo(1),
          reason: 'TenantLoginScreen missing Semantics id "$id"',
        );
      }
    } finally {
      handle.dispose();
    }
  });

  testWidgets('UploadPortalScreen exposes upload-choose-file identifier',
      (tester) async {
    final handle = tester.ensureSemantics();
    try {
      await tester.binding.setSurfaceSize(const Size(1280, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: UploadPortalScreen(apiClient: ApiClient()),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        countSemanticsIdentifiers(tester, TestIds.uploadChooseFile),
        greaterThanOrEqualTo(1),
        reason: 'UploadPortalScreen missing upload-choose-file',
      );
    } finally {
      handle.dispose();
    }
  });
}
