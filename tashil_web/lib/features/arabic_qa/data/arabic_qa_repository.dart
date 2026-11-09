import 'dart:convert';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_endpoints.dart';
import '../../../core/network/backend_http.dart';
import 'arabic_qa_models.dart';

abstract class ArabicQaDataSource {
  Future<ArabicQaAnswer> ask(String question);
  Future<List<ArabicQaCapability>> capabilities();
}

class HttpArabicQaDataSource implements ArabicQaDataSource {
  final ApiClient api;
  HttpArabicQaDataSource(this.api);

  @override
  Future<ArabicQaAnswer> ask(String question) async {
    final res = await BackendHttp.post(
      Uri.parse(ApiEndpoints.analyticsAsk),
      headers: {...api.requestHeaders, 'Content-Type': 'application/json'},
      body: jsonEncode({'question': question}),
    ).timeout(const Duration(seconds: 45));
    final body = utf8.decode(res.bodyBytes);
    if (res.statusCode != 200) {
      throw Exception('تعذر الحصول على إجابة (HTTP ${res.statusCode})');
    }
    return ArabicQaAnswer.fromJson(
      Map<String, dynamic>.from(jsonDecode(body) as Map),
    );
  }

  @override
  Future<List<ArabicQaCapability>> capabilities() async {
    final res = await BackendHttp.get(
      Uri.parse(ApiEndpoints.analyticsAskCapabilities),
      headers: api.requestHeaders,
    ).timeout(const Duration(seconds: 20));
    if (res.statusCode != 200) {
      throw Exception('تعذر تحميل قدرات الأسئلة (HTTP ${res.statusCode})');
    }
    final j = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    return [
      for (final e in (j['capabilities'] as List?) ?? const [])
        if (e is Map) ArabicQaCapability.fromJson(Map<String, dynamic>.from(e)),
    ];
  }
}
