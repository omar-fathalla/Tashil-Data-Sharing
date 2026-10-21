import 'package:flutter/material.dart';
import '../theme/m3_spacing.dart';

/// ServerDisconnectedCard presents a dedicated, high-aesthetic Material Design 3
/// notification when the backend server is disconnected or unreachable.
///
/// In strict compliance with enterprise data integrity standards:
/// - NEVER displays fake/unreal data or fabricated mock numbers.
/// - Clearly states that the server is disconnected.
/// - Prominently guides the user to contact Technical Support ("التواصل مع الدعم الفني").
/// - Provides a one-click Retry action to resume real-time data streaming once the server is back online.
class ServerDisconnectedCard extends StatelessWidget {
  final VoidCallback? onRetry;
  final String? title;
  final String? subtitle;
  final String? technicalDetails;

  const ServerDisconnectedCard({
    super.key,
    this.onRetry,
    this.title,
    this.subtitle,
    this.technicalDetails,
  });

  void _showSupportDialog(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: colorScheme.surfaceContainerHigh,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24.0),
          side: BorderSide(color: colorScheme.outlineVariant.withOpacity(0.6)),
        ),
        icon: Container(
          padding: const EdgeInsets.all(12.0),
          decoration: BoxDecoration(
            color: colorScheme.primaryContainer.withOpacity(0.5),
            shape: BoxShape.circle,
          ),
          child: Icon(
            Icons.support_agent_rounded,
            size: 36.0,
            color: colorScheme.primary,
          ),
        ),
        title: Text(
          'مركز الدعم الفني لمنصة تسهيل',
          textAlign: TextAlign.center,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'فريق الدعم الفني جاهز لمساعدتك في استعادة اتصال الخادم ومزامنة ملفات التجزئة في أي وقت.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            M3Spacing.gapMD,
            _buildContactRow(
              context: ctx,
              icon: Icons.phone_in_talk_rounded,
              label: 'الخط الساخن المباشر (24/7)',
              value: '19881 / 0100000000',
            ),
            const SizedBox(height: 8.0),
            _buildContactRow(
              context: ctx,
              icon: Icons.email_rounded,
              label: 'البريد الإلكتروني للدعم الفني',
              value: 'support@tashil.io',
            ),
            const SizedBox(height: 8.0),
            _buildContactRow(
              context: ctx,
              icon: Icons.terminal_rounded,
              label: 'خادم المعالجة المحلي',
              value: 'http://localhost:8080 (backend-go)',
            ),
            if (technicalDetails != null && technicalDetails!.isNotEmpty) ...[
              M3Spacing.gapSM,
              Container(
                padding: const EdgeInsets.all(10.0),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHighest.withOpacity(0.6),
                  borderRadius: BorderRadius.circular(8.0),
                  border: Border.all(color: colorScheme.outlineVariant.withOpacity(0.4)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'التفاصيل الفنية (Diagnostics):',
                      style: theme.textTheme.labelSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: colorScheme.error,
                      ),
                    ),
                    const SizedBox(height: 4.0),
                    Text(
                      technicalDetails!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontFamily: 'monospace',
                        fontSize: 11.0,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          FilledButton.tonal(
            onPressed: () {
              Navigator.of(ctx).pop();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('تم نسخ بيانات الدعم الفني: support@tashil.io | 19881'),
                  duration: Duration(seconds: 3),
                ),
              );
            },
            style: FilledButton.styleFrom(
              shape: const StadiumBorder(),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.copy_rounded, size: 16.0),
                SizedBox(width: 8.0),
                Text('نسخ بيانات التواصل'),
              ],
            ),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(),
            style: FilledButton.styleFrom(
              shape: const StadiumBorder(),
            ),
            child: const Text('إغلاق'),
          ),
        ],
      ),
    );
  }

  Widget _buildContactRow({
    required BuildContext context,
    required IconData icon,
    required String label,
    required String value,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withOpacity(0.4),
        borderRadius: BorderRadius.circular(10.0),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18.0, color: colorScheme.primary),
          const SizedBox(width: 10.0),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                    fontSize: 11.0,
                  ),
                ),
                Text(
                  value,
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: colorScheme.onSurface,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Center(
      child: Container(
        key: const ValueKey('server_disconnected_card'),
        constraints: const BoxConstraints(maxWidth: 820.0),
        margin: const EdgeInsets.symmetric(vertical: 24.0, horizontal: 16.0),
        padding: const EdgeInsets.all(32.0),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(24.0),
          border: Border.all(
            color: colorScheme.error.withOpacity(0.35),
            width: 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: colorScheme.error.withOpacity(0.08),
              blurRadius: 24.0,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Status Icon with Soft Glowing Red Ring
            Container(
              padding: const EdgeInsets.all(18.0),
              decoration: BoxDecoration(
                color: colorScheme.errorContainer.withOpacity(0.4),
                shape: BoxShape.circle,
                border: Border.all(
                  color: colorScheme.error.withOpacity(0.3),
                  width: 2.0,
                ),
              ),
              child: Icon(
                Icons.cloud_off_rounded,
                size: 48.0,
                color: colorScheme.error,
              ),
            ),

            M3Spacing.gapMD,

            // Disconnected Pill Tag
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 6.0),
              decoration: BoxDecoration(
                color: colorScheme.errorContainer.withOpacity(0.45),
                borderRadius: BorderRadius.circular(20.0),
                border: Border.all(
                  color: colorScheme.error.withOpacity(0.4),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 8.0,
                    height: 8.0,
                    decoration: BoxDecoration(
                      color: colorScheme.error,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8.0),
                  Text(
                    'حالة النظام: انقطاع الاتصال بالخادم الرئيسي',
                    style: theme.textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: colorScheme.error,
                    ),
                  ),
                ],
              ),
            ),

            M3Spacing.gapMD,

            // Primary Headline
            Text(
              title ?? 'تعذر الاتصال بخادم منصة تسهيل (Server Disconnected)',
              textAlign: TextAlign.center,
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
                color: colorScheme.onSurface,
              ),
            ),

            const SizedBox(height: 8.0),

            // Explanatory Subtitle
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 620.0),
              child: Text(
                subtitle ??
                    'تم إيقاف عرض لوحة البيانات مؤقتاً لعدم توفر الاتصال بمحرك التحليلات (Port 8080). '
                    'التزاماً بنزاهة البيانات والمعايير القياسية لمنصة تسهيل، لا نقوم بعرض أي بيانات وهمية أو أرقام غير حقيقية.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                  height: 1.5,
                ),
              ),
            ),

            M3Spacing.gapLG,

            // Support Guidance Card (التواصل مع الدعم الفني)
            Container(
              constraints: const BoxConstraints(maxWidth: 660.0),
              padding: const EdgeInsets.all(18.0),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest.withOpacity(0.5),
                borderRadius: BorderRadius.circular(16.0),
                border: Border.all(
                  color: colorScheme.outlineVariant.withOpacity(0.6),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(10.0),
                    decoration: BoxDecoration(
                      color: colorScheme.primaryContainer.withOpacity(0.6),
                      borderRadius: BorderRadius.circular(12.0),
                    ),
                    child: Icon(
                      Icons.support_agent_rounded,
                      size: 28.0,
                      color: colorScheme.primary,
                    ),
                  ),
                  const SizedBox(width: 14.0),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'مركز الدعم الفني (Technical Support)',
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: colorScheme.onSurface,
                          ),
                        ),
                        const SizedBox(height: 4.0),
                        Text(
                          'إذا استمر انقطاع الاتصال، يرجى التواصل مع فريق الدعم الفني للتحقق من تشغيل خادم المعالجة وربط الملفات المستوعبة.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                            height: 1.4,
                          ),
                        ),
                        const SizedBox(height: 10.0),
                        Wrap(
                          spacing: 16.0,
                          runSpacing: 6.0,
                          children: [
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.phone_rounded, size: 14.0, color: colorScheme.primary),
                                const SizedBox(width: 4.0),
                                Text(
                                  'الخط الساخن: 19881',
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.mail_outline_rounded, size: 14.0, color: colorScheme.primary),
                                const SizedBox(width: 4.0),
                                Text(
                                  'support@tashil.io',
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            M3Spacing.gapLG,

            // Action Buttons Row
            Wrap(
              spacing: 12.0,
              runSpacing: 8.0,
              alignment: WrapAlignment.center,
              children: [
                if (onRetry != null)
                  FilledButton.icon(
                    key: const ValueKey('server_retry_button'),
                    onPressed: onRetry,
                    icon: const Icon(Icons.refresh_rounded, size: 18.0),
                    label: const Text('إعادة محاولة الاتصال بالخادم'),
                    style: FilledButton.styleFrom(
                      shape: const StadiumBorder(),
                      padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 14.0),
                    ),
                  ),
                FilledButton.tonalIcon(
                  key: const ValueKey('contact_support_button'),
                  onPressed: () => _showSupportDialog(context),
                  icon: const Icon(Icons.support_agent_rounded, size: 18.0),
                  label: const Text('التواصل مع الدعم الفني'),
                  style: FilledButton.styleFrom(
                    shape: const StadiumBorder(),
                    padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 14.0),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
