import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'core/data/app_cache.dart';
import 'core/network/api_client.dart';
import 'core/security/zero_trust_digest.dart';
import 'core/storage/session_storage.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/m3_color_roles.dart';
import 'core/theme/m3_motion.dart';
import 'features/auth/presentation/screens/super_admin_login_screen.dart';
import 'features/auth/presentation/screens/tenant_login_screen.dart';
import 'features/auth/presentation/widgets/security_guard.dart';
import 'features/navigation/presentation/app_shell.dart';
import 'features/super_admin/presentation/screens/super_admin_screen.dart';

final ValueNotifier<Locale> appLocaleNotifier = ValueNotifier<Locale>(
  const Locale('en'),
);

void toggleAppLocale() {
  appLocaleNotifier.value = appLocaleNotifier.value.languageCode == 'ar'
      ? const Locale('en')
      : const Locale('ar');
}

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  if (kIsWeb) {
    usePathUrlStrategy();
  }
  runApp(const TashilDataSharingApp());
}

class TashilDataSharingApp extends StatefulWidget {
  const TashilDataSharingApp({super.key});

  @override
  State<TashilDataSharingApp> createState() => _TashilDataSharingAppState();
}

class _TashilDataSharingAppState extends State<TashilDataSharingApp> {
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();
  String _activeTenant = 'adeco';
  bool _isAdminMode = false;
  bool _isLoginMode = false;
  bool _isGenericCompanyPortal = true;
  late ApiClient _apiClient;

  @override
  void initState() {
    super.initState();
    ApiClient.restoreProvisionedTenantsFromStorage();
    _restoreOrInitializeSession();
  }

  void _restoreOrInitializeSession() {
    final path = kIsWeb ? Uri.base.path.toLowerCase().trim() : '';
    final fragment = kIsWeb ? Uri.base.fragment.toLowerCase().trim() : '';
    final isAdminRoute = path == '/admin' ||
        path.startsWith('/admin/') ||
        fragment == '/admin' ||
        fragment.startsWith('/admin/');

    String cleanPath = path;
    if (cleanPath.startsWith('/portal/')) {
      cleanPath = cleanPath.substring('/portal/'.length);
    } else if (cleanPath.startsWith('/')) {
      cleanPath = cleanPath.substring(1);
    }
    String candidateSlug = cleanPath.split('/').first.trim().toLowerCase();
    if (candidateSlug.isEmpty ||
        candidateSlug == 'index.html' ||
        candidateSlug == 'favicon.png') {
      String cleanFragment = fragment;
      if (cleanFragment.startsWith('/portal/')) {
        cleanFragment = cleanFragment.substring('/portal/'.length);
      } else if (cleanFragment.startsWith('/')) {
        cleanFragment = cleanFragment.substring(1);
      }
      candidateSlug = cleanFragment.split('/').first.trim().toLowerCase();
    }
    final isExplicitCompanySlug = candidateSlug.isNotEmpty &&
        candidateSlug != 'admin' &&
        candidateSlug != 'index.html' &&
        candidateSlug != 'favicon.png';

    final saved = SessionStorage.loadSession();
    final savedUser = saved?.currentUserJson != null
        ? TenantUserModel.fromJson(saved!.currentUserJson!)
        : null;
    final savedToken = saved?.authToken ?? '';

    final hasValidSuperAdminSession = savedUser != null &&
        savedUser.isSuperAdmin &&
        ZeroTrustDigest.isSuperAdminEmail(savedUser.email) &&
        ZeroTrustDigest.isVerifiedSuperAdminToken(savedToken);

    if (isAdminRoute) {
      _isGenericCompanyPortal = false;
      if (hasValidSuperAdminSession) {
        _isAdminMode = true;
        _isLoginMode = false;
        _apiClient = ApiClient(
          tenantId: 'system',
          authToken: savedToken,
        );
        _apiClient.currentUser = savedUser;
        _apiClient.currentTenantProfile =
            ApiClient.getTenantProfileBySlug(_activeTenant);
      } else {
        _isAdminMode = true;
        _isLoginMode = true;
        _apiClient = ApiClient(
          tenantId: 'system',
          authToken: '',
        );
        _apiClient.currentUser = null;
        _apiClient.currentTenantProfile =
            ApiClient.getTenantProfileBySlug('adeco');
      }
      SessionStorage.updateBrowserUrl('/admin');
      return;
    }

    // Default route: Company Portal on subdomain data.sw-point.com
    final hasValidCompanySession = savedUser != null &&
        !savedUser.isSuperAdmin &&
        savedToken.isNotEmpty;

    if (hasValidCompanySession) {
      final sessionTenant =
          ApiClient.normalizeDataTenantSlug(savedUser.tenantId);
      _activeTenant = isExplicitCompanySlug
          ? ApiClient.normalizeDataTenantSlug(candidateSlug)
          : sessionTenant;
      _isAdminMode = false;
      _isLoginMode = false;
      _isGenericCompanyPortal = false;
      _apiClient = ApiClient(
        tenantId: 'tenant-$_activeTenant',
        authToken: savedToken,
      );
      _apiClient.currentUser = savedUser;
      _apiClient.currentTenantProfile =
          ApiClient.getTenantProfileBySlug(_activeTenant);
      SessionStorage.updateBrowserUrl('/$_activeTenant');
    } else {
      // Show Company Login Portal
      _isAdminMode = false;
      _isLoginMode = true;
      if (isExplicitCompanySlug) {
        _activeTenant = ApiClient.normalizeDataTenantSlug(candidateSlug);
        _isGenericCompanyPortal = false;
        _apiClient = ApiClient(
          tenantId: 'tenant-$_activeTenant',
          authToken: '',
        );
        _apiClient.currentUser = null;
        _apiClient.currentTenantProfile =
            ApiClient.getTenantProfileBySlug(_activeTenant);
        SessionStorage.updateBrowserUrl('/$_activeTenant');
      } else {
        _activeTenant = 'adeco';
        _isGenericCompanyPortal = true;
        _apiClient = ApiClient(
          tenantId: 'company',
          authToken: '',
        );
        _apiClient.currentUser = null;
        _apiClient.currentTenantProfile =
            ApiClient.getTenantProfileBySlug('adeco');
      }
    }
  }

  void _persistSession() {
    SessionStorage.saveSession(
      SavedSessionState(
        activeTenant: _activeTenant,
        authToken: _apiClient.authToken,
        currentUserJson: _apiClient.currentUser?.toJson(),
        currentTenantProfileJson: _apiClient.currentTenantProfile?.toJson(),
        showSuperAdmin: _isAdminMode,
        isLoginMode: _isLoginMode,
      ),
    );
  }

  void _popPushedRoutes() {
    final nav = _navigatorKey.currentState;
    if (nav != null && nav.canPop()) {
      nav.popUntil((route) => route.isFirst);
    }
  }

  void _onTenantChanged(String newTenant) {
    final normalized = ApiClient.normalizeDataTenantSlug(newTenant);
    _popPushedRoutes();
    setState(() {
      _activeTenant = normalized;
      _isAdminMode = false;
      _isLoginMode = false;
      _isGenericCompanyPortal = false;
      final profile = ApiClient.getTenantProfileBySlug(_activeTenant);
      final brandEn = ApiClient.getEnglishDisplayNameForTenant(_activeTenant);
      // Preserve the real backend JWT (e.g. Super Admin) when switching portals.
      _apiClient = ApiClient(
        tenantId: 'tenant-$_activeTenant',
        authToken: _apiClient.authToken,
      );
      _apiClient.currentUser = TenantUserModel(
        userId: 'user-$_activeTenant-admin-01',
        tenantId: _activeTenant,
        email: profile.adminEmail.isNotEmpty
            ? profile.adminEmail
            : 'admin@$_activeTenant-retail.com',
        fullName: '$brandEn Admin',
        role: 'vendor_admin',
      );
      _apiClient.currentTenantProfile = profile;
      _persistSession();
      SessionStorage.updateBrowserUrl('/$normalized');
    });
  }

  void _switchToPortal(String slug) {
    _onTenantChanged(slug);
  }

  void openAdminGate() {
    _popPushedRoutes();
    setState(() {
      _isAdminMode = true;
      final isVerified = _apiClient.currentUser?.isSuperAdmin == true &&
          ZeroTrustDigest.isSuperAdminEmail(
              _apiClient.currentUser?.email ?? '') &&
          ZeroTrustDigest.isVerifiedSuperAdminToken(_apiClient.authToken);
      if (!isVerified) {
        _isLoginMode = true;
        _apiClient.authToken = '';
        _apiClient.currentUser = null;
      } else {
        _isLoginMode = false;
      }
      _persistSession();
      SessionStorage.updateBrowserUrl('/admin');
    });
  }

  void _handleSuperAdminAuthenticated(LoginResultModel res) {
    _popPushedRoutes();
    setState(() {
      _isAdminMode = true;
      _isLoginMode = false;
      _apiClient = ApiClient(
        tenantId: 'tenant-$_activeTenant',
        authToken: res.token,
      );
      _apiClient.currentUser = res.user;
      _apiClient.currentTenantProfile =
          ApiClient.getTenantProfileBySlug(_activeTenant);
      _persistSession();
      SessionStorage.updateBrowserUrl('/admin');
    });
  }

  void _handleVendorLoginSuccess(LoginResultModel res) {
    final cleanSlug = ApiClient.normalizeDataTenantSlug(
      res.tenant.slug.isNotEmpty ? res.tenant.slug : _activeTenant,
    );
    _popPushedRoutes();
    setState(() {
      _isAdminMode = res.user.isSuperAdmin;
      _isLoginMode = false;
      if (!res.user.isSuperAdmin) {
        _activeTenant = cleanSlug;
      }
      _apiClient = ApiClient(
        tenantId: res.user.isSuperAdmin ? 'system' : 'tenant-$_activeTenant',
        authToken: res.token,
      );
      _apiClient.currentUser = res.user;
      _apiClient.currentTenantProfile = res.user.isSuperAdmin
          ? ApiClient.getTenantProfileBySlug(_activeTenant)
          : res.tenant;
      _persistSession();
      if (!res.user.isSuperAdmin) {
        SessionStorage.updateBrowserUrl('/$cleanSlug');
      } else {
        SessionStorage.updateBrowserUrl('/admin');
      }
    });
  }

  void _logout() {
    AppCache.clear();
    _popPushedRoutes();
    SessionStorage.clearSession();
    setState(() {
      _isLoginMode = true;
      _isGenericCompanyPortal = true;
      _apiClient.currentUser = null;
      _apiClient.authToken = '';
      _persistSession();
      SessionStorage.updateBrowserUrl('/');
    });
  }

  Color get _currentSeed {
    if (_isAdminMode) {
      return TenantBrandSeeds.adminSeed;
    }
    return TenantBrandSeeds.getSeedForTenant(_activeTenant);
  }

  Widget _buildAdminGateOrScreen() {
    final isAuthenticatedSuperAdmin =
        _apiClient.currentUser?.isSuperAdmin == true &&
            ZeroTrustDigest.isSuperAdminEmail(
                _apiClient.currentUser?.email ?? '') &&
            ZeroTrustDigest.isVerifiedSuperAdminToken(_apiClient.authToken);

    if (!isAuthenticatedSuperAdmin) {
      return SuperAdminLoginScreen(
        key: const ValueKey('super_admin_login'),
        apiClient: _apiClient,
        onLoginSuccess: _handleSuperAdminAuthenticated,
        onCancel: () {
          _popPushedRoutes();
          setState(() {
            _isAdminMode = false;
            _isLoginMode = true;
            _isGenericCompanyPortal = true;
            _persistSession();
            SessionStorage.updateBrowserUrl('/');
          });
        },
      );
    }

    return SuperAdminScreen(
      key: const ValueKey('super_admin_dashboard'),
      apiClient: _apiClient,
      onSwitchToPortal: _switchToPortal,
      onLogout: _logout,
    );
  }

  Widget _buildCurrentScreen() {
    final Widget screen;
    if (_isAdminMode) {
      screen = _buildAdminGateOrScreen();
    } else if (_isLoginMode) {
      screen = TenantLoginScreen(
        key: ValueKey('company_portal_login_$_activeTenant'),
        apiClient: _apiClient,
        tenantSlug: _activeTenant,
        isGenericCompanyPortal: _isGenericCompanyPortal,
        onLoginSuccess: _handleVendorLoginSuccess,
        onNavigateToAdmin: null,
      );
    } else {
      screen = TenantSecurityGuard(
        key: ValueKey('guard_$_activeTenant'),
        apiClient: _apiClient,
        activePortalSlug: _activeTenant,
        onRedirectToAuthorizedPortal: (authorizedSlug) {
          _onTenantChanged(authorizedSlug);
        },
        child: AppShell(
          key: ValueKey('shell_$_activeTenant'),
          apiClient: _apiClient,
          activeTenant: _activeTenant,
          onTenantChanged: _onTenantChanged,
          onNavigateToAdmin: null,
          onLogout: _logout,
        ),
      );
    }

    return M3FadeThroughSwitcher(
      child: screen,
    );
  }

  Route<dynamic>? _onGenerateRoute(RouteSettings settings) {
    final name = settings.name ?? '/';
    final uri = Uri.parse(name);

    if (uri.path == '/admin') {
      return MaterialPageRoute(
        settings: settings,
        builder: (_) => Theme(
          data: AppTheme.light(seedColor: TenantBrandSeeds.adminSeed),
          child: _buildAdminGateOrScreen(),
        ),
      );
    }

    if (uri.pathSegments.isNotEmpty && uri.pathSegments[0] == 'portal') {
      final slug = ApiClient.normalizeDataTenantSlug(
        uri.pathSegments.length > 1 ? uri.pathSegments[1] : 'adeco',
      );
      final seed = TenantBrandSeeds.getSeedForTenant(slug);

      if (uri.pathSegments.length > 2 && uri.pathSegments[2] == 'login') {
        return MaterialPageRoute(
          settings: settings,
          builder: (_) => Theme(
            data: AppTheme.light(seedColor: seed),
            child: TenantLoginScreen(
              key: ValueKey('route_login_$slug'),
              apiClient: _apiClient,
              tenantSlug: slug,
              onLoginSuccess: _handleVendorLoginSuccess,
              onNavigateToAdmin: null,
            ),
          ),
        );
      }

      _apiClient.tenantId = 'tenant-$slug';
      final profile = ApiClient.getTenantProfileBySlug(slug);
      final brandEn = ApiClient.getEnglishDisplayNameForTenant(slug);
      _apiClient.currentTenantProfile = profile;
      final existingUser = _apiClient.currentUser;
      if (existingUser == null ||
          existingUser.isSuperAdmin ||
          ApiClient.normalizeDataTenantSlug(existingUser.tenantId) != slug) {
        final saved = SessionStorage.loadSession();
        final savedUser = saved?.currentUserJson != null
            ? TenantUserModel.fromJson(saved!.currentUserJson!)
            : null;
        if (savedUser != null &&
            !savedUser.isSuperAdmin &&
            ApiClient.normalizeDataTenantSlug(savedUser.tenantId) == slug) {
          final rawName = savedUser.fullName.trim();
          final cleanName = (rawName.isEmpty ||
                  rawName.contains('مدير') ||
                  rawName.contains('مشرف') ||
                  rawName.contains('مسؤول'))
              ? '$brandEn Admin'
              : rawName;
          _apiClient.currentUser = TenantUserModel(
            userId: savedUser.userId,
            tenantId: slug,
            email: savedUser.email.isNotEmpty
                ? savedUser.email
                : 'admin@$slug-retail.com',
            fullName: cleanName,
            role: savedUser.role.isNotEmpty ? savedUser.role : 'vendor_admin',
            assignedChain: savedUser.assignedChain,
            assignedRegion: savedUser.assignedRegion,
          );
        } else {
          _apiClient.currentUser = TenantUserModel(
            userId: 'user-$slug-admin-01',
            tenantId: slug,
            email: profile.adminEmail.isNotEmpty
                ? profile.adminEmail
                : 'admin@$slug-retail.com',
            fullName: '$brandEn Admin',
            role: 'vendor_admin',
          );
        }
      }
      if (_apiClient.authToken.isEmpty) {
        _apiClient.authToken = SessionStorage.loadSession()?.authToken ?? '';
      }

      return MaterialPageRoute(
        settings: settings,
        builder: (_) => Theme(
          data: AppTheme.light(seedColor: seed),
          child: TenantSecurityGuard(
            apiClient: _apiClient,
            activePortalSlug: slug,
            onRedirectToAuthorizedPortal: _switchToPortal,
            child: AppShell(
              key: ValueKey('route_shell_$slug'),
              apiClient: _apiClient,
              activeTenant: slug,
              onTenantChanged: _onTenantChanged,
              onNavigateToAdmin: null,
              onLogout: _logout,
            ),
          ),
        ),
      );
    }

    return null;
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Locale>(
      valueListenable: appLocaleNotifier,
      builder: (context, currentLocale, _) {
        return MaterialApp(
          navigatorKey: _navigatorKey,
          title: 'Tashil Data Sharing',
          debugShowCheckedModeBanner: false,
          scrollBehavior: const AppScrollBehavior(),
          themeMode: ThemeMode.light,
          theme: AppTheme.light(seedColor: _currentSeed),
          darkTheme: AppTheme.dark(seedColor: _currentSeed),

          // English Primary Default Configuration with Arabic RTL Support
          locale: currentLocale,
          supportedLocales: const [
            Locale('en'),
            Locale('ar'),
          ],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],

          onGenerateRoute: _onGenerateRoute,
          home: _buildCurrentScreen(),
        );
      },
    );
  }
}

/// Allows smooth dragging and swiping on Web for all pointer types
/// (touch, mouse, trackpad, and stylus).
class AppScrollBehavior extends MaterialScrollBehavior {
  const AppScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices => {
        PointerDeviceKind.touch,
        PointerDeviceKind.mouse,
        PointerDeviceKind.trackpad,
        PointerDeviceKind.stylus,
        PointerDeviceKind.unknown,
      };
}

