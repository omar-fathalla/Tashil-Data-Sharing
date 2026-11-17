import 'dart:ui' show SemanticsHitTestBehavior;

import 'package:flutter/material.dart';
import 'package:tashil_web/core/theme/m3_typography.dart';
import '../../../core/widgets/app_icons.dart';
import '../../../core/storage/session_storage.dart';
import '../app_page_route.dart';
import '../../../core/theme/m3_spacing.dart';
import '../../../core/theme/m3_shape.dart';
import 'package:flutter/services.dart';
import '../../../../core/layout/window_size_classes.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/testing/test_semantics.dart';
import '../../../../core/theme/m3_motion.dart';
import '../../../../core/widgets/data_sharing_logo.dart';
import '../../data_ingestion/presentation/screens/upload_portal_screen.dart';
import '../../executive_dashboard/presentation/screens/executive_screen.dart';
import '../../oos_monitor/presentation/screens/oos_dashboard_screen.dart';
import '../../sell_out_analytics/presentation/screens/sell_in_explorer_screen.dart';
import '../../sell_out_analytics/presentation/screens/sell_out_explorer_screen.dart';
import '../../sell_in_returns/presentation/screens/sell_in_returns_screen.dart';
import '../../auth/presentation/widgets/user_profile_dialog.dart';
import '../../competitor_comparison/presentation/screens/competitor_comparison_screen.dart';
import '../../pricing_compliance/presentation/screens/pricing_compliance_screen.dart';
import '../../store_benchmark/presentation/screens/store_matrix_screen.dart';
import '../../cpfr_replenishment/presentation/screens/cpfr_dashboard_screen.dart';
import '../../product_master/presentation/screens/product_master_screen.dart';
import '../../data_quality/presentation/screens/data_quality_screen.dart';
import '../../trade_marketing/presentation/screens/trade_marketing_roi_screen.dart';
import 'desktop_sidebar.dart';
import 'tenant_logo_slot.dart';
import 'not_found_page.dart';

class _NavDestinationSpec {
  final int index;
  final String labelEn;
  final String labelAr;
  final String shortLabel;
  final IconData icon;
  final IconData selectedIcon;

  const _NavDestinationSpec({
    required this.index,
    required this.labelEn,
    required this.labelAr,
    required this.shortLabel,
    required this.icon,
    required this.selectedIcon,
  });
}

/// AppShell hosts the adaptive navigation layout (Sidebar on Desktop, Rail on Medium, Drawer + 5-item Bar on Compact)
/// and handles top-level routing and multi-tenant branding switches.
class AppShell extends StatefulWidget {
  final ApiClient apiClient;
  final String activeTenant;
  final ValueChanged<String> onTenantChanged;
  final VoidCallback? onNavigateToAdmin;
  final VoidCallback? onLogout;

  const AppShell({
    super.key,
    required this.apiClient,
    required this.activeTenant,
    required this.onTenantChanged,
    this.onNavigateToAdmin,
    this.onLogout,
  });

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _selectedIndex = 0;

  /// Set when the URL has an unknown page slug. The sidebar stays
  /// visible and no destination is highlighted until the user picks
  /// a real page or taps back to Dashboard.
  String? _unknownSlug;

  @override
  void initState() {
    super.initState();
    final path = SessionStorage.currentBrowserPath();
    _unknownSlug = AppPageRoute.unknownPageSlugFromPath(path);
    if (_unknownSlug == null) {
      _selectedIndex = AppPageRoute.indexForSlug(
        AppPageRoute.pageSlugFromPath(path),
      );
    }
    // The Navigator may report `/` after the first frame; re-assert the
    // current page so the address bar (and the next refresh) keep it.
    // Unknown slugs are left as-is so the Not Found page stays reachable.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_unknownSlug != null) {
        SessionStorage.replaceBrowserUrl(
          AppPageRoute.pathFor(widget.activeTenant, _unknownSlug!),
        );
        return;
      }
      SessionStorage.replaceBrowserUrl(
        AppPageRoute.pathFor(
          widget.activeTenant,
          AppPageRoute.slugForIndex(_selectedIndex),
        ),
      );
    });
  }

  void _selectPage(int index) {
    setState(() {
      _selectedIndex = index;
      _unknownSlug = null;
    });
    SessionStorage.replaceBrowserUrl(
      AppPageRoute.pathFor(
        widget.activeTenant,
        AppPageRoute.slugForIndex(index),
      ),
    );
  }

  int? get _navHighlightIndex => _unknownSlug != null ? null : _selectedIndex;

  static const List<_NavDestinationSpec> _destinations = [
    _NavDestinationSpec(
      index: 0,
      labelEn: 'Executive Overview',
      labelAr: 'لوحة القيادة التنفيذية',
      shortLabel: 'Dashboard',
      icon: Icons.dashboard_rounded,
      selectedIcon: Icons.dashboard_rounded,
    ),
    _NavDestinationSpec(
      index: 1,
      labelEn: 'Sell-Out & Targets',
      labelAr: 'المبيعات ومستهدفات الـ Sell-Out',
      shortLabel: 'Sell-Out',
      icon: Icons.analytics_rounded,
      selectedIcon: Icons.analytics_rounded,
    ),
    _NavDestinationSpec(
      index: 2,
      labelEn: 'Sell-In & Targets',
      labelAr: 'التوريد ومستهدفات الـ Sell-In',
      shortLabel: 'Sell-In',
      icon: Icons.local_shipping_rounded,
      selectedIcon: Icons.local_shipping_rounded,
    ),
    _NavDestinationSpec(
      index: 3,
      labelEn: 'Returns',
      labelAr: 'المرتجعات',
      shortLabel: 'Returns',
      icon: Icons.assignment_return_rounded,
      selectedIcon: Icons.assignment_return_rounded,
    ),
    _NavDestinationSpec(
      index: 4,
      labelEn: 'OOS Monitor',
      labelAr: 'مراقب النواقص',
      shortLabel: 'OOS',
      icon: Icons.warning_amber_rounded,
      selectedIcon: Icons.warning_amber_rounded,
    ),
    _NavDestinationSpec(
      index: 5,
      labelEn: 'Store Matrix',
      labelAr: 'مصفوفة الفروع',
      shortLabel: 'Matrix',
      icon: Icons.store_mall_directory_rounded,
      selectedIcon: Icons.store_mall_directory_rounded,
    ),
    _NavDestinationSpec(
      index: 6,
      labelEn: 'Pricing & Promos',
      labelAr: 'التسعير والعروض',
      shortLabel: 'Pricing',
      icon: Icons.price_change_rounded,
      selectedIcon: Icons.price_change_rounded,
    ),
    _NavDestinationSpec(
      index: 7,
      labelEn: 'Compare',
      labelAr: 'مقارنة المنافسين',
      shortLabel: 'Compare',
      icon: Icons.compare_arrows_rounded,
      selectedIcon: Icons.compare_arrows_rounded,
    ),
    _NavDestinationSpec(
      index: 8,
      labelEn: 'Trade Marketing & ROI',
      labelAr: 'المصروفات الترويجية وعائد التسويق',
      shortLabel: 'Promo ROI',
      icon: Icons.campaign_rounded,
      selectedIcon: Icons.campaign_rounded,
    ),
    _NavDestinationSpec(
      index: 9,
      labelEn: 'CPFR & PO',
      labelAr: 'التجديد وأوامر الشراء',
      shortLabel: 'CPFR',
      icon: Icons.inventory_2_rounded,
      selectedIcon: Icons.inventory_2_rounded,
    ),
    _NavDestinationSpec(
      index: 10,
      labelEn: 'Smart Upload',
      labelAr: 'رفع البيانات الذكي',
      shortLabel: 'Upload',
      icon: Icons.auto_awesome_rounded,
      selectedIcon: Icons.auto_awesome_rounded,
    ),
    _NavDestinationSpec(
      index: 11,
      labelEn: 'Product Master & Price List',
      labelAr: 'كارتة الأصناف والأسعار',
      shortLabel: 'Master',
      icon: Icons.qr_code_2_rounded,
      selectedIcon: Icons.qr_code_2_rounded,
    ),
    _NavDestinationSpec(
      index: 12,
      labelEn: 'Data Errors',
      labelAr: 'الأخطاء',
      shortLabel: 'Errors',
      icon: AppIcons.dataQuality,
      selectedIcon: AppIcons.dataQuality,
    ),
  ];

  void _openUserProfile() {
    showDialog(
      context: context,
      builder: (ctx) => UserProfileDialog(
        apiClient: widget.apiClient,
        tenantSlug: widget.activeTenant,
        onLogout: widget.onLogout,
        onRoleChanged: () {
          if (mounted) {
            setState(() {});
          }
        },
      ),
    );
  }

  void _openMobileModulesSheet() {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: colorScheme.surfaceContainer,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28.0)),
      ),
      builder: (sheetCtx) {
        return Directionality(
          textDirection: TextDirection.rtl,
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(16.0, 4.0, 16.0, 16.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      const DataSharingLogo(size: 32.0, showShadow: false),
                      const SizedBox(width: 10.0),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Tashil Sections',
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            Text(
                              ApiClient.getEnglishDisplayNameForTenant(widget.activeTenant),
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12.0),
                  const Divider(height: 1.0),
                  const SizedBox(height: 8.0),
                  ..._destinations.map((dest) {
                    final isSelected = _selectedIndex == dest.index;
                    final navId = TestIds.navIdForIndex(dest.index);
                    // Compact bottom bar already owns Dashboard / Sell-Out /
                    // Pricing / OOS ids — only tag destinations missing there
                    // (notably Sell-In / Returns) so each nav-* id stays unique in the tree.
                    const primaryCompactIndexes = {0, 1, 4, 6};
                    final attachNavId = navId != null &&
                        !primaryCompactIndexes.contains(dest.index);
                    Widget title = Text(
                      dest.labelEn,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight:
                            isSelected ? FontWeight.w800 : FontWeight.w600,
                        color: isSelected
                            ? colorScheme.onSecondaryContainer
                            : colorScheme.onSurface,
                      ),
                    );
                    if (attachNavId) {
                      title = TestSemantics.navTarget(
                        identifier: navId,
                        label: dest.shortLabel,
                        child: title,
                      );
                    }
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 4.0),
                      child: ListTile(
                        dense: true,
                        shape: const RoundedRectangleBorder(
                          borderRadius: M3Shape.radiusLg,
                        ),
                        tileColor: isSelected
                            ? colorScheme.secondaryContainer
                            : Colors.transparent,
                        leading: Icon(
                          isSelected ? dest.selectedIcon : dest.icon,
                          color: isSelected
                              ? colorScheme.onSecondaryContainer
                              : colorScheme.onSurfaceVariant,
                        ),
                        title: title,
                        trailing: isSelected
                            ? Icon(
                                Icons.check_circle_rounded,
                                size: 20.0,
                                color: colorScheme.primary,
                              )
                            : const Icon(AppIcons.chevronEnd, size: 18.0),
                        onTap: () {
                          Navigator.pop(sheetCtx);
                          _selectPage(dest.index);
                        },
                      ),
                    );
                  }),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final layout = M3Layout.of(context);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    // Shell direction is derived from the locale (see shellTextDirectionFor).
    final shellDirection = shellTextDirectionFor(Localizations.maybeLocaleOf(context));

    final tenantKey = ApiClient.normalizeTenantSlug(widget.activeTenant);
    final user = widget.apiClient.currentUser;
    final roleKey =
        '${user?.role ?? 'default'}_${user?.assignedChain ?? ''}_${user?.assignedRegion ?? ''}';
    final stateKey = '${tenantKey}_$roleKey';
    final screens = [
      ExecutiveScreen(
        key: ValueKey('exec_$stateKey'),
        apiClient: widget.apiClient,
      ),
      SellOutExplorerScreen(
        key: ValueKey('sellout_$stateKey'),
        apiClient: widget.apiClient,
      ),
      SellInExplorerScreen(
        key: ValueKey('sellin_$stateKey'),
        apiClient: widget.apiClient,
      ),
      SellInReturnsScreen(
        key: ValueKey('returns_$stateKey'),
        apiClient: widget.apiClient,
      ),
      OOSDashboardScreen(
        key: ValueKey('oos_$stateKey'),
        apiClient: widget.apiClient,
      ),
      StoreMatrixScreen(
        key: ValueKey('matrix_$stateKey'),
        apiClient: widget.apiClient,
      ),
      PricingComplianceScreen(
        key: ValueKey('pricing_$stateKey'),
        apiClient: widget.apiClient,
      ),
      CompetitorComparisonScreen(
        key: ValueKey('compare_$stateKey'),
        apiClient: widget.apiClient,
      ),
      TradeMarketingRoiScreen(
        key: ValueKey('trade_roi_$stateKey'),
        apiClient: widget.apiClient,
      ),
      CPFRDashboardScreen(
        key: ValueKey('cpfr_$stateKey'),
        apiClient: widget.apiClient,
      ),
      UploadPortalScreen(
        key: ValueKey('upload_$stateKey'),
        apiClient: widget.apiClient,
      ),
      ProductMasterScreen(
        key: ValueKey('product_master_$stateKey'),
        apiClient: widget.apiClient,
      ),
      DataQualityScreen(
        key: ValueKey('data_quality_$stateKey'),
        apiClient: widget.apiClient,
      ),
    ];

    final currentScreen = M3FadeThroughSwitcher(
      duration: M3Motion.medium2,
      reverseDuration: M3Motion.short4,
      alignment: Alignment.topCenter,
      fit: StackFit.expand,
      child: KeyedSubtree(
        key: ValueKey(
          _unknownSlug != null
              ? 'nav_dest_not_found_${_unknownSlug}_$stateKey'
              : 'nav_dest_${_selectedIndex}_$stateKey',
        ),
        child: _unknownSlug != null
            ? NotFoundPage(
                attemptedSlug: _unknownSlug,
                onBackToDashboard: () => _selectPage(0),
              )
            : screens[_selectedIndex],
      ),
    );

    // 1. Desktop Experience (Expanded, Large, Extra Large >= 840dp)
    if (layout.isDesktop) {
      // Stack (not Row): sidebar is painted/hit-tested above clipped content
      // so page overflow or web flt-semantics from Pricing (etc.) cannot
      // swallow the Compare row. Fade-through outgoing pages stay IgnorePointer.
      const sidebarWidth = 250.0;
      return Scaffold(
        body: Directionality(
          textDirection: shellDirection,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Positioned(
                left: 0,
                right: sidebarWidth,
                top: 0,
                bottom: 0,
                child: Directionality(
                  textDirection: TextDirection.rtl,
                  child: ColoredBox(
                    color: colorScheme.surface,
                    child: ClipRect(
                      child: Align(
                        alignment: Alignment.topCenter,
                        child: currentScreen,
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                right: 0,
                top: 0,
                bottom: 0,
                width: sidebarWidth,
                // Opaque web flt-semantics strip (same pattern as dialogs /
                // bottom sheets): when automation forces ensureSemantics(),
                // Pricing chips near Compare's Y must not steal sidebar hits.
                child: Semantics(
                  container: true,
                  explicitChildNodes: true,
                  hitTestBehavior: SemanticsHitTestBehavior.opaque,
                  child: DesktopSidebar(
                    selectedIndex: _navHighlightIndex ?? -1,
                    onDestinationSelected: (index) => _selectPage(index),
                    activeTenant: widget.activeTenant,
                    currentUser: widget.apiClient.currentUser,
                    tenantLogoUrl: widget.apiClient.currentTenantProfile?.logoUrl,
                    onTenantChanged: widget.onTenantChanged,
                    onOpenProfile: _openUserProfile,
                    onNavigateToAdmin: widget.onNavigateToAdmin,
                    isSuperAdmin:
                        widget.apiClient.currentUser?.isSuperAdmin == true,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    // 2. Medium Tablet Experience (600 - 839dp) - Slim Navigation Rail
    if (layout.isMedium) {
      final rail = NavigationRail(
        selectedIndex: _navHighlightIndex,
        onDestinationSelected: (index) => _selectPage(index),
        labelType: NavigationRailLabelType.all,
        backgroundColor: colorScheme.surfaceContainer,
        leading: Padding(
          padding: const EdgeInsets.only(top: 8.0, bottom: 12.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Tooltip(
                message: 'Account & profile',
                child: InkWell(
                  key: const ValueKey('rail_tenant_header'),
                  customBorder: const CircleBorder(),
                  onTap: _openUserProfile,
                  child: TenantLogoSlot(
                    tenantSlug: widget.activeTenant,
                    logoUrl: widget.apiClient.currentTenantProfile?.logoUrl,
                    radius: 18.0,
                  ),
                ),
              ),
              const SizedBox(height: 6.0),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8.0,
                  vertical: 2.0,
                ),
                constraints: const BoxConstraints(maxWidth: 72.0),
                decoration: BoxDecoration(
                  color: colorScheme.primaryContainer,
                  borderRadius: M3Shape.radiusFull,
                ),
                child: Text(
                  ApiClient.getEnglishDisplayNameForTenant(widget.activeTenant),
                  key: const ValueKey('rail_tenant_name'),
                  textDirection: TextDirection.ltr,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.labelSmall?.copyWith(
                    fontSize: M3FontSize.microPlus,
                    fontWeight: FontWeight.w800,
                    color: colorScheme.onPrimaryContainer,
                  ),
                ),
              ),
            ],
          ),
        ),
        trailing: Expanded(
          child: Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 12.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (widget.onNavigateToAdmin != null &&
                      widget.apiClient.currentUser?.isSuperAdmin == true)
                    IconButton(
                      icon: const Icon(Icons.admin_panel_settings_rounded),
                      tooltip: 'Super Admin Portal',
                      onPressed: widget.onNavigateToAdmin,
                    ),
                  IconButton(
                    icon: const Icon(Icons.manage_accounts_rounded),
                    tooltip: 'Profile & Account',
                    onPressed: _openUserProfile,
                  ),
                  if (widget.onLogout != null)
                    TestSemantics(
                      identifier: TestIds.logout,
                      label: 'Log Out',
                      button: true,
                      child: IconButton(
                        icon: Icon(
                          Icons.logout_rounded,
                          color: colorScheme.error,
                        ),
                        tooltip: 'Log Out',
                        onPressed: widget.onLogout,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
        // Exactly one Semantics identifier per nav destination (on
        // `label` only — never also on icon/selectedIcon). Label stays
        // mounted for both selected and unselected states.
        destinations: _destinations
            .map(
              (d) {
                final navId = TestIds.navIdForIndex(d.index);
                final Widget label = navId == null
                    ? Text(d.shortLabel)
                    : TestSemantics.navTarget(
                        identifier: navId,
                        label: d.shortLabel,
                        child: Text(d.shortLabel),
                      );
                return NavigationRailDestination(
                  icon: Icon(d.icon),
                  selectedIcon: Icon(d.selectedIcon),
                  label: label,
                );
              },
            )
            .toList(),
      );
      return Scaffold(
        body: Directionality(
          textDirection: shellDirection,
          child: Row(
            textDirection: TextDirection.ltr,
            children: [
              Expanded(
                child: Directionality(
                  textDirection: TextDirection.rtl,
                  child: ColoredBox(
                    color: colorScheme.surface,
                    child: ClipRect(
                      child: Align(
                        alignment: Alignment.topCenter,
                        child: currentScreen,
                      ),
                    ),
                  ),
                ),
              ),
              const VerticalDivider(thickness: 1, width: 1),
              rail,
            ],
          ),
        ),
      );
    }

    // 3. Compact Mobile Experience (< 600dp)
    // Strictly follows M3 Bottom Navigation Bar limit (5 destinations max):
    // 4 primary destinations: Dashboard (0), Sell-Out (1), Pricing (6), OOS (4)
    // + 5th dynamic 'More' destination (Sell-In, Returns, Matrix, CPFR, …).
    final bool isSecondarySelected = _selectedIndex != 0 &&
        _selectedIndex != 1 &&
        _selectedIndex != 6 &&
        _selectedIndex != 4;
    final int bottomNavIndex;
    if (_selectedIndex == 0) {
      bottomNavIndex = 0;
    } else if (_selectedIndex == 1) {
      bottomNavIndex = 1;
    } else if (_selectedIndex == 6) {
      bottomNavIndex = 2; // Pricing
    } else if (_selectedIndex == 4) {
      bottomNavIndex = 3; // OOS
    } else {
      bottomNavIndex = 4; // More / Secondary
    }

    final _NavDestinationSpec activeSecondarySpec =
        isSecondarySelected ? _destinations[_selectedIndex] : _destinations[2];

    return Scaffold(
      appBar: AppBar(
        backgroundColor: colorScheme.surfaceContainer,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        systemOverlayStyle: SystemUiOverlayStyle(
          statusBarColor: colorScheme.surfaceContainer,
          statusBarIconBrightness: Brightness.dark,
          systemNavigationBarColor: colorScheme.surfaceContainer,
          systemNavigationBarIconBrightness: Brightness.dark,
        ),
        automaticallyImplyLeading: false,
        titleSpacing: 0,
        title: Directionality(
          textDirection: shellDirection,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12.0),
            child: Row(
              children: [
                // Left: Logo + Tashil Data Sharing + Company Adeco in English only
                const DataSharingLogo(size: 32.0, showShadow: false),
                const SizedBox(width: 8.0),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Tashil Data Sharing',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.2,
                        ),
                      ),
                      Text(
                        _getCompanyEnglishSubtitle(widget.activeTenant),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                          fontSize: M3FontSize.labelSmall,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                // Right: User Profile Icon placed to the left of the Menu Icon
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (widget.onNavigateToAdmin != null &&
                        widget.apiClient.currentUser?.isSuperAdmin == true)
                      IconButton(
                        icon: const Icon(Icons.admin_panel_settings_rounded),
                        tooltip: 'Admin Panel',
                        visualDensity: VisualDensity.compact,
                        onPressed: widget.onNavigateToAdmin,
                      ),
                    IconButton(
                      icon: const Icon(Icons.manage_accounts_rounded),
                      tooltip: 'Profile & Account',
                      visualDensity: VisualDensity.compact,
                      onPressed: _openUserProfile,
                    ),
                    Builder(
                      builder: (ctx) => IconButton(
                        icon: const Icon(Icons.menu_rounded),
                        tooltip: 'Menu',
                        visualDensity: VisualDensity.compact,
                        onPressed: () => Scaffold.of(ctx).openDrawer(),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
      drawer: NavigationDrawer(
        selectedIndex: () {
          final i = _destinations.indexWhere((d) => d.index == _selectedIndex);
          return i < 0 ? null : i;
        }(),
        onDestinationSelected: (pos) {
          _selectPage(_destinations[pos].index);
          Navigator.pop(context);
        },
        children: [
              Container(
                padding: const EdgeInsetsDirectional.fromSTEB(20.0, 20.0, 20.0, 16.0),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainer,
                  border: Border(
                    bottom: BorderSide(
                      color: colorScheme.outlineVariant.withOpacity(0.5),
                    ),
                  ),
                ),
                child: Row(
                  children: [
                    const DataSharingLogo(size: 42.0),
                    const SizedBox(width: 12.0),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Tashil Data Sharing',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w800,
                              color: colorScheme.onSurface,
                            ),
                          ),
                          const SizedBox(height: 2.0),
                          Text(
                            ApiClient.getEnglishDisplayNameForTenant(widget.activeTenant),
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colorScheme.primary,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              M3Spacing.gapXS,
              // Compact drawer: bottom bar already owns Sell-Out — only attach
              // ids for destinations missing there (notably Sell-In).
              ..._destinations.map(
                (dest) {
                  final navId = TestIds.navIdForIndex(dest.index);
                  const primaryCompactIndexes = {0, 1, 3, 5};
                  final attachNavId = navId != null &&
                      !primaryCompactIndexes.contains(dest.index);
                  Widget labelChild = Text(
                    dest.labelEn,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  );
                  if (attachNavId) {
                    labelChild = TestSemantics.navTarget(
                      identifier: navId,
                      label: dest.shortLabel,
                      child: labelChild,
                    );
                  }
                  return NavigationDrawerDestination(
                    icon: Icon(dest.icon),
                    selectedIcon: Icon(dest.selectedIcon),
                    label: Flexible(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [labelChild],
                      ),
                    ),
                  );
                },
              ),
              const Divider(height: 1.0),
              Padding(
                padding: const EdgeInsets.all(12.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ListTile(
                      dense: true,
                      shape: const RoundedRectangleBorder(
                        borderRadius: M3Shape.radiusMd,
                      ),
                      leading: const Icon(Icons.manage_accounts_rounded),
                      title: Text(
                        user?.fullName ?? user?.email ?? 'Profile',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      subtitle: Text(user?.role ?? 'User'),
                      onTap: () {
                        Navigator.pop(context);
                        _openUserProfile();
                      },
                    ),
                    if (widget.onLogout != null)
                      TestSemantics(
                        identifier: TestIds.logout,
                        label: 'Log Out',
                        button: true,
                        child: ListTile(
                          dense: true,
                          shape: const RoundedRectangleBorder(
                            borderRadius: M3Shape.radiusMd,
                          ),
                          leading: Icon(
                            Icons.logout_rounded,
                            color: colorScheme.error,
                          ),
                          title: Text(
                            'Log Out',
                            style: TextStyle(
                              color: colorScheme.error,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          onTap: () {
                            Navigator.pop(context);
                            widget.onLogout!();
                          },
                        ),
                      ),
                  ],
                ),
              ),
        ],
      ),
      body: Directionality(
        textDirection: TextDirection.rtl,
        child: Container(
          color: colorScheme.surface,
          alignment: Alignment.topCenter,
          child: currentScreen,
        ),
      ),
      bottomNavigationBar: Directionality(
        textDirection: shellDirection,
        child: NavigationBar(
          backgroundColor: colorScheme.surfaceContainer,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          selectedIndex: bottomNavIndex,
          labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
          onDestinationSelected: (idx) {
            if (idx == 0) {
              _selectPage(0);
            } else if (idx == 1) {
              _selectPage(1);
            } else if (idx == 2) {
              _selectPage(6); // Pricing & Promos
            } else if (idx == 3) {
              _selectPage(4); // OOS Monitor
            } else {
              _openMobileModulesSheet();
            }
          },
          destinations: [
            const NavigationDestination(
              icon: Icon(Icons.dashboard_rounded),
              selectedIcon: Icon(Icons.dashboard_rounded),
              label: 'Dashboard',
            ),
            // NavigationBar swaps icon ↔ selectedIcon; tag both so
            // nav-sell-out stays present in selected and unselected states.
            // Only one of the two is built at a time.
            const NavigationDestination(
              icon: TestSemantics.navTarget(
                identifier: TestIds.navSellOut,
                label: 'Sell-Out',
                child: Icon(Icons.analytics_rounded),
              ),
              selectedIcon: TestSemantics.navTarget(
                identifier: TestIds.navSellOut,
                label: 'Sell-Out',
                child: Icon(Icons.analytics_rounded),
              ),
              label: 'Sell-Out',
            ),
            const NavigationDestination(
              icon: Icon(Icons.price_change_rounded),
              selectedIcon: Icon(Icons.price_change_rounded),
              label: 'Pricing',
            ),
            const NavigationDestination(
              icon: Icon(Icons.warning_amber_rounded),
              selectedIcon: Icon(Icons.warning_amber_rounded),
              label: 'OOS',
            ),
            NavigationDestination(
              icon: Icon(
                isSecondarySelected
                    ? activeSecondarySpec.icon
                    : Icons.apps_rounded,
              ),
              selectedIcon: Icon(
                isSecondarySelected
                    ? activeSecondarySpec.selectedIcon
                    : Icons.apps_rounded,
              ),
              label: isSecondarySelected ? activeSecondarySpec.shortLabel : 'More',
            ),
          ],
        ),
      ),
    );
  }

  String _getCompanyEnglishSubtitle(String tenantSlug) {
    final clean = ApiClient.normalizeTenantSlug(tenantSlug).trim();
    if (clean.toLowerCase() == 'adeco' || clean.isEmpty) {
      return 'Company Adeco';
    }
    return 'Company ${clean[0].toUpperCase()}${clean.substring(1)}';
  }
}

/// The shell's text direction. All page content is Arabic, so the navigation
/// chrome is RTL (sidebar/rail on the start = right side) for both supported
/// locales ('ar' and the 'en' default) to stay consistent with the content.
TextDirection shellTextDirectionFor(Locale? locale) => TextDirection.rtl;
