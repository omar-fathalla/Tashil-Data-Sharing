import 'package:flutter/material.dart';

import '../../../core/network/api_client.dart';
import '../../../core/theme/m3_shape.dart';
import '../../../core/theme/m3_spacing.dart';
import 'tenant_logo_slot.dart';

/// Sidebar tenant brand: one logo slot plus the English tenant name.
///
/// The header is forced LTR so an English name such as "Adeco" stays
/// left-aligned inside the RTL shell. Tapping it opens the account dialog
/// (profile, password, role, sign out) — the action that used to sit on the
/// person-gear icon.
class TenantProfileCard extends StatelessWidget {
  final String activeTenant;
  final TenantUserModel? currentUser;
  final ValueChanged<String> onTenantChanged;
  final VoidCallback? onOpenProfile;
  final VoidCallback? onNavigateToAdmin;
  final bool isSuperAdmin;
  final String? logoUrl;
  final ImageProvider<Object>? logoImage;

  const TenantProfileCard({
    super.key,
    required this.activeTenant,
    this.currentUser,
    required this.onTenantChanged,
    this.onOpenProfile,
    this.onNavigateToAdmin,
    this.isSuperAdmin = false,
    this.logoUrl,
    this.logoImage,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final normalizedActive = ApiClient.normalizeDataTenantSlug(activeTenant);
    final displayName =
        ApiClient.getEnglishDisplayNameForTenant(normalizedActive);
    final accountWho = (currentUser?.fullName ?? currentUser?.email ?? '').trim();
    final accountLabel = accountWho.isEmpty
        ? '$displayName, account'
        : '$displayName, account, $accountWho';

    final header = Material(
      type: MaterialType.transparency,
      child: InkWell(
        key: const ValueKey('sidebar_tenant_header'),
        onTap: onOpenProfile,
        borderRadius: M3Shape.radiusMd,
        child: Semantics(
          button: onOpenProfile != null,
              label: accountLabel,
          onTap: onOpenProfile,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4.0),
            child: Row(
              children: [
                TenantLogoSlot(
                  tenantSlug: normalizedActive,
                  logoUrl: logoUrl,
                  logoImage: logoImage,
                  radius: 20.0,
                ),
                M3Spacing.hGapSM,
                Expanded(
                  child: Text(
                    displayName,
                    key: const ValueKey('sidebar_tenant_name'),
                    textDirection: TextDirection.ltr,
                    textAlign: TextAlign.left,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    return Directionality(
      textDirection: TextDirection.ltr,
      child: onOpenProfile == null
          ? header
          : Tooltip(message: 'Account & profile', child: header),
    );
  }
}
