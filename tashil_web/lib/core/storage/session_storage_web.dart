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
