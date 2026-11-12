import 'package:flutter/material.dart';
import '../testing/test_semantics.dart';
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
          // Uses dialogTheme (28dp, surfaceContainerHigh, no border).
          icon: Icon(
            Icons.warning_amber_rounded,
            size: 36.0,
            color: colorScheme.error,
          ),
          title: Text(
            title,
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineSmall,
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
              if (duplicateIdentifier != null &&
                  duplicateIdentifier.isNotEmpty) ...[
                M3Spacing.gapSM,
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12.0, vertical: 8.0),
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerHighest
                        .withValues(alpha: 0.5),
                    borderRadius: M3Shape.radiusSm,
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
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('إغلاق وتخطي التكرار'),
            ),
          ],
        );
      },
    );
  }

  static Widget _snackbarBody({
    required String identifier,
    required String message,
    required IconData icon,
    required Color iconColor,
    required Color textColor,
  }) {
    return TestSemantics(
      identifier: identifier,
      label: message,
      container: true,
      child: Row(
        children: [
          Icon(icon, color: iconColor, size: 20.0),
          const SizedBox(width: 8.0),
          Expanded(
            child: Text(
              message,
              style: TextStyle(color: textColor, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  /// Floating success snackbar — inverseSurface from theme; status via icon only.
  static void showSuccess(BuildContext context, String message) {
    final colorScheme = Theme.of(context).colorScheme;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: _snackbarBody(
          identifier: TestIds.snackbarSuccess,
          message: message,
          icon: Icons.check_circle_rounded,
          iconColor: colorScheme.inversePrimary,
          textColor: colorScheme.onInverseSurface,
        ),
        // background / shape from snackBarTheme
      ),
    );
  }

  /// Floating error snackbar — inverseSurface; error conveyed by icon.
  static void showError(BuildContext context, String message) {
    final colorScheme = Theme.of(context).colorScheme;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: _snackbarBody(
          identifier: TestIds.snackbarError,
          message: message,
          icon: Icons.error_outline_rounded,
          // errorContainer on inverseSurface ≈ 10:1 (colorScheme.error ≈ 2:1).
          iconColor: colorScheme.errorContainer,
          textColor: colorScheme.onInverseSurface,
        ),
      ),
    );
  }

  /// Floating warning snackbar — inverseSurface (no amber fill).
  static void showWarning(BuildContext context, String message) {
    final colorScheme = Theme.of(context).colorScheme;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: _snackbarBody(
          identifier: TestIds.snackbarMessage,
          message: message,
          icon: Icons.warning_amber_rounded,
          iconColor: colorScheme.inversePrimary,
          textColor: colorScheme.onInverseSurface,
        ),
      ),
    );
  }

  /// Floating info snackbar — inverseSurface; status via icon.
  static void showInfo(BuildContext context, String message) {
    final colorScheme = Theme.of(context).colorScheme;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: _snackbarBody(
          identifier: TestIds.snackbarMessage,
          message: message,
          icon: Icons.info_outline_rounded,
          iconColor: colorScheme.inversePrimary,
          textColor: colorScheme.onInverseSurface,
        ),
      ),
    );
  }
}
