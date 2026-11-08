import 'dart:convert';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_endpoints.dart';
import '../../../core/network/backend_http.dart';

/// One Gemini/deterministic Sell-In assist suggestion awaiting human approval.
class AssistSuggestion {
  final String id;
  final String kind; // layout | customer_chain
  final String status; // pending | approved | rejected
  final double confidence;
  final String mappingSource;
  final String modelUsed;
  final String reasonAr;
  final String filename;
  final String layout;
  final String customerNeedle;
  final String suggestedChain;
  final String envFragment;
  final List<String> sampleCustomers;

  const AssistSuggestion({
    required this.id,
    required this.kind,
    required this.status,
    this.confidence = 0,
    this.mappingSource = '',
    this.modelUsed = '',
    this.reasonAr = '',
    this.filename = '',
    this.layout = '',
    this.customerNeedle = '',
    this.suggestedChain = '',
    this.envFragment = '',
    this.sampleCustomers = const [],
  });

  factory AssistSuggestion.fromJson(Map<String, dynamic> j) {
    return AssistSuggestion(
      id: '${j['id'] ?? ''}',
      kind: '${j['kind'] ?? ''}',
      status: '${j['status'] ?? ''}',
      confidence: (j['confidence'] as num?)?.toDouble() ?? 0,
      mappingSource: '${j['mapping_source'] ?? ''}',
      modelUsed: '${j['model_used'] ?? ''}',
      reasonAr: '${j['reason_ar'] ?? ''}',
      filename: '${j['filename'] ?? ''}',
      layout: '${j['layout'] ?? ''}',
      customerNeedle: '${j['customer_needle'] ?? ''}',
      suggestedChain: '${j['suggested_chain'] ?? ''}',
      envFragment: '${j['env_fragment'] ?? ''}',
      sampleCustomers: [
        for (final s in (j['sample_customers'] as List?) ?? const []) '$s',
      ],
    );
  }

  bool get isLayout => kind == 'layout';
  bool get isChain => kind == 'customer_chain';
}

class AssistMetrics {
  final int suggested;
  final int approved;
  final int rejected;
  final int pending;
  final double approvalRate;
  final List<String> approvedFragments;

  const AssistMetrics({
    this.suggested = 0,
    this.approved = 0,
    this.rejected = 0,
    this.pending = 0,
    this.approvalRate = 0,
    this.approvedFragments = const [],
  });

  factory AssistMetrics.fromJson(Map<String, dynamic> j) {
    final m = (j['metrics'] is Map) ? Map<String, dynamic>.from(j['metrics'] as Map) : j;
    return AssistMetrics(
      suggested: (m['suggested'] as num?)?.toInt() ?? 0,
      approved: (m['approved'] as num?)?.toInt() ?? 0,
      rejected: (m['rejected'] as num?)?.toInt() ?? 0,
      pending: (m['pending'] as num?)?.toInt() ?? 0,
      approvalRate: (m['approval_rate'] as num?)?.toDouble() ?? 0,
      approvedFragments: [
        for (final f in (j['approved_fragments'] as List?) ?? const []) '$f',
      ],
    );
  }
}

abstract class SellInAssistDataSource {
  Future<List<AssistSuggestion>> list({String status = 'pending'});
  Future<AssistMetrics> metrics();
  Future<AssistSuggestion> decide(String action, String id);
  Future<List<AssistSuggestion>> suggestChains({
    required List<String> customers,
    String uploadChain = 'fathalla',
  });
  Future<AssistSuggestion> suggestLayout({
    required String filename,
    required List<List<String>> sample,
  });
}

class HttpSellInAssistDataSource implements SellInAssistDataSource {
  final ApiClient api;
  HttpSellInAssistDataSource(this.api);

  @override
  Future<List<AssistSuggestion>> list({String status = 'pending'}) async {
    final uri = Uri.parse(ApiEndpoints.sellInAssistSuggestions)
        .replace(queryParameters: {if (status.isNotEmpty) 'status': status});
    final res = await BackendHttp.get(uri, headers: api.requestHeaders).timeout(const Duration(seconds: 20));
    if (res.statusCode != 200) {
      throw Exception('تعذر تحميل اقتراحات Sell-In (HTTP ${res.statusCode})');
    }
    final j = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    return [
      for (final e in (j['suggestions'] as List?) ?? const [])
        if (e is Map) AssistSuggestion.fromJson(Map<String, dynamic>.from(e)),
    ];
  }

  @override
  Future<AssistMetrics> metrics() async {
    final res = await BackendHttp.get(
      Uri.parse(ApiEndpoints.sellInAssistMetrics),
      headers: api.requestHeaders,
    ).timeout(const Duration(seconds: 15));
    if (res.statusCode != 200) {
      throw Exception('تعذر تحميل مؤشرات المساعدة (HTTP ${res.statusCode})');
    }
    return AssistMetrics.fromJson(
      Map<String, dynamic>.from(jsonDecode(utf8.decode(res.bodyBytes)) as Map),
    );
  }

  @override
  Future<AssistSuggestion> decide(String action, String id) async {
    final url = action == 'approve' ? ApiEndpoints.sellInAssistApprove : ApiEndpoints.sellInAssistReject;
    final res = await BackendHttp.post(
      Uri.parse(url),
      headers: {...api.requestHeaders, 'Content-Type': 'application/json'},
      body: jsonEncode({'id': id}),
    ).timeout(const Duration(seconds: 30));
    final body = utf8.decode(res.bodyBytes);
    if (res.statusCode != 200) {
      var msg = 'فشل تنفيذ القرار (HTTP ${res.statusCode})';
      try {
        final j = jsonDecode(body);
        if (j is Map && j['error'] is String) msg = j['error'] as String;
      } catch (_) {}
      throw Exception(msg);
    }
    final j = jsonDecode(body) as Map<String, dynamic>;
    return AssistSuggestion.fromJson(Map<String, dynamic>.from(j['suggestion'] as Map));
  }

  @override
  Future<List<AssistSuggestion>> suggestChains({
    required List<String> customers,
    String uploadChain = 'fathalla',
  }) async {
    final res = await BackendHttp.post(
      Uri.parse(ApiEndpoints.sellInAssistSuggestChains),
      headers: {...api.requestHeaders, 'Content-Type': 'application/json'},
      body: jsonEncode({'customers': customers, 'upload_chain': uploadChain}),
    ).timeout(const Duration(seconds: 60));
    if (res.statusCode != 200) {
      throw Exception('تعذر اقتراح ربط العميل بالسلسلة (HTTP ${res.statusCode})');
    }
    final j = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    return [
      for (final e in (j['suggestions'] as List?) ?? const [])
        if (e is Map) AssistSuggestion.fromJson(Map<String, dynamic>.from(e)),
    ];
  }

  @override
  Future<AssistSuggestion> suggestLayout({
    required String filename,
    required List<List<String>> sample,
  }) async {
    final res = await BackendHttp.post(
      Uri.parse(ApiEndpoints.sellInAssistSuggestLayout),
      headers: {...api.requestHeaders, 'Content-Type': 'application/json'},
      body: jsonEncode({'filename': filename, 'sample': sample}),
    ).timeout(const Duration(seconds: 60));
    if (res.statusCode != 200) {
      throw Exception('تعذر اقتراح تخطيط الملف (HTTP ${res.statusCode})');
    }
    final j = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    return AssistSuggestion.fromJson(Map<String, dynamic>.from(j['suggestion'] as Map));
  }
}
