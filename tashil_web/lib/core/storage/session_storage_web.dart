// ignore_for_file: avoid_web_libraries_in_flutter

import 'dart:html' as html;

String? platformStorageGet(String key) {
  try {
    return html.window.localStorage[key];
  } catch (_) {
    return null;
  }
}

void platformStorageSet(String key, String value) {
  try {
    html.window.localStorage[key] = value;
  } catch (_) {}
}

void platformStorageRemove(String key) {
  try {
    html.window.localStorage.remove(key);
  } catch (_) {}
}

void platformStorageClear() {
  try {
    html.window.localStorage.clear();
  } catch (_) {}
}

void platformUpdateUrl(String path) {
  try {
    html.window.history.pushState(null, '', path);
  } catch (_) {}
}

void platformReplaceUrl(String path) {
  try {
    html.window.history.replaceState(null, '', path);
  } catch (_) {}
}

String? platformQueryParam(String name) {
  try {
    return Uri.parse(html.window.location.href).queryParameters[name];
  } catch (_) {
    return null;
  }
}

void platformReplaceQueryParam(String name, String? value) {
  try {
    final loc = html.window.location;
    final params =
        Map<String, String>.of(Uri.parse(loc.href).queryParameters);
    if (value == null || value.isEmpty) {
      params.remove(name);
    } else {
      params[name] = value;
    }
    final query = params.isEmpty ? '' : '?${Uri(queryParameters: params).query}';
    html.window.history
        .replaceState(null, '', '${loc.pathname ?? ''}$query${loc.hash}');
  } catch (_) {}
}

String platformCurrentPath() {
  try {
    return html.window.location.pathname ?? '';
  } catch (_) {
    return '';
  }
}
