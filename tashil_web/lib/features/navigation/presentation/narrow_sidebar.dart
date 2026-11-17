import 'package:flutter/material.dart';

import '../../../core/network/api_client.dart';
import '../../../core/testing/test_semantics.dart';
import '../../../core/theme/m3_shape.dart';
import '../../../core/theme/m3_typography.dart';
import '../nav_catalog.dart';
import 'tenant_logo_slot.dart';

/// Icon rail used below the desktop breakpoint (600–839dp).
///
/// Section titles from the wide sidebar become thin dividers here. The
/// tenant mark, account actions, and logout stay where the old
/// [NavigationRail] put them.
class NarrowSidebar extends StatelessWidget {
  static const double width = 80.0;

  final int? selectedRouteIndex;
  final ValueChanged<int> onDestinationSelected;
  final String activeTenant;
  final String? tenantLogoUrl;
  final VoidCallback? onOpenProfile;
  final VoidCallback? onNavigateToAdmin;
  final VoidCallback? onLogout;
  final bool isSuperAdmin;

  const NarrowSidebar({
    super.key,
    required this.selectedRouteIndex,
    required this.onDestinationSelected,
    required this.activeTenant,
    this.tenantLogoUrl,
    this.onOpenProfile,
    this.onNavigateToAdmin,
    this.onLogout,
    this.isSuperAdmin = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Material(
      color: colorScheme.surfaceContainer,
      child: SizedBox(
        width: width,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 8.0, bottom: 12.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Tooltip(
                    message: 'Account & profile',
                    child: InkWell(
                      key: const ValueKey('rail_tenant_header'),
                      customBorder: const CircleBorder(),
                      onTap: onOpenProfile,
                      child: TenantLogoSlot(
                        tenantSlug: activeTenant,
                        logoUrl: tenantLogoUrl,
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
                      ApiClient.getEnglishDisplayNameForTenant(activeTenant),
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
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 4.0),
                children: navSectionChildren(
                  collapsed: true,
                  itemBuilder: (item) => _NarrowDestination(
                    item: item,
                    selected: selectedRouteIndex == item.routeIndex,
                    onTap: () => onDestinationSelected(item.routeIndex),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 12.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (isSuperAdmin && onNavigateToAdmin != null)
                    IconButton(
                      icon: const Icon(Icons.admin_panel_settings_rounded),
                      tooltip: 'Super Admin Portal',
                      onPressed: onNavigateToAdmin,
                    ),
                  IconButton(
                    icon: const Icon(Icons.manage_accounts_rounded),
                    tooltip: 'Profile & Account',
                    onPressed: onOpenProfile,
                  ),
                  if (onLogout != null)
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
                        onPressed: onLogout,
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

class _NarrowDestination extends StatelessWidget {
  final AppNavItem item;
  final bool selected;
  final VoidCallback onTap;

  const _NarrowDestination({
    required this.item,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final navId = TestIds.navIdForIndex(item.routeIndex);
    Widget label = Text(
      item.shortLabel,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      textAlign: TextAlign.center,
      style: theme.textTheme.labelSmall?.copyWith(
        color: selected ? colorScheme.onSurface : colorScheme.onSurfaceVariant,
        fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
        height: 1.15,
      ),
    );
    if (navId != null) {
      label = TestSemantics.navTarget(
        identifier: navId,
        label: item.shortLabel,
        child: label,
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 2.0),
      child: InkWell(
        key: ValueKey('narrow_nav_${item.shortLabel}'),
        onTap: onTap,
        borderRadius: const BorderRadius.all(Radius.circular(16.0)),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4.0, horizontal: 2.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                height: 32.0,
                width: 56.0,
                child: Material(
                  color: selected
                      ? colorScheme.secondaryContainer
                      : Colors.transparent,
                  shape: const StadiumBorder(),
                  child: Icon(
                    selected ? item.selectedIcon : item.icon,
                    size: 22.0,
                    color: selected
                        ? colorScheme.onSecondaryContainer
                        : colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              const SizedBox(height: 2.0),
              label,
            ],
          ),
        ),
      ),
    );
  }
}
