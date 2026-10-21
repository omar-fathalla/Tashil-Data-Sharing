import 'package:flutter/material.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/theme/m3_spacing.dart';
import '../../../../core/widgets/m3_button.dart';

/// TenantSecurityGuard enforces strict Zero Cross-Tenant Leakage.
/// If an authenticated user from 'adeco' attempts to access 'unilever' data,
/// access is blocked with a security audit notice.
class TenantSecurityGuard extends StatelessWidget {
  final ApiClient apiClient;
  final String activePortalSlug;
  final Widget child;
  final ValueChanged<String> onRedirectToAuthorizedPortal;

  const TenantSecurityGuard({
    super.key,
    required this.apiClient,
    required this.activePortalSlug,
    required this.child,
    required this.onRedirectToAuthorizedPortal,
  });

  @override
  Widget build(BuildContext context) {
    final user = apiClient.currentUser;

    // If no authenticated user yet, allow initial preview
    if (user == null) {
      return child;
    }

    // Super Admin has global platform visibility
    if (user.isSuperAdmin) {
      return child;
    }

    final userTenant = user.tenantId.toLowerCase().replaceAll('tenant-', '');
    final portalTenant = activePortalSlug.toLowerCase().replaceAll('tenant-', '');

    // Strict RLS Check
    if (userTenant != portalTenant) {
      final theme = Theme.of(context);
      final colorScheme = theme.colorScheme;

      return Scaffold(
        backgroundColor: colorScheme.surface,
        body: Center(
          child: Padding(
            padding: M3Spacing.pLg,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 500.0),
              child: Card(
                elevation: 0,
                color: colorScheme.errorContainer.withOpacity(0.4),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20.0),
                  side: BorderSide(color: colorScheme.error),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(32.0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(16.0),
                        decoration: BoxDecoration(
                          color: colorScheme.error.withOpacity(0.15),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.gpp_bad_rounded,
                          size: 48.0,
                          color: colorScheme.error,
                        ),
                      ),
                      M3Spacing.gapMD,
                      Text(
                        'حاجز أمني صارم (RLS Breach Detected)',
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: colorScheme.error,
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      M3Spacing.gapSM,
                      Text(
                        'أنت مسجل حالياً كمسؤول بشركة ($userTenant) ولا تملك صلاحية الوصول إلى بوابة شركة ($portalTenant).',
                        style: theme.textTheme.bodyMedium,
                        textAlign: TextAlign.center,
                      ),
                      M3Spacing.gapSM,
                      Text(
                        'لحماية خصوصية شركاء التجزئة وسرية بيانات المبيعات، يتم حظر هذا الطلب فوراً وفق معايير الأمان المعتمدة.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      M3Spacing.gapLG,
                      M3Button.primary(
                        label: 'العودة إلى بوابة شركتك ($userTenant)',
                        icon: Icons.security_rounded,
                        onPressed: () => onRedirectToAuthorizedPortal(userTenant),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    return child;
  }
}
