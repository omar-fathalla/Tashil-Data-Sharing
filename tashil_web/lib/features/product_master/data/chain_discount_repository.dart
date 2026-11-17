import 'dart:async';
import 'dart:convert';

import 'package:tashil_web/core/network/backend_http.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_endpoints.dart';

/// Default discounts used for every chain that has no saved profile (backend uses the same values).
const double kDefaultInvoiceDiscountPct = 10.0;
const double kDefaultAdditionalDiscountPct = 0.0;
const double kDefaultVatRatePct = 14.0;

/// One chain's terms (VAT, invoice discount, extra discount). Percentages are whole numbers (10 = 10%).
class ChainDiscountProfileModel {
  final String chain;
  final double invoiceDiscountPct;
  final double additionalDiscountPct;

  /// null = not set on the server (the Product Master column, then 14%, applies).
  final double? vatRatePct;
  final DateTime? updatedAt;
  final String updatedBy;

  const ChainDiscountProfileModel({
    required this.chain,
    required this.invoiceDiscountPct,
    required this.additionalDiscountPct,
    this.vatRatePct,
    this.updatedAt,
    this.updatedBy = '',
  });

  /// The VAT shown / applied for this chain.
  double get effectiveVatRatePct => vatRatePct ?? kDefaultVatRatePct;

  factory ChainDiscountProfileModel.fromJson(Map<String, dynamic> j) => ChainDiscountProfileModel(
        chain: (j['chain'] ?? '').toString(),
        invoiceDiscountPct: _toDouble(j['invoice_discount_pct']),
        additionalDiscountPct: _toDouble(j['additional_discount_pct']),
        vatRatePct: j['vat_rate_pct'] is num ? (j['vat_rate_pct'] as num).toDouble() : null,
        updatedAt: DateTime.tryParse((j['updated_at'] ?? '').toString()),
        updatedBy: (j['updated_by'] ?? '').toString(),
      );

  Map<String, dynamic> toJson() => {
        'chain': chain,
        'invoice_discount_pct': invoiceDiscountPct,
        'additional_discount_pct': additionalDiscountPct,
        if (vatRatePct != null) 'vat_rate_pct': vatRatePct,
      };

  /// Cost per piece = list price × (1 − invoice%) × (1 − additional%) (same VAT basis as the list price).
  double netUnitCost(double unitPrice) =>
      unitPrice * (1 - invoiceDiscountPct / 100) * (1 - additionalDiscountPct / 100);

  static String key(String chain) => chain.trim().toLowerCase();
}

double _toDouble(dynamic v) => v is num ? v.toDouble() : double.tryParse('$v') ?? 0.0;

class ChainDiscountException implements Exception {
  final String message;
  const ChainDiscountException(this.message);
  @override
  String toString() => message;
}

const String kChainDiscountTimeoutMessage =
    'انتهت مهلة تحميل إعدادات السلاسل. تحقّق من الاتصال ثم أعد المحاولة.';
const String kChainDiscountConnectionMessage =
    'تعذّر الاتصال بالخادم لتحميل إعدادات السلاسل. أعد المحاولة بعد قليل.';

const String kKnownChainsTimeoutMessage =
    'انتهت مهلة تحميل السلاسل المعروفة. تحقّق من الاتصال ثم أعد المحاولة.';
const String kKnownChainsConnectionMessage =
    'تعذّر الاتصال بالخادم لتحميل السلاسل. أعد المحاولة بعد قليل.';
const String kKnownChainsFailedMessage =
    'تعذّر تحميل السلاسل المعروفة. أعد المحاولة.';
const String kKnownChainsEmptyMessage =
    'لا توجد سلاسل ببيانات مرفوعة حتى الآن. ارفع شيت Sell-In أو Sell-Out ثم أعد المحاولة.';
const String kKnownChainsAllAddedMessage =
    'كل السلاسل المعروفة مضافة بالفعل. عدّل السلسلة بالضغط على صفها في الجدول.';
const String kKnownChainsPickMessage = 'اختر سلسلة من القائمة';
const String kKnownChainsAlreadyAdded = 'مضافة بالفعل';

/// A chain the backend has already recognized in counted Sell-In / Sell-Out data.
/// [key] is the exact normalized value enrichment matches on (for example `fathalla`).
class KnownChain {
  final String key;
  final String displayName;
  final int rowCount;
  final int sellInRows;
  final int sellOutRows;
  final String lastDataDate;

  const KnownChain({
    required this.key,
    required this.displayName,
    this.rowCount = 0,
    this.sellInRows = 0,
    this.sellOutRows = 0,
    this.lastDataDate = '',
  });

  factory KnownChain.fromJson(Map<String, dynamic> j) {
    final key = (j['key'] ?? j['name'] ?? '').toString().trim();
    final display = (j['display_name'] ?? '').toString().trim();
    return KnownChain(
      key: key,
      displayName: display.isEmpty ? key : display,
      rowCount: j['row_count'] is num ? (j['row_count'] as num).toInt() : 0,
      sellInRows: j['sell_in_rows'] is num ? (j['sell_in_rows'] as num).toInt() : 0,
      sellOutRows: j['sell_out_rows'] is num ? (j['sell_out_rows'] as num).toInt() : 0,
      lastDataDate: (j['last_data_date'] ?? '').toString(),
    );
  }
}

/// User-facing Arabic text for a known-chains load failure (never a raw exception).
String friendlyKnownChainsError(Object error) {
  if (error is ChainDiscountException) return error.message;
  if (error is TimeoutException) return kKnownChainsTimeoutMessage;
  return kKnownChainsConnectionMessage;
}

/// User-facing Arabic text for a chain-terms load/save failure (never a raw exception).
String friendlyChainDiscountError(Object error) {
  if (error is ChainDiscountException) return error.message;
  if (error is TimeoutException) return kChainDiscountTimeoutMessage;
  return kChainDiscountConnectionMessage;
}

/// GET / PUT `/api/v1/product-master/chain-discounts` (per tenant, stored in Firestore).
class ChainDiscountRepository {
  final ApiClient api;
  ChainDiscountRepository(this.api);

  // Offline-only fallback: holds what the user entered in this session, never invented values.
  static final Map<String, List<ChainDiscountProfileModel>> _offline = {};

  /// Client budget for GET; the backend bounds its own read well below this.
  static Duration loadTimeout = const Duration(seconds: 20);

  Future<List<ChainDiscountProfileModel>> load() async {
    try {
      final res = await BackendHttp.get(
        Uri.parse(ApiEndpoints.productMasterChainDiscounts),
        headers: api.requestHeaders,
      ).timeout(loadTimeout);
      if (res.statusCode == 200) {
        return _parse(res.bodyBytes);
      }
      if (!api.allowMockFallback) {
        throw ChainDiscountException(res.statusCode == 504
            ? kChainDiscountTimeoutMessage
            : 'تعذّر تحميل إعدادات السلاسل (HTTP ${res.statusCode}). أعد المحاولة.');
      }
    } catch (e) {
      if (!api.allowMockFallback) {
        throw ChainDiscountException(friendlyChainDiscountError(e));
      }
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
      if (!api.allowMockFallback) {
        throw ChainDiscountException(e is TimeoutException
            ? 'انتهت مهلة حفظ إعدادات السلاسل. أعد المحاولة.'
            : 'تعذّر الاتصال بالخادم لحفظ إعدادات السلاسل. أعد المحاولة.');
      }
    }
    _offline[api.tenantId] = List.of(profiles);
    return profiles;
  }

  /// Chains with counted Sell-In / Sell-Out data. Never invents a name when the call fails.
  Future<List<KnownChain>> loadKnownChains() async {
    try {
      final res = await BackendHttp.get(
        Uri.parse(ApiEndpoints.productMasterChains),
        headers: api.requestHeaders,
      ).timeout(loadTimeout);
      if (res.statusCode == 200) {
        return _parseChains(res.bodyBytes);
      }
      throw ChainDiscountException(res.statusCode == 504
          ? kKnownChainsTimeoutMessage
          : kKnownChainsFailedMessage);
    } on ChainDiscountException {
      rethrow;
    } catch (e) {
      throw ChainDiscountException(friendlyKnownChainsError(e));
    }
  }

  List<KnownChain> _parseChains(List<int> bytes) {
    final data = jsonDecode(utf8.decode(bytes));
    if (data is! Map) return const [];
    final list = (data['chains'] as List?) ?? const [];
    final out = <KnownChain>[];
    for (final item in list) {
      if (item is! Map) continue;
      final chain = KnownChain.fromJson(Map<String, dynamic>.from(item));
      if (chain.key.isNotEmpty) out.add(chain);
    }
    return out;
  }

  List<ChainDiscountProfileModel> _parse(List<int> bytes) {
    final data = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
    final list = (data['profiles'] as List?) ?? const [];
    return list.whereType<Map<String, dynamic>>().map(ChainDiscountProfileModel.fromJson).toList();
  }
}
