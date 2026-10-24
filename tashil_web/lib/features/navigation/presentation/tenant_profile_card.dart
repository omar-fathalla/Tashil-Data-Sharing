import 'package:flutter/material.dart';
import '../../../core/theme/m3_status_colors.dart';
import '../../../core/theme/m3_shape.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/theme/m3_color_roles.dart';
import '../../../../core/theme/m3_spacing.dart';

/// TenantProfileCard displays current enterprise branding (Adeco, Unilever, PepsiCo, or dynamically provisioned companies),
/// active user role, provides seamless tenant switching, and profile editing.
class TenantProfileCard extends StatelessWidget {
  final String activeTenant;
  final TenantUserModel? currentUser;
  final ValueChanged<String> onTenantChanged;
  final VoidCallback? onOpenProfile;
  final VoidCallback? onNavigateToAdmin;

  final bool isSuperAdmin;

  const TenantProfileCard({
    super.key,
    required this.activeTenant,
    this.currentUser,
    required this.onTenantChanged,
    this.onOpenProfile,
    this.onNavigateToAdmin,
    this.isSuperAdmin = false,
  });

  static String _cleanUserNameEn(TenantUserModel? user, String companyEn) {
    final raw = (user?.fullName ?? '').trim();
    if (raw.isEmpty ||
        raw.contains('مدير') ||
        raw.contains('مشرف') ||
        raw.contains('مسؤول')) {
      return '$companyEn Admin';
    }
    return raw;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final normalizedActive = ApiClient.normalizeDataTenantSlug(activeTenant);
    final brandSeedColor = TenantBrandSeeds.getSeedForTenant(normalizedActive);
    final currentDisplayName =
        ApiClient.getEnglishDisplayNameForTenant(normalizedActive);
    final userNameEn = _cleanUserNameEn(currentUser, currentDisplayName);
    final roleEn = currentUser?.roleDisplayEn ?? 'Vendor Admin';

    return Container(
      padding: M3Spacing.pSm,
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: M3Shape.radiusMd,
        border: Border.all(color: colorScheme.outlineVariant.withOpacity(0.6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: onOpenProfile,
            borderRadius: M3Shape.radiusSm,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4.0),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 18.0,
                    backgroundColor: brandSeedColor,
                    child: Text(
                      normalizedActive.isNotEmpty
                          ? normalizedActive[0].toUpperCase()
                          : 'A',
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  M3Spacing.gapXS,
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                currentDisplayName,
                                style: theme.textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 6.0),
                            Container(
                              width: 7.0,
                              height: 7.0,
                              decoration: BoxDecoration(
                                color: M3StatusColors.of(context).success,
                                shape: BoxShape.circle,
                              ),
                            ),
                          ],
                        ),
                        Text(
                          '$userNameEn • $roleEn',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                            fontSize: 10.5,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  if (onOpenProfile != null)
                    IconButton(
                      icon: const Icon(Icons.manage_accounts_rounded, size: 20.0),
                      tooltip: 'User Profile & Settings',
                      onPressed: onOpenProfile,
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
