import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:tashil_web/core/network/api_client.dart';
import 'package:tashil_web/core/storage/session_storage.dart';
import 'package:tashil_web/core/theme/app_theme.dart';
import 'package:tashil_web/core/theme/m3_color_roles.dart';
import 'package:tashil_web/features/auth/presentation/screens/super_admin_login_screen.dart';
import 'package:tashil_web/features/auth/presentation/screens/tenant_login_screen.dart';
import 'package:tashil_web/features/auth/presentation/widgets/forgot_password_dialog.dart';
import 'package:tashil_web/features/auth/presentation/widgets/security_guard.dart';
import 'package:tashil_web/features/auth/presentation/widgets/user_profile_dialog.dart';
import 'package:tashil_web/features/navigation/presentation/app_shell.dart';
import 'package:tashil_web/features/pricing_compliance/presentation/screens/pricing_compliance_screen.dart';
import 'package:tashil_web/features/sell_out_analytics/presentation/screens/sell_out_explorer_screen.dart';
import 'package:tashil_web/features/super_admin/presentation/screens/super_admin_screen.dart';
import 'package:tashil_web/main.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = false;

  setUp(() {
    SessionStorage.clearAll();
  });

  group('Super Admin Portal & Provisioning Wizard Tests', () {
    late ApiClient apiClient;

    setUp(() {
      apiClient = ApiClient(tenantId: 'tenant-adeco');
    });

    testWidgets('SuperAdminScreen renders company list and stats', (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(1280, 800));

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(seedColor: TenantBrandSeeds.adminSeed),
          home: SuperAdminScreen(apiClient: apiClient),
        ),
      );
      await tester.pumpAndSettle();

      // Redesigned M3 header: English title + Arabic subtitle + action group.
      expect(find.text('Super Admin Executive Portal'), findsOneWidget);
      expect(find.text('إجمالي الشركات المفعلة'), findsOneWidget);
      expect(find.text('New Company'), findsWidgets);
      expect(find.text('شركة أديكو للصناعات الغذائية (Adeco)'), findsOneWidget);
      expect(find.text('شركة يونيليفر مشرق (Unilever)'), findsOneWidget);
      expect(find.text('شركة بيبسي كولا مصر (PepsiCo)'), findsOneWidget);
    });

    testWidgets('Tenant Provisioning Wizard opens and generates portal URL & credentials', (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(1280, 800));

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(seedColor: TenantBrandSeeds.adminSeed),
          home: SuperAdminScreen(apiClient: apiClient),
        ),
      );
      await tester.pumpAndSettle();

      // Click the "New Company" header action
      await tester.tap(find.text('New Company').first);
      await tester.pumpAndSettle();

      expect(find.text('معالج إضافة شركة جديدة وتوليد الرابط'), findsOneWidget);
      expect(find.text('اسم المؤسسة / الشركة *'), findsOneWidget);

      // Enter company name
      await tester.enterText(find.widgetWithText(TextFormField, 'اسم المؤسسة / الشركة *'), 'شركة جهينة');
      await tester.enterText(find.widgetWithText(TextFormField, 'معرف الرابط الفريد (Slug) *'), 'juhayna');
      await tester.enterText(find.widgetWithText(TextFormField, 'البريد الإلكتروني لمسؤول الشركة *'), 'admin@juhayna.com');
      await tester.pumpAndSettle();

      // Submit wizard form
      await tester.ensureVisible(find.text('Create Portal'));
      await tester.tap(find.text('Create Portal'));
      await tester.pumpAndSettle();

      // Expect success credential card
      expect(find.text('تم تجهيز بوابة شركة جهينة بنجاح!'), findsOneWidget);
      expect(find.text(ApiClient.buildPortalUrl('juhayna')), findsWidgets);
      expect(find.text('admin@juhayna.com'), findsWidgets);

      // Close wizard
      await tester.ensureVisible(find.text('Done'));
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
    });

    testWidgets('Admin Reset Password modal opens and generates new password', (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(1280, 800));

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(seedColor: TenantBrandSeeds.adminSeed),
          home: SuperAdminScreen(apiClient: apiClient),
        ),
      );
      await tester.pumpAndSettle();

      // Find first per-company "Reset Key" action
      final resetButtons = find.text('Reset Key');
      expect(resetButtons, findsWidgets);

      await tester.ensureVisible(resetButtons.first);
      await tester.pumpAndSettle();
      await tester.tap(resetButtons.first);
      await tester.pumpAndSettle();

      expect(find.textContaining('إعادة تعيين كلمة المرور:'), findsOneWidget);
      expect(find.text('Generate Key'), findsOneWidget);

      await tester.tap(find.text('Generate Key'));
      await tester.pumpAndSettle();

      expect(find.text('كلمة المرور الجديدة:'), findsOneWidget);
    });
  });

  group('Dedicated Tenant Portal Login & Password Management Tests', () {
    late ApiClient apiClient;

    setUp(() {
      apiClient = ApiClient(tenantId: 'tenant-adeco');
    });

    testWidgets('TenantLoginScreen renders unified Tashil branding and login controls', (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(1280, 800));
      appLocaleNotifier.value = const Locale('en');

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(seedColor: TenantBrandSeeds.adecoSeed),
          home: TenantLoginScreen(
            apiClient: apiClient,
            tenantSlug: 'adeco',
            onLoginSuccess: (_) {},
            onNavigateToAdmin: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Tashil'), findsOneWidget);
      expect(find.text('Data Sharing'), findsOneWidget);
      expect(find.text('Welcome back, please enter your details'), findsOneWidget);
      expect(find.text('Email'), findsOneWidget);
      expect(find.text('Password'), findsOneWidget);
      expect(find.text('Remember Me'), findsOneWidget);
      expect(find.text('Forgot Password?'), findsOneWidget);
      expect(find.text('Login'), findsWidgets);
      expect(find.text("Don't have an account?"), findsOneWidget);
      expect(find.text('01211857725'), findsOneWidget);
    });

    testWidgets('ForgotPasswordDialog shows contact-admin note (no self-serve token)', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: Scaffold(
              body: ForgotPasswordDialog(
                apiClient: apiClient,
                tenantSlug: 'adeco',
                initialEmail: 'admin@adeco-retail.com',
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('استعادة كلمة المرور'), findsOneWidget);
      expect(find.text(ForgotPasswordDialog.contactAdminMessageAr), findsOneWidget);
      expect(find.text('إرسال الرمز'), findsNothing);
      expect(find.text('رمز التحقق (Reset Token)'), findsNothing);
    });

    testWidgets('UserProfileDialog renders account details and password change form', (WidgetTester tester) async {
      apiClient.currentUser = TenantUserModel(
        userId: 'user-adeco-admin-01',
        tenantId: 'adeco',
        email: 'admin@adeco-retail.com',
        fullName: 'أحمد المنشاوي',
        role: 'vendor_admin',
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: UserProfileDialog(
              apiClient: apiClient,
              tenantSlug: 'adeco',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('أحمد المنشاوي'), findsWidgets);
      expect(find.text('admin@adeco-retail.com'), findsOneWidget);
      expect(find.text('Password'), findsOneWidget);

      await tester.tap(find.text('Password'));
      await tester.pumpAndSettle();

      expect(find.text('Current Password'), findsOneWidget);
      expect(find.text('New Password (min. 8 characters)'), findsOneWidget);
      expect(find.text('Confirm New Password'), findsOneWidget);
    });
  });

  group('Zero Cross-Tenant Leakage & Security Guard Tests', () {
    late ApiClient apiClient;

    setUp(() {
      apiClient = ApiClient(tenantId: 'tenant-adeco');
    });

    testWidgets('SecurityGuard blocks Adeco user from accessing Unilever portal', (WidgetTester tester) async {
      apiClient.currentUser = TenantUserModel(
        userId: 'user-adeco-01',
        tenantId: 'adeco',
        email: 'admin@adeco.com',
        fullName: 'Adeco Admin',
        role: 'vendor_admin',
      );

      String? redirectedSlug;

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: TenantSecurityGuard(
            apiClient: apiClient,
            activePortalSlug: 'unilever', // Cross-tenant attempt!
            onRedirectToAuthorizedPortal: (slug) => redirectedSlug = slug,
            child: const Text('Confidential Unilever Dashboard Data'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Must NOT render the confidential dashboard
      expect(find.text('Confidential Unilever Dashboard Data'), findsNothing);

      // Must display RLS security breach notice
      expect(find.text('حاجز أمني صارم (RLS Breach Detected)'), findsOneWidget);
      expect(find.text('العودة إلى بوابة شركتك (adeco)'), findsOneWidget);

      // Tap return button
      await tester.tap(find.text('العودة إلى بوابة شركتك (adeco)'));
      await tester.pumpAndSettle();

      expect(redirectedSlug, 'adeco');
    });

    testWidgets('SecurityGuard allows Super Admin access across any tenant portal', (WidgetTester tester) async {
      apiClient.currentUser = TenantUserModel(
        userId: 'user-super-admin',
        tenantId: 'system',
        email: 'admin@tashil.com',
        fullName: 'Super Admin',
        role: 'super_admin',
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: TenantSecurityGuard(
            apiClient: apiClient,
            activePortalSlug: 'unilever',
            onRedirectToAuthorizedPortal: (_) {},
            child: const Text('Unilever Dashboard Data'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Unilever Dashboard Data'), findsOneWidget);
      expect(find.text('حاجز أمني صارم (RLS Breach Detected)'), findsNothing);
    });
  });

  group('Batch 1: Multi-Tenant Data Switching, Dynamic Dropdown, Super Admin Auth Gate & Session Persistence', () {
    test('ApiClient starts without a demo token and keeps isolated FMCG datasets per tenant', () async {
      final adecoClient = ApiClient(tenantId: 'tenant-adeco');
      final unileverClient = ApiClient(tenantId: 'tenant-unilever');
      final pepsiClient = ApiClient(tenantId: 'tenant-pepsi');

      // No implicit demo-*-token: a real backend JWT must come from login.
      expect(adecoClient.authToken, isEmpty);
      expect(unileverClient.authToken, isEmpty);
      expect(pepsiClient.authToken, isEmpty);

      final adecoRecs = await adecoClient.getRecords();
      final unileverRecs = await unileverClient.getRecords();
      final pepsiRecs = await pepsiClient.getRecords();

      expect(adecoRecs.first.skuName, contains('Adeco'));
      expect(unileverRecs.first.skuName, contains('Lipton'));
      expect(pepsiRecs.first.skuName, contains('Pepsi'));
    });

    testWidgets('SellOutExplorerScreen reloads data via didUpdateWidget when tenant changes', (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(1280, 800));
      final client = ApiClient(tenantId: 'tenant-adeco');

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(body: SellOutExplorerScreen(apiClient: client)),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('Adeco Extra Virgin Olive Oil'), findsOneWidget);
      expect(find.textContaining('Lipton Yellow Label Tea'), findsNothing);

      // Switch client tenant in place and rebuild
      client.tenantId = 'tenant-unilever';
      client.authToken = 'demo-unilever-token';
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(body: SellOutExplorerScreen(apiClient: client)),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('Lipton Yellow Label Tea'), findsOneWidget);
      expect(find.textContaining('Adeco Extra Virgin Olive Oil'), findsNothing);
    });

    testWidgets('Provisioned company (juhayna) renders in AppShell DropdownButton without crash', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1440, 1024);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final superClient = ApiClient(tenantId: 'system');
      superClient.currentUser = TenantUserModel(
        userId: 'user-super-admin',
        tenantId: 'system',
        email: 'superadmin@tashil.io',
        fullName: 'Super Admin',
        role: 'super_admin',
      );

      await superClient.provisionTenant(
        displayName: 'شركة جهينة للصناعات الغذائية',
        slug: 'juhayna',
        brandSeedColor: '#059669',
        adminEmail: 'admin@juhayna.com',
      );

      superClient.tenantId = 'tenant-juhayna';
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: AppShell(
            apiClient: superClient,
            activeTenant: 'juhayna',
            onTenantChanged: (_) {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Verify DropdownButton<String> renders without assertion crash and displays provisioned company name
      expect(find.textContaining('Juhayna'), findsWidgets);
    });

    testWidgets('Super Admin Login Gate blocks unauthenticated access and requires valid credentials', (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(1280, 800));
      final client = ApiClient(tenantId: 'tenant-adeco');
      LoginResultModel? authResult;

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(seedColor: TenantBrandSeeds.adminSeed),
          home: SuperAdminLoginScreen(
            apiClient: client,
            onLoginSuccess: (res) => authResult = res,
            onCancel: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Super Admin Security Gate'), findsOneWidget);
      expect(find.text('Sign In'), findsOneWidget);

      // 1. Wrong password attempt is rejected
      await tester.enterText(find.byKey(const ValueKey('super_admin_email_field')), 'superadmin@tashil.io');
      await tester.enterText(find.byKey(const ValueKey('super_admin_password_field')), 'WrongPass123!');
      await tester.tap(find.text('Sign In'));
      await tester.pumpAndSettle();

      expect(authResult, isNull);
      expect(find.textContaining('رفض الوصول'), findsWidgets);

      // 2. Without a reachable backend there is no offline/demo session:
      // even valid-looking credentials must not authenticate locally.
      await tester.enterText(find.byKey(const ValueKey('super_admin_email_field')), 'support@sw-point.com');
      await tester.enterText(find.byKey(const ValueKey('super_admin_password_field')), 'AnyPassword123!');
      await tester.tap(find.text('Sign In'));
      await tester.pumpAndSettle();

      expect(authResult, isNull);
      expect(client.authToken, isEmpty);
    });

    testWidgets('SessionStorage persists and restores authenticated session across app restarts', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1440, 1024);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      SessionStorage.saveSession(
        SavedSessionState(
          activeTenant: 'unilever',
          authToken: 'demo-unilever-token',
          currentUserJson: TenantUserModel(
            userId: 'user-unilever-admin',
            tenantId: 'unilever',
            email: 'admin@unilever-retail.com',
            fullName: 'مدير يونيليفر',
            role: 'vendor_admin',
          ).toJson(),
          showSuperAdmin: false,
          isLoginMode: false,
        ),
      );

      await tester.pumpWidget(const TashilDataSharingApp());
      await tester.pumpAndSettle();

      expect(find.textContaining('Unilever'), findsWidgets);
    });

    test('ApiClient normalizes system/admin tenant to adeco data and formats hyphenated slugs cleanly', () async {
      final sysClient = ApiClient(tenantId: 'system');
      final sysRecs = await sysClient.getRecords();
      expect(sysRecs, isNotEmpty);
      expect(sysRecs.first.skuName, contains('Adeco'));
      expect(sysRecs.first.skuName, isNot(contains('System')));

      final hyphenClient = ApiClient(tenantId: 'tenant-el-marai-egypt');
      final hyphenRecs = await hyphenClient.getRecords();
      expect(hyphenRecs, isNotEmpty);
      expect(hyphenRecs.first.skuName, contains('El Marai Egypt'));
    });

    testWidgets('PricingComplianceScreen and SellOutExplorerScreen dynamically update category filters on tenant switch', (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(1280, 800));
      final client = ApiClient(tenantId: 'tenant-adeco');

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(body: PricingComplianceScreen(apiClient: client)),
        ),
      );
      await tester.pumpAndSettle();

      // Adeco categories
      expect(find.widgetWithText(FilterChip, 'زيوت طعام'), findsOneWidget);
      expect(find.widgetWithText(FilterChip, 'مشروبات غازية'), findsNothing);

      // Switch to PepsiCo
      client.tenantId = 'tenant-pepsi';
      client.authToken = 'demo-pepsi-token';
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(body: PricingComplianceScreen(apiClient: client)),
        ),
      );
      await tester.pumpAndSettle();

      // PepsiCo categories must replace Adeco's hardcoded categories
      expect(find.widgetWithText(FilterChip, 'مشروبات غازية'), findsOneWidget);
      expect(find.widgetWithText(FilterChip, 'مقرمشات وسناكس'), findsOneWidget);
      expect(find.widgetWithText(FilterChip, 'زيوت طعام'), findsNothing);

      // Selecting a PepsiCo category FilterChip filters items properly
      await tester.tap(find.widgetWithText(FilterChip, 'مشروبات غازية'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Pepsi Cola'), findsOneWidget);
    });
  });
}

