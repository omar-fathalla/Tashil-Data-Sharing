import 'package:flutter/material.dart';

/// Stable automation identifiers for Flutter web Semantics
/// (`flt-semantics-identifier` / accessible name via [label]).
///
/// Naming scheme (kebab-case):
/// - Auth: `login-*`, `logout`
/// - Nav: `nav-<area>`
/// - Sell-Out / Sell-In upload: `sellout-*` / `sellin-*`
/// - File list: `uploaded-files-*`, `file-row-<name>`, `file-delete-<name>`
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

  /// Sanitizes a file name for use in `file-row-*` / `file-delete-*` ids.
  static String fileToken(String fileName) {
    final token = fileName
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9._-]+'), '-')
        .replaceAll(RegExp(r'-{2,}'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    return token.isEmpty ? 'unnamed' : token;
  }

  static String fileRow(String fileName) => 'file-row-${fileToken(fileName)}';

  static String fileDelete(String fileName) =>
      'file-delete-${fileToken(fileName)}';
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
