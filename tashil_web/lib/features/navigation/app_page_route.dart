/// Maps AppShell page indexes to URL path segments so a browser refresh
/// keeps the user on the same page, e.g. `/adeco/sell-in`.
class AppPageRoute {
  AppPageRoute._();

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

  /// Extracts the page slug from a URL path like `/adeco/sell-in` or
  /// `/portal/adeco/sell-in`. Returns '' when there is none.
  static String pageSlugFromPath(String path) {
    final segments = path
        .toLowerCase()
        .split('/')
        .where((s) => s.trim().isNotEmpty)
        .toList();
    if (segments.isNotEmpty && segments.first == 'portal') {
      segments.removeAt(0);
    }
    if (segments.length < 2) return '';
    final candidate = segments[1].trim();
    return pageSlugs.contains(candidate) ? candidate : '';
  }

  /// Builds the browser path for [tenant] and optional [pageSlug].
  static String pathFor(String tenant, [String pageSlug = '']) {
    final p = pageSlug.trim();
    return p.isEmpty ? '/$tenant' : '/$tenant/$p';
  }
}
