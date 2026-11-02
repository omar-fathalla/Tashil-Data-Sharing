import 'dart:convert';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_endpoints.dart';
import '../../../core/network/backend_http.dart';

/// One customer name in the Sell-In customer registry.
class RegistryEntry {
  final String name;
  final String status; // pending | approved | rejected
  final String chain;
  final String aliasOf;
  final bool seeded;
  final String suggestedName;
  final String suggestionReason;
  final String uploadChain;
  final int rows;
  final double value;
  final List<String> months;
  final List<String> files;

  const RegistryEntry({
    required this.name,
    required this.status,
    this.chain = '',
    this.aliasOf = '',
    this.seeded = false,
    this.suggestedName = '',
    this.suggestionReason = '',
    this.uploadChain = '',
    this.rows = 0,
    this.value = 0,
    this.months = const [],
    this.files = const [],
  });

  factory RegistryEntry.fromJson(Map<String, dynamic> j) {
    var rows = 0;
    var value = 0.0;
    final months = <String>{};
    final files = <String>[];
    for (final q in (j['quarantine'] as List?) ?? const []) {
      if (q is! Map) continue;
      rows += (q['rows'] as num?)?.toInt() ?? 0;
      value += (q['value'] as num?)?.toDouble() ?? 0;
      for (final m in (q['months'] as List?) ?? const []) {
        months.add('$m');
      }
      if ('${q['file'] ?? ''}'.isNotEmpty) files.add('${q['file']}');
    }
    return RegistryEntry(
      name: '${j['name'] ?? ''}',
      status: '${j['status'] ?? ''}',
      chain: '${j['chain'] ?? ''}',
      aliasOf: '${j['alias_of'] ?? ''}',
      seeded: j['seeded'] == true,
      suggestedName: '${j['suggested_name'] ?? ''}',
      suggestionReason: '${j['suggestion_reason'] ?? ''}',
      uploadChain: '${j['upload_chain'] ?? ''}',
      rows: rows,
      value: value,
      months: months.toList()..sort(),
      files: files,
    );
  }
}

class RegistryDecisionResult {
  final List<String> reappliedFiles;
  final List<String> errors;
  const RegistryDecisionResult({this.reappliedFiles = const [], this.errors = const []});
}

abstract class CustomerRegistryDataSource {
  Future<List<RegistryEntry>> list({String status = ''});
  Future<RegistryDecisionResult> decide(String action, String name, {String chain = '', String aliasOf = '', String reason = ''});
}

class HttpCustomerRegistryDataSource implements CustomerRegistryDataSource {
  final ApiClient api;
  HttpCustomerRegistryDataSource(this.api);

  @override
  Future<List<RegistryEntry>> list({String status = ''}) async {
    final uri = Uri.parse(ApiEndpoints.customerRegistry)
        .replace(queryParameters: {if (status.isNotEmpty) 'status': status});
    final res = await BackendHttp.get(uri, headers: api.requestHeaders).timeout(const Duration(seconds: 20));
    if (res.statusCode != 200) throw Exception('تعذر تحميل قائمة العملاء (HTTP ${res.statusCode})');
    final j = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    return [
      for (final e in (j['entries'] as List?) ?? const [])
        if (e is Map) RegistryEntry.fromJson(Map<String, dynamic>.from(e)),
    ];
  }

  @override
  Future<RegistryDecisionResult> decide(String action, String name,
      {String chain = '', String aliasOf = '', String reason = ''}) async {
    final res = await BackendHttp.post(
      Uri.parse('${ApiEndpoints.customerRegistry}/$action'),
      headers: {...api.requestHeaders, 'Content-Type': 'application/json'},
      body: jsonEncode({'name': name, 'chain': chain, 'alias_of': aliasOf, 'reason': reason}),
    ).timeout(const Duration(seconds: 180));
    final body = utf8.decode(res.bodyBytes);
    if (res.statusCode != 200) {
      var msg = 'فشل تنفيذ القرار (HTTP ${res.statusCode})';
      try {
        final j = jsonDecode(body);
        if (j is Map && j['message'] is String) msg = j['message'] as String;
      } catch (_) {}
      throw Exception(msg);
    }
    final j = jsonDecode(body) as Map<String, dynamic>;
    return RegistryDecisionResult(
      reappliedFiles: [for (final f in (j['reapplied_files'] as List?) ?? const []) '$f'],
      errors: [for (final f in (j['errors'] as List?) ?? const []) '$f'],
    );
  }
}
