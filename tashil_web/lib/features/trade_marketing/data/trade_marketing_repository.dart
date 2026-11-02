import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:tashil_web/core/network/backend_http.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_endpoints.dart';
import '../domain/trade_marketing_models.dart';

/// Error raised by [TradeMarketingRepository] calls, with a user-facing message.
class TradeMarketingException implements Exception {
  final String message;
  final int? statusCode;
  const TradeMarketingException(this.message, {this.statusCode});

  bool get isUnauthorized => statusCode == 401;

  @override
  String toString() => message;
}

/// Server-side sales baselines for one chain + month (from ingested Excel sell-out / sell-in).
class TradeMarketingSalesBaseline {
  final int year;
  final int month;
  final String chainName;
  final double currentMonthSalesEgp;
  final double previousMonthSalesEgp;
  final double lastYearSameMonthSalesEgp;
  final double currentMonthSellInEgp;
  final double marketingSpendEgp;

  const TradeMarketingSalesBaseline({
    required this.year,
    required this.month,
    required this.chainName,
    required this.currentMonthSalesEgp,
    required this.previousMonthSalesEgp,
    required this.lastYearSameMonthSalesEgp,
    required this.currentMonthSellInEgp,
    this.marketingSpendEgp = 0,
  });

  factory TradeMarketingSalesBaseline.fromJson(Map<String, dynamic> j) => TradeMarketingSalesBaseline(
        year: _toInt(j['year']),
        month: _toInt(j['month']),
        chainName: (j['chain_name'] ?? '').toString(),
        currentMonthSalesEgp: _toDouble(j['current_month_sales_egp']),
        previousMonthSalesEgp: _toDouble(j['previous_month_sales_egp']),
        lastYearSameMonthSalesEgp: _toDouble(j['last_year_same_month_sales_egp']),
        currentMonthSellInEgp: _toDouble(j['current_month_sell_in_egp']),
        marketingSpendEgp: _toDouble(j['marketing_spend_egp']),
      );
}

/// Result of an Excel/CSV expense upload.
class ExpenseUploadResult {
  final int savedCount;
  final int rejectedCount;
  final List<String> rejectedReasons;
  const ExpenseUploadResult(this.savedCount, this.rejectedCount, this.rejectedReasons);
}

/// Normalises chain names so "Beet El Gomla" and "beet-elgomla" match (same rule as the backend).
String normalizeTradeMarketingChain(String s) =>
    s.toLowerCase().replaceAll(RegExp(r'[^\p{L}\p{N}]', unicode: true), '');

String tradeMarketingBaselineKey(int year, int month, String chain) =>
    '${year}_${month}_${normalizeTradeMarketingChain(chain)}';

int _toInt(dynamic v) => v is num ? v.toInt() : int.tryParse('$v') ?? 0;
double _toDouble(dynamic v) => v is num ? v.toDouble() : double.tryParse('$v') ?? 0.0;

MarketingExpenseItem marketingExpenseFromJson(Map<String, dynamic> j) => MarketingExpenseItem(
      id: (j['id'] ?? '').toString(),
      year: _toInt(j['year']),
      month: _toInt(j['month']),
      chainName: (j['chain_name'] ?? '').toString(),
      category: MarketingExpenseCategory.fromId((j['category'] ?? '').toString()),
      brandName: (j['brand_name'] ?? '').toString(),
      campaignTitle: (j['campaign_title'] ?? '').toString(),
      vendorOrAgency: (j['vendor_or_agency'] ?? '').toString(),
      amountEgp: _toDouble(j['amount_egp']),
      notes: (j['notes'] ?? '').toString(),
      createdAt: DateTime.tryParse((j['created_at'] ?? '').toString()) ?? DateTime.now(),
    );

Map<String, dynamic> marketingExpenseToJson(MarketingExpenseItem e) => {
      'year': e.year,
      'month': e.month,
      'chain_name': e.chainName,
      'category': e.category.id,
      'brand_name': e.brandName,
      'campaign_title': e.campaignTitle,
      'vendor_or_agency': e.vendorOrAgency,
      'amount_egp': e.amountEgp,
      'notes': e.notes,
    };

/// Data access for the Trade Marketing ROI screen.
abstract class TradeMarketingRepository {
  Future<List<MarketingExpenseItem>> listExpenses({int? year, int? month, String? chain});

  /// Creates (when [isNew]) or updates an expense and returns the server copy.
  Future<MarketingExpenseItem> saveExpense(MarketingExpenseItem item, {required bool isNew});
  Future<void> deleteExpense(String id);
  Future<List<TradeMarketingSalesBaseline>> getRoi({int? year, int? month, String? chain});
  Future<ExpenseUploadResult> uploadExpenses(List<int> bytes, String filename);
}

/// HTTP implementation using the shared [ApiClient] auth/tenant headers.
class ApiTradeMarketingRepository implements TradeMarketingRepository {
  final ApiClient apiClient;
  final http.Client _http;
  static const _timeout = Duration(seconds: 15);

  ApiTradeMarketingRepository(this.apiClient, {http.Client? httpClient}) : _http = httpClient ?? http.Client();

  Uri _uri(String base, Map<String, Object?> q) {
    final params = <String, String>{
      for (final e in q.entries)
        if (e.value != null && '${e.value}'.isNotEmpty && '${e.value}' != '0' && '${e.value}' != 'all') e.key: '${e.value}',
    };
    return Uri.parse(base).replace(queryParameters: params.isEmpty ? null : params);
  }

  Map<String, dynamic> _decode(http.Response resp) {
    Map<String, dynamic> body = const {};
    try {
      final d = jsonDecode(utf8.decode(resp.bodyBytes));
      if (d is Map<String, dynamic>) body = d;
    } catch (_) {}
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      final msg = body['error']?.toString() ??
          (resp.statusCode == 401 ? 'انتهت الجلسة، يرجى تسجيل الدخول مرة أخرى' : 'Server error ${resp.statusCode}');
      throw TradeMarketingException(msg, statusCode: resp.statusCode);
    }
    return body;
  }

  Future<http.Response> _guard(Future<http.Response> f) async {
    try {
      final r = await f.timeout(_timeout);
      BackendHttp.onResponseStatus?.call(
          r.statusCode, r.request?.url ?? Uri(), r.request?.headers['Authorization']);
      return r;
    } catch (e) {
      throw const TradeMarketingException('تعذر الاتصال بالخادم / Could not reach the server');
    }
  }

  @override
  Future<List<MarketingExpenseItem>> listExpenses({int? year, int? month, String? chain}) async {
    final resp = await _guard(_http.get(
      _uri(ApiEndpoints.tradeMarketingExpenses, {'year': year, 'month': month, 'chain': chain}),
      headers: apiClient.requestHeaders,
    ));
    final list = (_decode(resp)['expenses'] as List?) ?? const [];
    return list.whereType<Map<String, dynamic>>().map(marketingExpenseFromJson).toList();
  }

  @override
  Future<MarketingExpenseItem> saveExpense(MarketingExpenseItem item, {required bool isNew}) async {
    final body = jsonEncode(marketingExpenseToJson(item));
    final resp = await _guard(isNew
        ? _http.post(Uri.parse(ApiEndpoints.tradeMarketingExpenses), headers: apiClient.requestHeaders, body: body)
        : _http.put(Uri.parse(ApiEndpoints.tradeMarketingExpense(item.id)), headers: apiClient.requestHeaders, body: body));
    final e = _decode(resp)['expense'];
    if (e is! Map<String, dynamic>) throw const TradeMarketingException('Invalid server response');
    return marketingExpenseFromJson(e);
  }

  @override
  Future<void> deleteExpense(String id) async {
    final resp = await _guard(
      _http.delete(Uri.parse(ApiEndpoints.tradeMarketingExpense(id)), headers: apiClient.requestHeaders),
    );
    _decode(resp);
  }

  @override
  Future<List<TradeMarketingSalesBaseline>> getRoi({int? year, int? month, String? chain}) async {
    final resp = await _guard(_http.get(
      _uri(ApiEndpoints.tradeMarketingRoi, {'year': year, 'month': month, 'chain': chain}),
      headers: apiClient.requestHeaders,
    ));
    final list = (_decode(resp)['summaries'] as List?) ?? const [];
    return list.whereType<Map<String, dynamic>>().map(TradeMarketingSalesBaseline.fromJson).toList();
  }

  @override
  Future<ExpenseUploadResult> uploadExpenses(List<int> bytes, String filename) async {
    final req = http.MultipartRequest('POST', Uri.parse(ApiEndpoints.tradeMarketingExpensesUpload));
    req.headers.addAll(Map.of(apiClient.requestHeaders)..remove('Content-Type'));
    req.files.add(http.MultipartFile.fromBytes('file', bytes, filename: filename));
    final resp = await _guard(_http.send(req).then(http.Response.fromStream));
    final b = _decode(resp);
    final reasons = ((b['rejected'] as List?) ?? const [])
        .whereType<Map<String, dynamic>>()
        .map((r) => 'Row ${r['row']}: ${r['reason']}')
        .toList();
    return ExpenseUploadResult(_toInt(b['saved_count']), _toInt(b['rejected_count']), reasons);
  }
}
