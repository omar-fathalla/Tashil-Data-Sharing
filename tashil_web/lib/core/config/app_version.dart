import 'package:flutter/foundation.dart';

import 'app_version_host_stub.dart'
    if (dart.library.html) 'app_version_host_web.dart' as host;

/// Deploy version shown in the sidebar.
///
/// Build-time fallback comes from `--dart-define=APP_VERSION=<n>`
/// (`scripts/flutter_build_web.sh` / deploy). Local runs show `dev`.
///
/// On web, the **deployed** source of truth is hosting `version.json`
/// (`app_version`) and the matching `data-app-version` stamp on
/// `index.html`. Partial web-only deploys that bump those without
/// rebuilding the dart-define must not leave the sidebar stuck on an
/// older `vNNN`.
class AppVersion {
  AppVersion._();

  static const String raw =
      String.fromEnvironment('APP_VERSION', defaultValue: 'dev');

  static String? _deployed;

  /// Notifies listeners when [label] changes after hydration.
  static final ValueNotifier<String> listenable =
      ValueNotifier<String>(labelFor(raw));

  /// Label shown in the sidebar, e.g. `v189` or `dev`.
  static String get label => labelFor(_deployed ?? raw);

  static String labelFor(String value) =>
      int.tryParse(value) != null ? 'v$value' : value;

  /// Applies a numeric deployed `app_version` (from DOM / version.json / tests).
  static void applyDeployedAppVersion(String? value) {
    final v = (value ?? '').trim();
    if (v.isEmpty || int.tryParse(v) == null) return;
    if (_deployed == v) return;
    _deployed = v;
    listenable.value = labelFor(v);
  }

  /// Sync read of `<html data-app-version>` (web only).
  static void hydrateFromDocument() {
    applyDeployedAppVersion(host.readDocumentAppVersion());
  }

  /// Async read of hosting `version.json` (web only).
  static Future<void> hydrateFromVersionJson() async {
    applyDeployedAppVersion(await host.fetchVersionJsonAppVersion());
  }

  /// Test helper — clears the deployed override.
  @visibleForTesting
  static void debugReset() {
    _deployed = null;
    listenable.value = labelFor(raw);
  }
}
