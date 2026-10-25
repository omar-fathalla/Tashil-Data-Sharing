import 'dart:convert';

import 'package:tashil_web/core/network/backend_http.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_endpoints.dart';

/// Default discounts used for every chain that has no saved profile (backend uses the same values).
const double kDefaultInvoiceDiscountPct = 10.0;
const double kDefaultAdditionalDiscountPct = 0.0;

/// One chain's discounts. Percentages are whole numbers (10 = 10%).
class ChainDiscountProfileModel {
  final String chain;
  final double invoiceDiscountPct;
  final double additionalDiscountPct;
  final DateTime? updatedAt;
  final String updatedBy;

  const ChainDiscountProfileModel({
    required this.chain,
    required this.invoiceDiscountPct,
    required this.additionalDiscountPct,
    this.updatedAt,
    this.updatedBy = '',
  });

  factory ChainDiscountProfileModel.fromJson(Map<String, dynamic> j) => ChainDiscountProfileModel(
        chain: (j['chain'] ?? '').toString(),
        invoiceDiscountPct: _toDouble(j['invoice_discount_pct']),
        additionalDiscountPct: _toDouble(j['additional_discount_pct']),
        updatedAt: DateTime.tryParse((j['updated_at'] ?? '').toString()),
        updatedBy: (j['updated_by'] ?? '').toString(),
      );

  Map<String, dynamic> toJson() => {
        'chain': chain,
        'invoice_discount_pct': invoiceDiscountPct,
        'additional_discount_pct': additionalDiscountPct,
      };

  /// Cost per piece = list price incl. VAT × (1 − invoice%) × (1 − additional%).
  double netUnitCost(double unitPriceInclVat) =>
      unitPriceInclVat * (1 - invoiceDiscountPct / 100) * (1 - additionalDiscountPct / 100);

  static String key(String chain) => chain.trim().toLowerCase();
}

double _toDouble(dynamic v) => v is num ? v.toDouble() : double.tryParse('$v') ?? 0.0;

class ChainDiscountException implements Exception {
  final String message;
  const ChainDiscountException(this.message);
  @override
  String toString() => message;
}

/// GET / PUT `/api/v1/product-master/chain-discounts` (per tenant, stored in Firestore).
class ChainDiscountRepository {
  final ApiClient api;
  ChainDiscountRepository(this.api);

  // Offline-only fallback: holds what the user entered in this session, never invented values.
  static final Map<String, List<ChainDiscountProfileModel>> _offline = {};

  Future<List<ChainDiscountProfileModel>> load() async {
    try {
      final res = await BackendHttp.get(
        Uri.parse(ApiEndpoints.productMasterChainDiscounts),
        headers: api.requestHeaders,
      ).timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) {
        return _parse(res.bodyBytes);
      }
      if (!api.allowMockFallback) {
        throw ChainDiscountException('تعذر تحميل خصومات السلاسل (HTTP ${res.statusCode})');
      }
    } catch (e) {
      if (!api.allowMockFallback) rethrow;
    }
    return List.of(_offline[api.tenantId] ?? const []);
  }

  /// Replaces the full list (add / edit / delete are all a new list).
  Future<List<ChainDiscountProfileModel>> save(List<ChainDiscountProfileModel> profiles) async {
    try {
      final res = await BackendHttp.put(
        Uri.parse(ApiEndpoints.productMasterChainDiscounts),
        headers: api.requestHeaders,
        body: jsonEncode({'profiles': profiles.map((p) => p.toJson()).toList()}),
      ).timeout(const Duration(seconds: 12));
      if (res.statusCode == 200) {
        return _parse(res.bodyBytes);
      }
      String msg = 'تعذر حفظ خصومات السلاسل (HTTP ${res.statusCode})';
      try {
        final err = (jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>)['error'];
        if (err != null) msg = '$msg: $err';
      } catch (_) {}
      if (!api.allowMockFallback || res.statusCode == 400 || res.statusCode == 403) {
        throw ChainDiscountException(msg);
      }
    } on ChainDiscountException {
      rethrow;
    } catch (e) {
      if (!api.allowMockFallback) rethrow;
    }
    _offline[api.tenantId] = List.of(profiles);
    return profiles;
  }

  List<ChainDiscountProfileModel> _parse(List<int> bytes) {
    final data = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
    final list = (data['profiles'] as List?) ?? const [];
    return list.whereType<Map<String, dynamic>>().map(ChainDiscountProfileModel.fromJson).toList();
  }
}
