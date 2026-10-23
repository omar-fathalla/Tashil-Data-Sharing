import 'package:flutter/material.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/theme/m3_motion.dart';
import '../../../../core/theme/m3_spacing.dart';
import '../../../../core/widgets/data_sharing_logo.dart';
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
        icon: Icons.dashboard_outlined,
        selectedIcon: Icons.dashboard_rounded,
        label: 'Dashboard',
      ),
      _NavDestination(
        icon: Icons.analytics_outlined,
        selectedIcon: Icons.analytics_rounded,
        label: 'Sell-Out',
      ),
      _NavDestination(
        icon: Icons.local_shipping_outlined,
        selectedIcon: Icons.local_shipping_rounded,
        label: 'Sell-In',
      ),
      _NavDestination(
        icon: Icons.warning_amber_outlined,
        selectedIcon: Icons.warning_amber_rounded,
        label: 'OOS Monitor',
        badgeCount: 3,
      ),
      _NavDestination(
        icon: Icons.store_mall_directory_outlined,
        selectedIcon: Icons.store_mall_directory_rounded,
        label: 'Store Matrix',
      ),
      _NavDestination(
        icon: Icons.price_change_outlined,
        selectedIcon: Icons.price_change_rounded,
        label: 'Pricing & Promos',
      ),
      _NavDestination(
        icon: Icons.compare_arrows_outlined,
        selectedIcon: Icons.compare_arrows_rounded,
        label: 'Compare',
      ),
      _NavDestination(
        icon: Icons.campaign_outlined,
        selectedIcon: Icons.campaign_rounded,
        label: 'Trade Marketing & ROI',
      ),
      _NavDestination(
        icon: Icons.inventory_2_outlined,
        selectedIcon: Icons.inventory_2_rounded,
        label: 'CPFR Replenishment',
      ),
      _NavDestination(
        icon: Icons.auto_awesome_outlined,
        selectedIcon: Icons.auto_awesome_rounded,
        label: 'Upload',
      ),
      _NavDestination(
        icon: Icons.qr_code_2_outlined,
        selectedIcon: Icons.qr_code_2_rounded,
        label: 'Product Master',
      ),
    ];

    return Container(
      width: 250.0,
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainer,
        border: BorderDirectional(
          end: BorderSide(color: colorScheme.outlineVariant.withOpacity(0.5), width: 1.0),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header: Brand & App Title
          Padding(
            padding: const EdgeInsets.fromLTRB(16.0, 24.0, 16.0, 16.0),
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
                      Text(
                        'Tashil Portal',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        'Data Sharing Platform',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                          fontSize: 10.0,
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
              padding: const EdgeInsets.symmetric(horizontal: 12.0),
              itemCount: destinations.length,
              separatorBuilder: (_, __) => const SizedBox(height: 4.0),
              itemBuilder: (context, index) {
                final dest = destinations[index];
                final isSelected = selectedIndex == index;

                return InkWell(
                  onTap: () => onDestinationSelected(index),
                  borderRadius: BorderRadius.circular(28.0), // M3 pill shape
                  child: AnimatedContainer(
                    duration: M3Motion.short4,
                    curve: M3Motion.standard,
                    height: 48.0,
                    padding: const EdgeInsets.symmetric(horizontal: 16.0),
                    decoration: BoxDecoration(
                      color: isSelected ? colorScheme.secondaryContainer : Colors.transparent,
                      borderRadius: BorderRadius.circular(28.0),
                    ),
                    child: Row(
                      children: [
                        AnimatedSwitcher(
                          duration: M3Motion.short3,
                          transitionBuilder: (child, anim) => ScaleTransition(
                            scale: Tween<double>(begin: 0.85, end: 1.0).animate(anim),
                            child: FadeTransition(opacity: anim, child: child),
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
                          child: AnimatedDefaultTextStyle(
                            duration: M3Motion.short4,
                            curve: M3Motion.standard,
                            style: (theme.textTheme.labelLarge ?? const TextStyle()).copyWith(
                              color: isSelected
                                  ? colorScheme.onSecondaryContainer
                                  : colorScheme.onSurfaceVariant,
                              fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                              fontFamily: 'Cairo',
                            ),
                            child: Text(
                              dest.label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                        if (dest.badgeCount != null && dest.badgeCount! > 0)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6.0, vertical: 2.0),
                            decoration: BoxDecoration(
                              color: colorScheme.error,
                              borderRadius: BorderRadius.circular(10.0),
                            ),
                            child: Text(
                              dest.badgeCount.toString(),
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: colorScheme.onError,
                                fontSize: 10.0,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),

          // Super Admin Return Button (Visible ONLY to authenticated Super Admin inspecting a portal)
          if (isSuperAdmin && onNavigateToAdmin != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 4.0),
              child: OutlinedButton.icon(
                key: const ValueKey('sidebar_super_admin_button'),
                onPressed: onNavigateToAdmin,
                icon: Icon(
                  Icons.admin_panel_settings_rounded,
                  size: 18.0,
                  color: colorScheme.primary,
                ),
                label: Text(
                  'Back to Central Admin',
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: colorScheme.primary,
                  ),
                ),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 10.0),
                  side: BorderSide(color: colorScheme.primary.withOpacity(0.5)),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10.0),
                  ),
                ),
              ),
            ),

          // System Health & Engine Footer
          Container(
            padding: M3Spacing.pSm,
            margin: const EdgeInsets.all(12.0),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest.withOpacity(0.3),
              borderRadius: BorderRadius.circular(12.0),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.bolt, size: 14.0, color: colorScheme.primary),
                    const SizedBox(width: 4.0),
                    Expanded(
                      child: Text(
                        'Smart Ingestion Active',
                        style: theme.textTheme.labelSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                          fontSize: 10.0,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2.0),
                Text(
                  'BigQuery Streaming OLAP Active',
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontSize: 10.0,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _NavDestination {
  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final int? badgeCount;

  _NavDestination({
    required this.icon,
    required this.selectedIcon,
    required this.label,
    this.badgeCount,
  });
}
