/// Maps AppShell page indexes to URL path segments so a browser refresh
/// keeps the user on the same page, e.g. `/adeco/sell-in`.
class AppPageRoute {
  AppPageRoute._();

  /// True for `/`, empty path, or `/index.html` — the site root entry.
  /// Root must show company login (or redirect a valid session to the
  /// tenant portal); it must never resolve to a blank route.
  static bool isBareRoot(String path) {
    final p = path.trim().toLowerCase();
    return p.isEmpty || p == '/' || p == '/index.html';
  }

  static const List<String> pageSlugs = [
    'dashboard',
    'sell-out',
    'sell-in',
    'returns',
    'oos',
    'store-matrix',
    'pricing',
    'compare',
    'trade-marketing',
    'cpfr',
    'upload',
    'product-master',
    'data-errors',
  ];

  /// Page slug for [index]; empty for the Dashboard (index 0) or unknown.
  static String slugForIndex(int index) {
    if (index <= 0 || index >= pageSlugs.length) return '';
    return pageSlugs[index];
  }

  /// Page index for [slug], or 0 (Dashboard) when unknown.
  static int indexForSlug(String? slug) {
    final s = (slug ?? '').trim().toLowerCase();
    if (s.isEmpty) return 0;
    final i = pageSlugs.indexOf(s);
    return i < 0 ? 0 : i;
  }

  /// Path segments after stripping a leading `/portal/` prefix.
  static List<String> _segments(String path) {
    final segments = path
        .toLowerCase()
        .split('/')
        .where((s) => s.trim().isNotEmpty)
        .toList();
    if (segments.isNotEmpty && segments.first == 'portal') {
      segments.removeAt(0);
    }
    return segments;
  }

  /// Extracts the page slug from a URL path like `/adeco/sell-in` or
  /// `/portal/adeco/sell-in`. Returns '' when there is none or the
  /// segment is not a known page (see [unknownPageSlugFromPath]).
  static String pageSlugFromPath(String path) {
    final segments = _segments(path);
    if (segments.length < 2) return '';
    final candidate = segments[1].trim();
    return pageSlugs.contains(candidate) ? candidate : '';
  }

  /// The unknown page segment of `/{tenant}/{slug}` (or `/portal/...`),
  /// or null when the path has no page or the page is a known slug.
  /// `/adeco` and `/adeco/` are valid Dashboard URLs, not unknown.
  static String? unknownPageSlugFromPath(String path) {
    final segments = _segments(path);
    if (segments.length < 2) return null;
    final candidate = segments[1].trim();
    if (candidate.isEmpty || pageSlugs.contains(candidate)) return null;
    return candidate;
  }

  /// Known page slug, or the unknown segment if present, so a refresh
  /// or a post-login redirect can keep `/adeco/nope` on the Not Found
  /// page instead of silently rewriting to Dashboard.
  static String slugToPreserveFromPath(String path) {
    return unknownPageSlugFromPath(path) ?? pageSlugFromPath(path);
  }

  /// Builds the browser path for [tenant] and optional [pageSlug].
  static String pathFor(String tenant, [String pageSlug = '']) {
    final p = pageSlug.trim();
    return p.isEmpty ? '/$tenant' : '/$tenant/$p';
  }
}
