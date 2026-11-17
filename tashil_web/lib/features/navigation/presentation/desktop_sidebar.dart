import 'package:flutter/material.dart';
import '../../../core/config/app_version.dart';
import '../../../core/network/api_client.dart';
import '../../../core/testing/test_semantics.dart';
import '../../../core/theme/m3_motion.dart';
import '../../../core/theme/m3_spacing.dart';
import '../nav_catalog.dart';
import 'tenant_profile_card.dart';

/// DesktopSidebar provides a permanent Material Design 3 Navigation Drawer
/// with an RTL layout (width: 250dp) designed for executive management portals.
class DesktopSidebar extends StatelessWidget {
  /// Live rows are 52dp. Variant C chips plus a divider between every section
  /// overflow a 1280×800 sidebar at that height (the list would scroll).
  /// 36dp is the reviewed mockup row and keeps every destination on screen.
  static const double destinationHeight = 36.0;

  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;
  final String activeTenant;
  final TenantUserModel? currentUser;
  final ValueChanged<String> onTenantChanged;
  final VoidCallback? onOpenProfile;
  final VoidCallback? onNavigateToAdmin;
  final bool isSuperAdmin;

  /// Optional tenant logo (`TenantProfileModel.logoUrl`). Null falls back to
  /// the catalog profile; empty shows the letter avatar.
  final String? tenantLogoUrl;

  /// Test / preview image. Wins over [tenantLogoUrl].
  final ImageProvider<Object>? tenantLogoImage;

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
    this.tenantLogoUrl,
    this.tenantLogoImage,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

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
            // Tenant brand. LTR inside the card so the English name sits on the left.
            Padding(
              padding:
                  const EdgeInsetsDirectional.fromSTEB(16.0, 24.0, 16.0, 16.0),
              child: TenantProfileCard(
                activeTenant: activeTenant,
                currentUser: currentUser,
                onTenantChanged: onTenantChanged,
                onOpenProfile: onOpenProfile,
                onNavigateToAdmin: onNavigateToAdmin,
                isSuperAdmin: isSuperAdmin,
                logoUrl: tenantLogoUrl,
                logoImage: tenantLogoImage,
              ),
            ),

            // Navigation Items
            Expanded(
              child: ListView(
                padding:
                    const EdgeInsetsDirectional.fromSTEB(12.0, 0.0, 12.0, 12.0),
                children: navSectionChildren(
                  itemBuilder: (dest) => Padding(
                    padding: const EdgeInsets.only(bottom: 2.0),
                    child: _SidebarDestination(
                      item: dest,
                      selected: selectedIndex == dest.routeIndex,
                      onSelected: () => onDestinationSelected(dest.routeIndex),
                    ),
                  ),
                ),
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
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
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
                  const SizedBox(height: 4.0),
                  ValueListenableBuilder<String>(
                    valueListenable: AppVersion.listenable,
                    builder: (context, versionLabel, _) {
                      return Text(
                        'Tashil • Data Sharing Platform • $versionLabel',
                        key: const ValueKey('sidebar-app-version'),
                        textDirection: TextDirection.ltr,
                        textAlign: TextAlign.left,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w300,
                        ),
                      );
                    },
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

class _SidebarDestination extends StatelessWidget {
  final AppNavItem item;
  final bool selected;
  final VoidCallback onSelected;

  const _SidebarDestination({
    required this.item,
    required this.selected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    // M3 nav indicator: a pill-shaped Material (no BoxDecoration).
    // Own the web flt-semantics tap (onTap) so page overlays /
    // mis-sized content semantics cannot swallow sidebar clicks
    // (live: Pricing → Compare stayed put while OOS still worked).
    Widget tile = Material(
      key: ValueKey('sidebar_nav_${item.sidebarLabel}'),
      color: selected ? colorScheme.secondaryContainer : Colors.transparent,
      shape: const StadiumBorder(),
      clipBehavior: Clip.antiAlias,
      animationDuration: M3Motion.short4,
      child: InkWell(
        onTap: onSelected,
        customBorder: const StadiumBorder(),
        child: Container(
          height: DesktopSidebar.destinationHeight,
          padding: const EdgeInsetsDirectional.symmetric(horizontal: 16.0),
          child: Row(
            children: [
              AnimatedSwitcher(
                duration: M3Motion.short3,
                transitionBuilder: (child, anim) => ScaleTransition(
                  scale: Tween<double>(begin: 0.85, end: 1.0).animate(anim),
                  child: FadeTransition(opacity: anim, child: child),
                ),
                child: Icon(
                  selected ? item.selectedIcon : item.icon,
                  key: ValueKey('${item.routeIndex}_$selected'),
                  size: 22.0,
                  color: selected
                      ? colorScheme.onSecondaryContainer
                      : colorScheme.onSurfaceVariant,
                ),
              ),
              M3Spacing.gapSM,
              Expanded(
                child: Text(
                  item.sidebarLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: selected
                        ? colorScheme.onSecondaryContainer
                        : colorScheme.onSurface,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              ),
              if (item.badgeCount != null && item.badgeCount! > 0)
                Badge.count(count: item.badgeCount!),
            ],
          ),
        ),
      ),
    );
    return Semantics(
      identifier: TestIds.navIdForIndex(item.routeIndex),
      label: item.sidebarLabel,
      button: true,
      container: true,
      excludeSemantics: true,
      onTap: onSelected,
      child: tile,
    );
  }
}
