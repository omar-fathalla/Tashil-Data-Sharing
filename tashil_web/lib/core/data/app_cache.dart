import '../network/api_client.dart';
import '../network/backend_http.dart';
import 'cache_store.dart';

/// App-level shared [CacheStore] used by every step-4 repository, so cached reads survive
/// leaving and re-opening a screen. Keys stay tenant/role aware ([CacheStore.key]).
///
/// Safety: the whole cache is cleared on logout ([clear], called from the app root) and,
/// independently of the auth module, whenever a repository is created for a different
/// session identity (tenant + user + role) than the last one ([forApi]).
class AppCache {
  AppCache._();

  static final CacheStore shared = CacheStore(defaultTtl: const Duration(minutes: 5));
  static String? _session;

  static String _identity(ApiClient api) {
    final u = api.currentUser;
    return [api.tenantId, u?.userId, u?.role, u?.assignedChain, u?.assignedRegion].join('|');
  }

  /// Returns [shared], clearing it first if the session identity changed.
  static CacheStore forApi(ApiClient api) {
    _hookRevisions();
    final id = _identity(api);
    if (_session != null && _session != id) {
      shared.clear();
      BackendHttp.cache.clear();
    }
    _session = id;
    return shared;
  }

  static bool _hooked = false;

  /// Parsed repository results are dropped whenever the HTTP layer learns the backend
  /// data changed, so the next read re-parses the fresh (already cached) response.
  static void _hookRevisions() {
    if (_hooked) return;
    _hooked = true;
    BackendHttp.dataRevision.addListener(shared.clearLocal);
  }

  /// Drops every cached entry (logout / tenant switch).
  static void clear() {
    shared.clear();
    BackendHttp.cache.clear();
    _session = null;
  }
}
