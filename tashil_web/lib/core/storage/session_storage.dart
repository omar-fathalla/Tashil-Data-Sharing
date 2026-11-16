import 'dart:convert';

import 'session_storage_stub.dart'
    if (dart.library.html) 'session_storage_web.dart';

class SavedSessionState {
  final String activeTenant;
  final String? authToken;
  final Map<String, dynamic>? currentUserJson;
  final Map<String, dynamic>? currentTenantProfileJson;
  final bool showSuperAdmin;
  final bool isLoginMode;

  const SavedSessionState({
    required this.activeTenant,
    this.authToken,
    this.currentUserJson,
    this.currentTenantProfileJson,
    required this.showSuperAdmin,
    required this.isLoginMode,
  });

  Map<String, dynamic> toJson() => {
        'active_tenant': activeTenant,
        'auth_token': authToken,
        'current_user': currentUserJson,
        'current_tenant_profile': currentTenantProfileJson,
        'show_super_admin': showSuperAdmin,
        'is_login_mode': isLoginMode,
      };

  factory SavedSessionState.fromJson(Map<String, dynamic> json) {
    return SavedSessionState(
      activeTenant: json['active_tenant'] as String? ?? 'adeco',
      authToken: json['auth_token'] as String?,
      currentUserJson: json['current_user'] is Map<String, dynamic>
          ? json['current_user'] as Map<String, dynamic>
          : (json['current_user'] is Map
              ? Map<String, dynamic>.from(json['current_user'] as Map)
              : null),
      currentTenantProfileJson:
          json['current_tenant_profile'] is Map<String, dynamic>
              ? json['current_tenant_profile'] as Map<String, dynamic>
              : (json['current_tenant_profile'] is Map
                  ? Map<String, dynamic>.from(
                      json['current_tenant_profile'] as Map)
                  : null),
      showSuperAdmin: json['show_super_admin'] as bool? ?? false,
      isLoginMode: json['is_login_mode'] as bool? ?? false,
    );
  }
}

class SessionStorage {
  SessionStorage._();

  static const String _sessionKey = 'tashil_session_state_v1';
  static const String _provisionedTenantsKey = 'tashil_provisioned_tenants_v1';
  static const String _deletedTenantsKey = 'tashil_deleted_tenants_v1';

  static void saveSession(SavedSessionState state) {
    platformStorageSet(_sessionKey, jsonEncode(state.toJson()));
  }

  static SavedSessionState? loadSession() {
    final raw = platformStorageGet(_sessionKey);
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        return SavedSessionState.fromJson(decoded);
      }
      if (decoded is Map) {
        return SavedSessionState.fromJson(Map<String, dynamic>.from(decoded));
      }
    } catch (_) {}
    return null;
  }

  static void clearSession() {
    platformStorageRemove(_sessionKey);
  }

  static void saveProvisionedTenants(List<Map<String, dynamic>> tenants) {
    platformStorageSet(_provisionedTenantsKey, jsonEncode(tenants));
  }

  static List<Map<String, dynamic>> loadProvisionedTenants() {
    final raw = platformStorageGet(_provisionedTenantsKey);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        return decoded
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
      }
    } catch (_) {}
    return const [];
  }

  static void saveDeletedTenantSlugs(List<String> slugs) {
    platformStorageSet(_deletedTenantsKey, jsonEncode(slugs));
  }

  static List<String> loadDeletedTenantSlugs() {
    final raw = platformStorageGet(_deletedTenantsKey);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        return decoded.map((e) => e.toString().trim().toLowerCase()).toList();
      }
    } catch (_) {}
    return const [];
  }

  static const String _retailChainsKey = 'tashil_retail_chains_catalog_v1';
  static const String _deletedChainsKey = 'tashil_deleted_chains_v1';

  static void saveRetailChains(List<Map<String, dynamic>> chains) {
    platformStorageSet(_retailChainsKey, jsonEncode(chains));
  }

  static List<Map<String, dynamic>> loadRetailChains() {
    final raw = platformStorageGet(_retailChainsKey);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        return decoded
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
      }
    } catch (_) {}
    return const [];
  }

  static void saveDeletedChainCodes(List<String> codes) {
    platformStorageSet(_deletedChainsKey, jsonEncode(codes));
  }

  static List<String> loadDeletedChainCodes() {
    final raw = platformStorageGet(_deletedChainsKey);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        return decoded.map((e) => e.toString().trim().toLowerCase()).toList();
      }
    } catch (_) {}
    return const [];
  }

  static const String _deletedArchiveIdsKey = 'tashil_deleted_archive_ids_v1';
  static const String _deletedArchiveFileNamesKey =
      'tashil_deleted_archive_filenames_v1';
  static const String _clearedTenantsKey = 'tashil_cleared_tenants_v1';

  static void saveDeletedArchiveIds(Set<String> ids) {
    platformStorageSet(_deletedArchiveIdsKey, jsonEncode(ids.toList()));
  }

  static Set<String> loadDeletedArchiveIds() {
    final raw = platformStorageGet(_deletedArchiveIdsKey);
    if (raw == null || raw.isEmpty) return <String>{};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        return decoded
            .map((e) => e.toString().trim())
            .where((e) => e.isNotEmpty)
            .toSet();
      }
    } catch (_) {}
    return <String>{};
  }

  static void saveDeletedArchiveFileNames(Set<String> fileNames) {
    platformStorageSet(
        _deletedArchiveFileNamesKey, jsonEncode(fileNames.toList()));
  }

  static Set<String> loadDeletedArchiveFileNames() {
    final raw = platformStorageGet(_deletedArchiveFileNamesKey);
    if (raw == null || raw.isEmpty) return <String>{};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        return decoded
            .map((e) => e.toString().trim().toLowerCase())
            .where((e) => e.isNotEmpty)
            .toSet();
      }
    } catch (_) {}
    return <String>{};
  }

  static void saveClearedTenants(Set<String> tenants) {
    platformStorageSet(_clearedTenantsKey, jsonEncode(tenants.toList()));
  }

  static Set<String> loadClearedTenants() {
    final raw = platformStorageGet(_clearedTenantsKey);
    if (raw == null || raw.isEmpty) return <String>{};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        return decoded
            .map((e) => e.toString().trim().toLowerCase())
            .where((e) => e.isNotEmpty)
            .toSet();
      }
    } catch (_) {}
    return <String>{};
  }

  static void clearAll() {
    platformStorageClear();
  }

  static void updateBrowserUrl(String path) {
    platformUpdateUrl(path);
  }

  /// Replaces the current history entry (no new Back step).
  static void replaceBrowserUrl(String path) {
    platformReplaceUrl(path);
  }

  /// Current browser path on web; '' elsewhere.
  static String currentBrowserPath() => platformCurrentPath();

  /// A query parameter of the current URL (in-memory outside the browser).
  static String? browserQueryParam(String name) => platformQueryParam(name);

  /// Sets (or removes, when [value] is null/empty) one query parameter in
  /// place, keeping the path, the other parameters and the hash.
  static void replaceBrowserQueryParam(String name, String? value) =>
      platformReplaceQueryParam(name, value);
}
