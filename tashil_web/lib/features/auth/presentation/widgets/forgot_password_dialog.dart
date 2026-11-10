import 'package:flutter/material.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/theme/m3_spacing.dart';
import '../../../../core/widgets/m3_button.dart';

/// Contact-admin note for password recovery.
///
/// Self-serve reset previously relied on `reset_token` in the forgot-password
/// HTTP response. That field is no longer returned (security fix). There is no
/// outbound email channel yet, so in-app token reset would be dead — this dialog
/// directs the user to an admin instead. Do not wire an email provider without
/// Mohamed's approval. Super Admin can still force-reset via admin APIs.
class ForgotPasswordDialog extends StatelessWidget {
  final ApiClient apiClient;
  final String tenantSlug;
  final String? initialEmail;

  static const contactAdminMessageAr = 'تواصل مع المسؤول لإعادة تعيين كلمة المرور';
  static const contactAdminMessageEn =
      'Contact your administrator to reset your password';

  const ForgotPasswordDialog({
    super.key,
    required this.apiClient,
    required this.tenantSlug,
    this.initialEmail,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isArabic = Directionality.of(context) == TextDirection.rtl;

    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.lock_reset_rounded, color: colorScheme.primary),
          M3Spacing.gapSM,
          Expanded(
            child: Text(
              isArabic ? 'استعادة كلمة المرور' : 'Password recovery',
              style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 440.0,
        child: Text(
          isArabic ? contactAdminMessageAr : contactAdminMessageEn,
          style: theme.textTheme.bodyMedium,
        ),
      ),
      actions: [
        M3Button.primary(
          label: isArabic ? 'حسناً' : 'OK',
          onPressed: () => Navigator.pop(context),
        ),
      ],
    );
  }
}
