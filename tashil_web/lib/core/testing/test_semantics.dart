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

  static const selloutUploadButton = 'sellout-upload-button';
  static const sellinUploadButton = 'sellin-upload-button';
  static const uploadChooseFile = 'upload-choose-file';

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
    selloutUploadButton,
    sellinUploadButton,
    uploadChooseFile,
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
  static String fileDelete({
    required String archiveId,
    required String fileName,
  }) =>
      'file-delete-${fileToken(archiveId)}-${fileToken(fileName)}';
}

/// Thin wrapper that attaches a stable [identifier] (and optional [label])
/// for web automation without changing visual layout.
class TestSemantics extends StatelessWidget {
  final String identifier;
  final String? label;
  final bool button;
  final bool textField;
  final bool container;
  final bool excludeSemantics;
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
  });

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
        container = false,
        excludeSemantics = false;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      identifier: identifier,
      label: label,
      button: button,
      textField: textField,
      container: container,
      excludeSemantics: excludeSemantics,
      child: child,
    );
  }
}
