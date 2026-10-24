import 'package:flutter/material.dart';
import '../theme/m3_shape.dart';
import '../theme/m3_spacing.dart';

/// M3Feedback provides accessible, theme-driven user feedback dialogs and SnackBars
/// adhering strictly to Material Design 3 and the Zero-Tolerance Duplicate Data Standard.
class M3Feedback {
  M3Feedback._();

  /// Displays an unambiguous, clear Arabic Warning Modal when a duplicate record or file
  /// is intercepted. In accordance with the Data Deduplication & Integrity Standard:
  /// - Strictly uses an amber warning icon (⚠️)
  /// - NEVER displays a purple or green checkmark
  /// - States clearly that the record is already registered and was rejected
  static Future<void> showDuplicateWarning(
    BuildContext context, {
    required String title,
    required String message,
    String? duplicateIdentifier,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: colorScheme.surfaceContainerHigh,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: M3Shape.radiusLg,
            side: BorderSide(color: colorScheme.outlineVariant, width: 1.0),
          ),
          icon: Container(
            padding: const EdgeInsets.all(12.0),
            decoration: BoxDecoration(
              color: colorScheme.errorContainer.withOpacity(0.4),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.warning_amber_rounded,
              size: 36.0,
              color: colorScheme.error,
            ),
          ),
          title: Text(
            title,
            textAlign: TextAlign.center,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
              color: colorScheme.onSurface,
            ),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                message,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              if (duplicateIdentifier != null && duplicateIdentifier.isNotEmpty) ...[
                M3Spacing.gapSM,
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerHighest.withOpacity(0.5),
                    borderRadius: M3Shape.radiusSm,
                    border: Border.all(color: colorScheme.outlineVariant.withOpacity(0.5)),
                  ),
                  child: Text(
                    duplicateIdentifier,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.labelMedium?.copyWith(
                      fontFamily: 'monospace',
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ],
          ),
          actionsAlignment: MainAxisAlignment.center,
          actions: [
            FilledButton.tonal(
              onPressed: () => Navigator.of(ctx).pop(),
              style: FilledButton.styleFrom(
                shape: const StadiumBorder(),
                padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 12.0),
              ),
              child: const Text('إغلاق وتخطي التكرار'),
            ),
          ],
        );
      },
    );
  }

  /// Displays an M3 compliant floating success snackbar.
  static void showSuccess(BuildContext context, String message) {
    final colorScheme = Theme.of(context).colorScheme;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(Icons.check_circle_rounded, color: colorScheme.onPrimaryContainer, size: 20.0),
            const SizedBox(width: 8.0),
            Expanded(
              child: Text(
                message,
                style: TextStyle(color: colorScheme.onPrimaryContainer, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
        backgroundColor: colorScheme.primaryContainer,
        behavior: SnackBarBehavior.floating,
        shape: const RoundedRectangleBorder(borderRadius: M3Shape.radiusMd),
      ),
    );
  }

  /// Displays an M3 compliant floating error snackbar.
  static void showError(BuildContext context, String message) {
    final colorScheme = Theme.of(context).colorScheme;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(Icons.error_outline_rounded, color: colorScheme.onErrorContainer, size: 20.0),
            const SizedBox(width: 8.0),
            Expanded(
              child: Text(
                message,
                style: TextStyle(color: colorScheme.onErrorContainer, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
        backgroundColor: colorScheme.errorContainer,
        behavior: SnackBarBehavior.floating,
        shape: const RoundedRectangleBorder(borderRadius: M3Shape.radiusMd),
      ),
    );
  }

  /// Displays an M3 compliant floating warning snackbar.
  static void showWarning(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.warning_amber_rounded, color: Colors.black87, size: 20.0),
            const SizedBox(width: 8.0),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(color: Colors.black87, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
        backgroundColor: Colors.amber.shade300,
        behavior: SnackBarBehavior.floating,
        shape: const RoundedRectangleBorder(borderRadius: M3Shape.radiusMd),
      ),
    );
  }

  /// Displays an M3 compliant floating info snackbar.
  static void showInfo(BuildContext context, String message) {
    final colorScheme = Theme.of(context).colorScheme;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(Icons.info_outline_rounded, color: colorScheme.onSecondaryContainer, size: 20.0),
            const SizedBox(width: 8.0),
            Expanded(
              child: Text(
                message,
                style: TextStyle(color: colorScheme.onSecondaryContainer, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
        backgroundColor: colorScheme.secondaryContainer,
        behavior: SnackBarBehavior.floating,
        shape: const RoundedRectangleBorder(borderRadius: M3Shape.radiusMd),
      ),
    );
  }
}
