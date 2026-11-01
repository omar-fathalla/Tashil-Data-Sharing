import 'package:flutter/widgets.dart';

import '../network/backend_http.dart';

/// Lets a data screen refresh itself silently when cached backend data changes
/// (background revalidation found new content, or an upload/edit/delete happened).
/// Cached data is shown instantly on return; this only fires on real changes.
mixin DataRefreshMixin<T extends StatefulWidget> on State<T> {
  /// Reload the screen's data. Repository reads are served from the fresh cache.
  void onBackendDataChanged();

  void _handleRevision() {
    // Deferred so app-level caches listening to the same signal clear first.
    Future<void>.microtask(() {
      if (mounted) onBackendDataChanged();
    });
  }

  @override
  void initState() {
    super.initState();
    BackendHttp.dataRevision.addListener(_handleRevision);
  }

  @override
  void dispose() {
    BackendHttp.dataRevision.removeListener(_handleRevision);
    super.dispose();
  }
}
