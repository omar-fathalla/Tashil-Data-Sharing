import 'package:flutter/material.dart';

/// Stable automation identifiers for Flutter web Semantics
/// (`flt-semantics-identifier` / accessible name via [label]).
///
/// Naming scheme (kebab-case):
/// - Auth: `login-*`, `logout`
/// - Nav: `nav-<area>`
/// - Sell-Out / Sell-In upload: `sellout-*` / `sellin-*`
/// - File list: `uploaded-files-*`, `file-row-<archiveId>-<name>`,
///   `file-delete-<archiveId>-<name>`
/// - Dialogs: `delete-confirm`, `delete-cancel`
/// - Feedback: `snackbar-error`, `snackbar-success`, `snackbar-message`
///
/// See `docs/SEMANTICS_TEST_IDS.md` in the repo root.
class TestIds {
  TestIds._();

  static const loginEmail = 'login-email';
  static const loginPassword = 'login-password';
  static const loginSubmit = 'login-submit';
  static const logout = 'logout';

  static const navSellOut = 'nav-sell-out';
  static const navSellIn = 'nav-sell-in';
  static const navReturns = 'nav-returns';

  static const selloutUploadButton = 'sellout-upload-button';
  static const sellinUploadButton = 'sellin-upload-button';
  static const uploadChooseFile = 'upload-choose-file';

  /// DOM id / data-testid of the persistent hidden `<input type="file">`
  /// (`#tashil-file-input`). Prefer Playwright `setInputFiles` on this node.
  static const fileInput = 'tashil-file-input';

  /// Confirm / cancel for Sell-Out staged preview commit dialog.
  static const uploadCommitConfirm = 'upload-commit-confirm';
  static const uploadCommitCancel = 'upload-commit-cancel';

  static const selloutUploadedFiles = 'sellout-uploaded-files';
  static const sellinUploadedFiles = 'sellin-uploaded-files';
  static const uploadedFilesList = 'uploaded-files-list';

  static const deleteConfirm = 'delete-confirm';
  static const deleteCancel = 'delete-cancel';

  static const snackbarError = 'snackbar-error';
  static const snackbarSuccess = 'snackbar-success';
  static const snackbarMessage = 'snackbar-message';

  /// Stable catalog of page-level ids (excludes dynamic `file-row-*` /
  /// `file-delete-*`). Useful for smoke coverage lists.
  static const List<String> loginPageIds = [
    loginEmail,
    loginPassword,
    loginSubmit,
  ];

  static const List<String> keyCatalogIds = [
    loginEmail,
    loginPassword,
    loginSubmit,
    logout,
    navSellOut,
    navSellIn,
    navReturns,
    selloutUploadButton,
    sellinUploadButton,
    uploadChooseFile,
    uploadCommitConfirm,
    uploadCommitCancel,
    selloutUploadedFiles,
    sellinUploadedFiles,
    uploadedFilesList,
    deleteConfirm,
    deleteCancel,
    snackbarError,
    snackbarSuccess,
    snackbarMessage,
  ];

  /// Nav destination id for shell index, or null when uninstrumented.
  static String? navIdForIndex(int index) {
    switch (index) {
      case 1:
        return navSellOut;
      case 2:
        return navSellIn;
      case 3:
        return navReturns;
      default:
        return null;
    }
  }

  /// Sanitizes a file name or archive id token for use in dynamic ids.
  static String fileToken(String value) {
    final token = value
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9._-]+'), '-')
        .replaceAll(RegExp(r'-{2,}'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    return token.isEmpty ? 'unnamed' : token;
  }

  /// Unique row id: includes archive id so identical file names do not collide.
  static String fileRow({
    required String archiveId,
    required String fileName,
  }) =>
      'file-row-${fileToken(archiveId)}-${fileToken(fileName)}';

  /// Unique delete-action id for an archive row.
  /// Pattern: `file-delete-<archiveId>-<slugified-filename>`.
  static String fileDelete({
    required String archiveId,
    required String fileName,
  }) =>
      'file-delete-${fileToken(archiveId)}-${fileToken(fileName)}';
}

/// Thin wrapper that attaches a stable [identifier] (and optional [label])
/// for web automation without changing visual layout.
///
/// For tappable controls prefer [TestSemantics.button]: it sets `button: true`,
/// wires [onTap] (so Flutter web emits `role="button"` with a real click
/// handler), uses a semantics [container] boundary, and excludes child
/// semantics so DataTable cells cannot absorb the node into `role="cell"`.
class TestSemantics extends StatelessWidget {
  final String identifier;
  final String? label;
  final bool button;
  final bool textField;
  final bool container;
  final bool excludeSemantics;
  final bool enabled;
  final VoidCallback? onTap;
  final Widget child;

  const TestSemantics({
    super.key,
    required this.identifier,
    required this.child,
    this.label,
    this.button = false,
    this.textField = false,
    this.container = false,
    this.excludeSemantics = false,
    this.enabled = true,
    this.onTap,
  });

  /// Interactive control for Playwright / screen readers.
  ///
  /// Always pass [onPressed] so the semantics node owns the tap action
  /// (required for web `flt-semantics` to be clickable without falling
  /// through to `flutter-view`).
  const TestSemantics.button({
    super.key,
    required this.identifier,
    required this.label,
    required VoidCallback? onPressed,
    required this.child,
    bool excludeChildSemantics = true,
  })  : button = true,
        textField = false,
        container = true,
        excludeSemantics = excludeChildSemantics,
        enabled = onPressed != null,
        onTap = onPressed;

  /// Text field that owns focus via [onFocus] so Playwright
  /// `locator.click()` hits a real semantics action (not flutter-view).
  const TestSemantics.textField({
    super.key,
    required this.identifier,
    required this.label,
    required VoidCallback onFocus,
    required this.child,
    bool excludeChildSemantics = true,
  })  : button = false,
        textField = true,
        container = true,
        excludeSemantics = excludeChildSemantics,
        enabled = true,
        onTap = onFocus;

  /// Single interactive nav face — callers must attach this to exactly one
  /// child per destination (e.g. only `label` or only `icon`, never both
  /// `icon` + `selectedIcon` + `label`).
  const TestSemantics.navTarget({
    super.key,
    required this.identifier,
    required this.label,
    required this.child,
  })  : button = true,
        textField = false,
        container = true,
        excludeSemantics = false,
        enabled = true,
        onTap = null;

  @override
  Widget build(BuildContext context) {
    // Interactive nodes without an owned action get absorbed (e.g. DataTable
    // role=cell) or fall through to flutter-view on web.
    final ownsAction = onTap != null && (button || textField);
    final effectiveContainer = container || ownsAction;
    final effectiveExclude = excludeSemantics || ownsAction;

    return Semantics(
      identifier: identifier,
      label: label,
      button: button,
      textField: textField,
      container: effectiveContainer,
      excludeSemantics: effectiveExclude,
      enabled: enabled,
      onTap: onTap,
      child: child,
    );
  }
}
