import '../../../core/widgets/app_icons.dart';
import 'package:flutter/material.dart';
import '../../../core/config/app_version.dart';
import '../../../core/network/api_client.dart';
import '../../../core/testing/test_semantics.dart';
import '../../../core/theme/m3_motion.dart';
import '../../../core/theme/m3_spacing.dart';
import '../../../core/widgets/data_sharing_logo.dart';
import 'tenant_profile_card.dart';

/// DesktopSidebar provides a permanent Material Design 3 Navigation Drawer
/// with an RTL layout (width: 250dp) designed for executive management portals.
class DesktopSidebar extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;
  final String activeTenant;
  final TenantUserModel? currentUser;
  final ValueChanged<String> onTenantChanged;
  final VoidCallback? onOpenProfile;
  final VoidCallback? onNavigateToAdmin;
  final bool isSuperAdmin;

  const DesktopSidebar({
    super.key,
    required this.selectedIndex,
    required this.onDestinationSelected,
    required this.activeTenant,
    this.currentUser,
    required this.onTenantChanged,
    this.onOpenProfile,
    this.onNavigateToAdmin,
    this.isSuperAdmin = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final destinations = [
      _NavDestination(
        icon: Icons.dashboard_rounded,
        selectedIcon: Icons.dashboard_rounded,
        label: 'Dashboard',
        labelAr: 'لوحة القيادة',
      ),
      _NavDestination(
        icon: Icons.analytics_rounded,
        selectedIcon: Icons.analytics_rounded,
        label: 'Sell-Out',
        labelAr: 'المبيعات (Sell-Out)',
        semanticsIdentifier: TestIds.navSellOut,
      ),
      _NavDestination(
        icon: Icons.local_shipping_rounded,
        selectedIcon: Icons.local_shipping_rounded,
        label: 'Sell-In',
        labelAr: 'التوريد (Sell-In)',
        semanticsIdentifier: TestIds.navSellIn,
      ),
      _NavDestination(
        icon: Icons.assignment_return_rounded,
        selectedIcon: Icons.assignment_return_rounded,
        label: 'Returns',
        labelAr: 'المرتجعات',
        semanticsIdentifier: TestIds.navReturns,
      ),
      _NavDestination(
        icon: Icons.warning_amber_rounded,
        selectedIcon: Icons.warning_amber_rounded,
        label: 'OOS Monitor',
        labelAr: 'مراقب النواقص',
        badgeCount: 3,
      ),
      _NavDestination(
        icon: Icons.store_mall_directory_rounded,
        selectedIcon: Icons.store_mall_directory_rounded,
        label: 'Store Matrix',
        labelAr: 'مصفوفة الفروع',
      ),
      _NavDestination(
        icon: Icons.price_change_rounded,
        selectedIcon: Icons.price_change_rounded,
        label: 'Pricing & Promos',
        labelAr: 'التسعير والعروض',
        semanticsIdentifier: TestIds.navPricing,
      ),
      _NavDestination(
        icon: Icons.compare_arrows_rounded,
        selectedIcon: Icons.compare_arrows_rounded,
        label: 'Compare',
        labelAr: 'مقارنة المنافسين',
        semanticsIdentifier: TestIds.navCompare,
      ),
      _NavDestination(
        icon: Icons.campaign_rounded,
        selectedIcon: Icons.campaign_rounded,
        label: 'Trade Marketing & ROI',
        labelAr: 'التسويق التجاري والعائد',
      ),
      _NavDestination(
        icon: Icons.inventory_2_rounded,
        selectedIcon: Icons.inventory_2_rounded,
        label: 'CPFR Replenishment',
        labelAr: 'التجديد وأوامر الشراء',
      ),
      _NavDestination(
        icon: Icons.auto_awesome_rounded,
        selectedIcon: Icons.auto_awesome_rounded,
        label: 'Upload',
        labelAr: 'رفع البيانات الذكي',
      ),
      _NavDestination(
        icon: Icons.qr_code_2_rounded,
        selectedIcon: Icons.qr_code_2_rounded,
        label: 'Product Master',
        labelAr: 'كارتة الأصناف',
      ),
      _NavDestination(
        icon: AppIcons.dataQuality,
        selectedIcon: AppIcons.dataQuality,
        label: 'Errors',
        labelAr: 'الأخطاء',
      ),
    ];

    // Elevation keeps sidebar (and its flt-semantics nodes) above page
    // content when ensureSemantics() is on for web automation.
    return Material(
      elevation: 1.0,
      shadowColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      color: colorScheme.surfaceContainer,
      shape: BorderDirectional(
        end: BorderSide(color: colorScheme.outlineVariant, width: 1.0),
      ),
      child: SizedBox(
        width: 250.0,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header: Brand & App Title
            Padding(
              padding:
                  const EdgeInsetsDirectional.fromSTEB(16.0, 24.0, 16.0, 16.0),
              child: Row(
                children: [
                  const DataSharingLogo(
                    size: 40.0,
                    showSquircle: true,
                  ),
                  M3Spacing.gapSM,
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                'Tashil Portal',
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            const SizedBox(width: 6.0),
                            ValueListenableBuilder<String>(
                              valueListenable: AppVersion.listenable,
                              builder: (context, versionLabel, _) {
                                return Text(
                                  versionLabel,
                                  key: const ValueKey('sidebar-app-version'),
                                  textDirection: TextDirection.ltr,
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                                );
                              },
                            ),
                          ],
                        ),
                        Text(
                          'Data Sharing Platform',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // Tenant Profile Switcher
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: TenantProfileCard(
                activeTenant: activeTenant,
                currentUser: currentUser,
                onTenantChanged: onTenantChanged,
                onOpenProfile: onOpenProfile,
                onNavigateToAdmin: onNavigateToAdmin,
                isSuperAdmin: isSuperAdmin,
              ),
            ),

            M3Spacing.gapMD,

            // Navigation Items
            Expanded(
              child: ListView.separated(
                padding:
                    const EdgeInsetsDirectional.fromSTEB(12.0, 0.0, 12.0, 12.0),
                itemCount: destinations.length,
                separatorBuilder: (_, __) => const SizedBox(height: 4.0),
                itemBuilder: (context, index) {
                  final dest = destinations[index];
                  final isSelected = selectedIndex == index;

                  // M3 nav indicator: a pill-shaped Material (no BoxDecoration).
                  // Own the web flt-semantics tap (onTap) so page overlays /
                  // mis-sized content semantics cannot swallow sidebar clicks
                  // (live: Pricing → Compare stayed put while OOS still worked).
                  void select() => onDestinationSelected(index);
                  Widget item = Material(
                    key: ValueKey('sidebar_nav_${dest.label}'),
                    color: isSelected
                        ? colorScheme.secondaryContainer
                        : Colors.transparent,
                    shape: const StadiumBorder(),
                    clipBehavior: Clip.antiAlias,
                    animationDuration: M3Motion.short4,
                    child: InkWell(
                      onTap: select,
                      customBorder: const StadiumBorder(),
                      child: Container(
                        height: 52.0,
                        padding: const EdgeInsetsDirectional.symmetric(
                            horizontal: 16.0),
                        child: Row(
                          children: [
                            AnimatedSwitcher(
                              duration: M3Motion.short3,
                              transitionBuilder: (child, anim) =>
                                  ScaleTransition(
                                scale: Tween<double>(begin: 0.85, end: 1.0)
                                    .animate(anim),
                                child:
                                    FadeTransition(opacity: anim, child: child),
                              ),
                              child: Icon(
                                isSelected ? dest.selectedIcon : dest.icon,
                                key: ValueKey('${index}_$isSelected'),
                                size: 22.0,
                                color: isSelected
                                    ? colorScheme.onSecondaryContainer
                                    : colorScheme.onSurfaceVariant,
                              ),
                            ),
                            M3Spacing.gapSM,
                            Expanded(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    dest.label,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.labelLarge?.copyWith(
                                      color: isSelected
                                          ? colorScheme.onSecondaryContainer
                                          : colorScheme.onSurface,
                                      fontWeight: isSelected
                                          ? FontWeight.w700
                                          : FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (dest.badgeCount != null && dest.badgeCount! > 0)
                              Badge.count(count: dest.badgeCount!),
                          ],
                        ),
                      ),
                    ),
                  );
                  final id = dest.semanticsIdentifier;
                  item = Semantics(
                    identifier: id,
                    label: dest.label,
                    button: true,
                    container: true,
                    excludeSemantics: true,
                    onTap: select,
                    child: item,
                  );
                  return item;
                },
              ),
            ),

            // Super Admin Return Button (Visible ONLY to authenticated Super Admin inspecting a portal)
            if (isSuperAdmin && onNavigateToAdmin != null)
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12.0, vertical: 4.0),
                child: OutlinedButton.icon(
                  key: const ValueKey('sidebar_super_admin_button'),
                  onPressed: onNavigateToAdmin,
                  icon: Icon(
                    Icons.admin_panel_settings_rounded,
                    size: 18.0,
                    color: colorScheme.primary,
                  ),
                  label: Text(
                    'Back to Super Admin',
                    style: theme.textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: colorScheme.primary,
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12.0, vertical: 10.0),
                    side: BorderSide(color: colorScheme.outline),
                  ),
                ),
              ),

            // System Health footer: fixed below the scrollable list (never overlaps it).
            const Divider(height: 1.0),
            Padding(
              padding:
                  const EdgeInsetsDirectional.fromSTEB(16.0, 8.0, 16.0, 12.0),
              child: Row(
                key: const ValueKey('sidebar_footer_status'),
                children: [
                  // Only the status dot uses primary; icon + text stay neutral.
                  CircleAvatar(
                      radius: 4.0, backgroundColor: colorScheme.primary),
                  const SizedBox(width: 6.0),
                  Icon(Icons.bolt_rounded,
                      size: 16.0, color: colorScheme.onSurfaceVariant),
                  const SizedBox(width: 6.0),
                  Expanded(
                    child: Text(
                      'Smart Ingestion Active',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NavDestination {
  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final String labelAr;
  final int? badgeCount;
  final String? semanticsIdentifier;

  _NavDestination({
    required this.icon,
    required this.selectedIcon,
    required this.label,
    required this.labelAr,
    this.badgeCount,
    this.semanticsIdentifier,
  });
}
