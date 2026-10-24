import 'package:flutter/material.dart';
import '../theme/m3_spacing.dart';
import 'app_icons.dart';

/// Centered empty state (icon, title, optional message + action).
class M3EmptyState extends StatelessWidget {
  const M3EmptyState({
    super.key,
    required this.title,
    this.message,
    this.icon = AppIcons.empty,
    this.action,
  });

  final String title;
  final String? message;
  final IconData icon;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Center(
      child: Padding(
        padding: M3Spacing.pMd,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48.0, color: cs.onSurfaceVariant),
            M3Spacing.gapSM,
            Text(title,
                textAlign: TextAlign.center,
                style: theme.textTheme.titleMedium),
            if (message != null) ...[
              M3Spacing.gapXS,
              Text(message!,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium),
            ],
            if (action != null) ...[M3Spacing.gapSM, action!],
          ],
        ),
      ),
    );
  }
}

/// Loading state: linear (inline/top of section) or circular (centered).
class M3LoadingState extends StatelessWidget {
  const M3LoadingState({super.key, this.message, this.linear = false});

  final String? message;
  final bool linear;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (linear) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const LinearProgressIndicator(),
          if (message != null)
            Padding(
              padding: const EdgeInsets.only(top: M3Spacing.xs),
              child: Text(message!, style: theme.textTheme.bodySmall),
            ),
        ],
      );
    }
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(),
          if (message != null) ...[
            M3Spacing.gapSM,
            Text(message!,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium),
          ],
        ],
      ),
    );
  }
}

/// Full-section error state with optional retry.
class M3ErrorState extends StatelessWidget {
  const M3ErrorState({
    super.key,
    required this.title,
    this.message,
    this.onRetry,
    this.retryLabel = 'إعادة المحاولة',
  });

  final String title;
  final String? message;
  final VoidCallback? onRetry;
  final String retryLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Center(
      child: Padding(
        padding: M3Spacing.pMd,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(AppIcons.error, size: 48.0, color: cs.error),
            M3Spacing.gapSM,
            Text(title,
                textAlign: TextAlign.center,
                style: theme.textTheme.titleMedium),
            if (message != null) ...[
              M3Spacing.gapXS,
              Text(message!,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium),
            ],
            if (onRetry != null) ...[
              M3Spacing.gapSM,
              FilledButton.tonalIcon(
                onPressed: onRetry,
                icon: const Icon(AppIcons.refresh),
                label: Text(retryLabel),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Inline M3 [MaterialBanner] for connection / server errors.
/// Replaces the old ServerDisconnectedCard.
class M3ErrorBanner extends StatelessWidget {
  const M3ErrorBanner({
    super.key,
    this.title = 'تعذر الاتصال بالخادم',
    this.message,
    this.technicalDetails,
    this.onRetry,
    this.onDismiss,
    this.retryLabel = 'إعادة المحاولة',
    this.icon = AppIcons.cloudOff,
  });

  final String title;
  final String? message;
  final String? technicalDetails;
  final VoidCallback? onRetry;
  final VoidCallback? onDismiss;
  final String retryLabel;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final actions = <Widget>[
      if (onDismiss != null)
        TextButton(onPressed: onDismiss, child: const Text('إغلاق')),
      if (onRetry != null)
        TextButton(onPressed: onRetry, child: Text(retryLabel)),
    ];
    return MaterialBanner(
      backgroundColor: cs.errorContainer,
      leading: Icon(icon, color: cs.onErrorContainer),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: theme.textTheme.titleSmall
                  ?.copyWith(color: cs.onErrorContainer)),
          if (message != null)
            Text(message!,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: cs.onErrorContainer)),
          if (technicalDetails != null)
            Text(technicalDetails!,
                style: theme.textTheme.bodySmall?.copyWith(
                    color: cs.onErrorContainer, fontFamily: 'monospace')),
        ],
      ),
      actions: actions.isEmpty ? const [SizedBox.shrink()] : actions,
    );
  }
}
