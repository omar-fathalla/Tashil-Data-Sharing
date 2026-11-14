// ignore_for_file: avoid_web_libraries_in_flutter

import 'dart:convert';
import 'dart:html' as html;

import 'package:http/http.dart' as http;

/// Reads the postprocess stamp from `<html data-app-version="…">`.
String? readDocumentAppVersion() {
  final raw =
      html.document.documentElement?.getAttribute('data-app-version')?.trim();
  if (raw == null ||
      raw.isEmpty ||
      raw == '__TASHIL_APP_VERSION__') {
    return null;
  }
  return raw;
}

/// Loads `app_version` from the no-cache hosting `version.json`.
Future<String?> fetchVersionJsonAppVersion() async {
  try {
    final uri = Uri.parse(
      'version.json?t=${DateTime.now().millisecondsSinceEpoch}',
    );
    final res = await http.get(uri, headers: const {
      'Cache-Control': 'no-cache',
      'Pragma': 'no-cache',
    });
    if (res.statusCode != 200) return null;
    final decoded = jsonDecode(res.body);
    if (decoded is! Map) return null;
    final v = decoded['app_version']?.toString().trim();
    if (v == null || v.isEmpty) return null;
    return v;
  } catch (_) {
    return null;
  }
}
